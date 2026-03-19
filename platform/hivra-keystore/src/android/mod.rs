//! Android keystore-backed seed storage.
//!
//! Seed material is stored as encrypted ciphertext through an Android-side
//! helper backed by Android Keystore. Rust keeps the account model and legacy
//! migration rules stable while delegating Android-specific secure storage
//! semantics to Kotlin via JNI.

use crate::{Error, Result, Seed};
use jni::objects::{GlobalRef, JClass, JObject, JString, JValue};
use jni::{JNIEnv, JavaVM};
use once_cell::sync::OnceCell;
use sha2::{Digest, Sha256};
use std::fs;
use std::path::{Path, PathBuf};

const PACKAGE_NAME: &str = "com.hivra.hivra_app";
const ACTIVE_SEED_ACCOUNT: &str = "active_capsule_seed_account";
const LEGACY_SEED_FILE: &str = "capsule_seed";

const STORE_METHOD: &str = "storeSeedBlob";
const LOAD_METHOD: &str = "loadSeedBlob";
const DELETE_METHOD: &str = "deleteSeedBlob";
const EXISTS_METHOD: &str = "seedBlobExists";

static JVM: OnceCell<JavaVM> = OnceCell::new();
static BRIDGE_OBJECT_REF: OnceCell<GlobalRef> = OnceCell::new();

#[no_mangle]
#[allow(missing_docs)]
pub extern "system" fn Java_com_hivra_hivra_1app_HivraKeystoreBridge_nativeInit(
    mut env: JNIEnv,
    class: JClass,
) {
    if let Ok(vm) = env.get_java_vm() {
        let _ = JVM.set(vm);
    }
    if let Ok(instance) = env.get_static_field(&class, "INSTANCE", "Lcom/hivra/hivra_app/HivraKeystoreBridge;")
        .and_then(|value| value.l())
        .and_then(|obj| env.new_global_ref(obj))
    {
        let _ = BRIDGE_OBJECT_REF.set(instance);
    }
}

/// Stores the capsule seed using Android Keystore-backed encrypted storage.
pub fn store_seed(seed: &Seed) -> Result<()> {
    let dir = keystore_dir()?;
    fs::create_dir_all(&dir)?;

    let account = seed_account(seed);
    let encoded = encode_hex(seed.as_bytes());
    if !store_seed_blob(&account, &encoded)? {
        return Err(Error::PlatformError(
            "Android keystore helper rejected seed write".to_string(),
        ));
    }
    fs::write(dir.join(ACTIVE_SEED_ACCOUNT), account)?;
    Ok(())
}

/// Loads the capsule seed using Android Keystore-backed encrypted storage.
pub fn load_seed() -> Result<Seed> {
    let dir = keystore_dir()?;

    if let Ok(account) = fs::read_to_string(dir.join(ACTIVE_SEED_ACCOUNT)) {
        let account = account.trim();
        match load_seed_from_account(account) {
            Ok(seed) => return Ok(seed),
            Err(Error::KeyNotFound) => {}
            Err(other) => return Err(other),
        }
    }

    let legacy_path = dir.join(LEGACY_SEED_FILE);
    let encoded = fs::read_to_string(&legacy_path).map_err(map_io_error)?;
    let seed = Seed::new(decode_hex_32(encoded.trim())?);
    let _ = store_seed(&seed);
    let _ = fs::remove_file(&legacy_path);
    Ok(seed)
}

/// Deletes the capsule seed from Android secure storage.
pub fn delete_seed() -> Result<()> {
    let dir = keystore_dir()?;

    if let Ok(account) = fs::read_to_string(dir.join(ACTIVE_SEED_ACCOUNT)) {
        let _ = delete_seed_blob(account.trim());
        let _ = fs::remove_file(dir.join(account.trim()));
    }
    let _ = fs::remove_file(dir.join(ACTIVE_SEED_ACCOUNT));
    let _ = fs::remove_file(dir.join(LEGACY_SEED_FILE));
    Ok(())
}

/// Returns `true` if a seed entry exists in Android secure storage.
pub fn seed_exists() -> bool {
    load_seed().is_ok()
}

fn load_seed_from_account(account: &str) -> Result<Seed> {
    match load_seed_blob(account)? {
        Some(encoded) => Ok(Seed::new(decode_hex_32(encoded.trim())?)),
        None => {
            let legacy_file = keystore_dir()?.join(account);
            let encoded = fs::read_to_string(&legacy_file).map_err(map_io_error)?;
            let seed = Seed::new(decode_hex_32(encoded.trim())?);
            let _ = store_seed(&seed);
            let _ = fs::remove_file(legacy_file);
            Ok(seed)
        }
    }
}

fn keystore_dir() -> Result<PathBuf> {
    let candidates = [
        format!("/data/user/0/{PACKAGE_NAME}/files/hivra-keystore"),
        format!("/data/data/{PACKAGE_NAME}/files/hivra-keystore"),
    ];

    for candidate in candidates {
        let path = PathBuf::from(candidate);
        if path.exists() || parent_exists(&path) {
            return Ok(path);
        }
    }

    Err(Error::PlatformError(
        "Android app-private files directory not available".to_string(),
    ))
}

fn parent_exists(path: &Path) -> bool {
    path.parent().is_some_and(Path::exists)
}

fn seed_account(seed: &Seed) -> String {
    let mut hasher = Sha256::new();
    hasher.update(seed.as_bytes());
    hasher.update(b"hivra_capsule_seed_account_v1");
    let hash = hasher.finalize();
    format!("capsule_seed:{}", encode_hex(hash.as_slice()))
}

fn map_io_error(err: std::io::Error) -> Error {
    match err.kind() {
        std::io::ErrorKind::NotFound => Error::KeyNotFound,
        _ => Error::IoError(err),
    }
}

fn with_bridge<T, F>(f: F) -> Result<T>
where
    F: FnOnce(&mut JNIEnv, &JObject) -> Result<T>,
{
    let vm = JVM
        .get()
        .ok_or_else(|| Error::PlatformError("Android JVM not initialized".to_string()))?;
    let bridge_ref = BRIDGE_OBJECT_REF
        .get()
        .ok_or_else(|| Error::PlatformError("Android bridge object not initialized".to_string()))?;

    let mut env = vm
        .attach_current_thread()
        .map_err(|e| Error::PlatformError(e.to_string()))?;
    f(&mut env, bridge_ref.as_obj())
}

fn store_seed_blob(account: &str, encoded_seed: &str) -> Result<bool> {
    with_bridge(|env, bridge| {
        let account = env
            .new_string(account)
            .map_err(|e| jni_error(env, "new_string(account)", e))?;
        let encoded_seed = env
            .new_string(encoded_seed)
            .map_err(|e| jni_error(env, "new_string(encoded_seed)", e))?;

        let result = env
            .call_method(
                bridge,
                STORE_METHOD,
                "(Ljava/lang/String;Ljava/lang/String;)Z",
                &[
                    JValue::Object(&JObject::from(account)),
                    JValue::Object(&JObject::from(encoded_seed)),
                ],
            )
            .map_err(|e| jni_error(env, "storeSeedBlob", e))?
            .z()
            .map_err(|e| jni_error(env, "storeSeedBlob result", e))?;
        Ok(result)
    })
}

fn load_seed_blob(account: &str) -> Result<Option<String>> {
    with_bridge(|env, bridge| {
        let account = env
            .new_string(account)
            .map_err(|e| jni_error(env, "new_string(account)", e))?;
        let result = env
            .call_method(
                bridge,
                LOAD_METHOD,
                "(Ljava/lang/String;)Ljava/lang/String;",
                &[JValue::Object(&JObject::from(account))],
            )
            .map_err(|e| jni_error(env, "loadSeedBlob", e))?
            .l()
            .map_err(|e| jni_error(env, "loadSeedBlob result", e))?;

        if result.is_null() {
            return Ok(None);
        }

        let text = env
            .get_string(&JString::from(result))
            .map_err(|e| jni_error(env, "loadSeedBlob get_string", e))?
            .to_str()
            .map_err(|e| Error::PlatformError(e.to_string()))?
            .to_string();
        Ok(Some(text))
    })
}

fn delete_seed_blob(account: &str) -> Result<bool> {
    with_bridge(|env, bridge| {
        let account = env
            .new_string(account)
            .map_err(|e| jni_error(env, "new_string(account)", e))?;
        let result = env
            .call_method(
                bridge,
                DELETE_METHOD,
                "(Ljava/lang/String;)Z",
                &[JValue::Object(&JObject::from(account))],
            )
            .map_err(|e| jni_error(env, "deleteSeedBlob", e))?
            .z()
            .map_err(|e| jni_error(env, "deleteSeedBlob result", e))?;
        Ok(result)
    })
}

#[allow(dead_code)]
fn seed_blob_exists(account: &str) -> Result<bool> {
    with_bridge(|env, bridge| {
        let account = env
            .new_string(account)
            .map_err(|e| jni_error(env, "new_string(account)", e))?;
        let result = env
            .call_method(
                bridge,
                EXISTS_METHOD,
                "(Ljava/lang/String;)Z",
                &[JValue::Object(&JObject::from(account))],
            )
            .map_err(|e| jni_error(env, "seedBlobExists", e))?
            .z()
            .map_err(|e| jni_error(env, "seedBlobExists result", e))?;
        Ok(result)
    })
}

fn jni_error(env: &mut JNIEnv, op: &str, err: impl ToString) -> Error {
    let mut message = format!("Android JNI {op} failed: {}", err.to_string());
    if matches!(env.exception_check(), Ok(true)) {
        let detail = env
            .exception_occurred()
            .ok()
            .and_then(|throwable| {
                let _ = env.exception_clear();
                env.call_method(&throwable, "toString", "()Ljava/lang/String;", &[])
                    .ok()?
                    .l()
                    .ok()
                    .and_then(|value| {
                        if value.is_null() {
                            return None;
                        }
                        env.get_string(&JString::from(value))
                            .ok()
                            .and_then(|text| text.to_str().ok().map(ToOwned::to_owned))
                    })
            });
        if let Some(detail) = detail {
            message.push_str(&format!(" (Java exception: {detail})"));
        } else {
            let _ = env.exception_describe();
            let _ = env.exception_clear();
            message.push_str(" (Java exception cleared)");
        }
    }
    Error::PlatformError(message)
}

fn encode_hex(bytes: &[u8]) -> String {
    const HEX: &[u8; 16] = b"0123456789abcdef";
    let mut out = String::with_capacity(bytes.len() * 2);
    for &b in bytes {
        out.push(HEX[(b >> 4) as usize] as char);
        out.push(HEX[(b & 0x0f) as usize] as char);
    }
    out
}

fn decode_hex_32(input: &str) -> Result<[u8; 32]> {
    if input.len() != 64 {
        return Err(Error::InvalidSeedLength(input.len() / 2));
    }

    let mut out = [0u8; 32];
    let bytes = input.as_bytes();
    for i in 0..32 {
        let hi = from_hex_nibble(bytes[i * 2])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in storage".to_string()))?;
        let lo = from_hex_nibble(bytes[i * 2 + 1])
            .ok_or_else(|| Error::PlatformError("Invalid seed encoding in storage".to_string()))?;
        out[i] = (hi << 4) | lo;
    }
    Ok(out)
}

fn from_hex_nibble(c: u8) -> Option<u8> {
    match c {
        b'0'..=b'9' => Some(c - b'0'),
        b'a'..=b'f' => Some(c - b'a' + 10),
        b'A'..=b'F' => Some(c - b'A' + 10),
        _ => None,
    }
}

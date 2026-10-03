use std::ffi::{CStr, CString};
use std::os::raw::c_char;
#[cfg(feature = "capsule-host")]
use std::os::raw::c_void;
use std::ptr;
use std::sync::Mutex;

use once_cell::sync::Lazy;

pub(crate) static LAST_ERROR: Lazy<Mutex<Option<String>>> = Lazy::new(|| Mutex::new(None));

pub(crate) fn set_last_error(message: impl Into<String>) {
    *LAST_ERROR.lock().unwrap() = Some(message.into());
}

pub(crate) fn clear_last_error() {
    *LAST_ERROR.lock().unwrap() = None;
}

mod ffi_support;
mod plugin_runtime_api;
pub use ffi_support::FfiBytes;

// The server uses the same WASM ABI without importing Capsule/Keychain APIs.
#[cfg(feature = "capsule-host")]
include!("capsule_host.rs");

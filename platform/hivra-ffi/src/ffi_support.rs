use super::*;

// The persisted v1 format is bincode 1.x's little-endian, fixed-width layout.
// This bounds allocation while admitting the existing 32 MiB payload budget
// plus quarantine policies, tombstones and record metadata. Do not use wincode's
// smaller default preallocation budget or introduce a new wire format here.
#[cfg(feature = "capsule-host")]
pub(crate) fn capsule_binary_config() -> impl wincode::config::Config {
    wincode::config::Configuration::default()
        .with_preallocation_size_limit::<{ 64 * 1024 * 1024 }>()
        .with_deserialization_size_limit::<{ 64 * 1024 * 1024 }>()
}

#[cfg(all(test, feature = "capsule-host"))]
mod binary_tests {
    use super::*;

    #[test]
    fn malformed_lengths_and_option_tags_fail_before_allocation() {
        for length in [u64::MAX, 64 * 1024 * 1024 + 1] {
            let bytes = length.to_le_bytes();
            assert!(
                wincode::config::deserialize::<Vec<u8>, _>(&bytes, capsule_binary_config())
                    .is_err()
            );
            assert!(
                wincode::config::deserialize::<String, _>(&bytes, capsule_binary_config()).is_err()
            );
        }
        assert!(
            wincode::config::deserialize::<Option<u64>, _>(&[2], capsule_binary_config()).is_err()
        );
    }
}

/// Structure for returning serialized bytes
#[repr(C)]
pub struct FfiBytes {
    pub data: *mut u8,
    pub len: usize,
}

/// Free string allocated by FFI
#[no_mangle]
pub unsafe extern "C" fn hivra_free_string(ptr: *mut c_char) {
    if !ptr.is_null() {
        let _ = CString::from_raw(ptr);
    }
}

/// Return the last FFI error string, if any.
#[no_mangle]
pub unsafe extern "C" fn hivra_last_error_message() -> *mut c_char {
    let message = LAST_ERROR.lock().unwrap().clone();
    match message {
        Some(message) => CString::new(message)
            .map(CString::into_raw)
            .unwrap_or(ptr::null_mut()),
        None => ptr::null_mut(),
    }
}

/// Free memory allocated by capsule_state_encode
#[no_mangle]
pub unsafe extern "C" fn free_bytes(ptr: *mut u8, len: usize) {
    if !ptr.is_null() {
        let _ = Vec::from_raw_parts(ptr, len, len);
    }
}

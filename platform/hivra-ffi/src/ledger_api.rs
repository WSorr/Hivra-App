use super::*;

/// Get complete capsule state in one FFI call
#[no_mangle]
pub unsafe extern "C" fn capsule_state_encode(_capsule_ptr: *const c_void) -> FfiBytes {
    if let Some(state) = current_capsule_state() {
        match bincode::serialize(&state) {
            Ok(bytes) => {
                let mut boxed = bytes.into_boxed_slice();
                let data = boxed.as_mut_ptr();
                let len = boxed.len();
                std::mem::forget(boxed);
                FfiBytes { data, len }
            }
            Err(_) => FfiBytes {
                data: ptr::null_mut(),
                len: 0,
            },
        }
    } else {
        FfiBytes {
            data: ptr::null_mut(),
            len: 0,
        }
    }
}


/// Export the current capsule state projection as JSON
#[no_mangle]
pub unsafe extern "C" fn hivra_export_capsule_state_json(out_json: *mut *mut c_char) -> i32 {
    if out_json.is_null() {
        return -1;
    }

    match current_capsule_state() {
        Some(state) => match serde_json::to_string(&state) {
            Ok(json) => match CString::new(json) {
                Ok(cstr) => {
                    *out_json = cstr.into_raw();
                    0
                }
                Err(_) => -2,
            },
            Err(_) => -2,
        },
        None => -3,
    }
}

/// Export the current ledger as JSON
#[no_mangle]
pub unsafe extern "C" fn hivra_export_ledger(out_json: *mut *mut c_char) -> i32 {
    if out_json.is_null() {
        return -1;
    }

    match export_runtime_ledger() {
        Ok(json) => match CString::new(json) {
            Ok(cstr) => {
                *out_json = cstr.into_raw();
                0
            }
            Err(_) => -2,
        },
        Err(_) => -2,
    }
}

/// Import a ledger from JSON and replace the runtime ledger
#[no_mangle]
pub unsafe extern "C" fn hivra_import_ledger(json_ptr: *const c_char) -> i32 {
    if json_ptr.is_null() {
        return -1;
    }

    let json = match CStr::from_ptr(json_ptr).to_str() {
        Ok(v) => v,
        Err(_) => return -2,
    };

    match import_runtime_ledger(json) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

/// Append a domain event to the runtime ledger.
///
/// Returns:
/// - 0 on success
/// - negative value on failure
#[no_mangle]
pub unsafe extern "C" fn hivra_ledger_append_event(
    kind: u8,
    payload_ptr: *const u8,
    payload_len: usize,
) -> i32 {
    if payload_len > 0 && payload_ptr.is_null() {
        return -1;
    }

    let event_kind = match event_kind_from_u8(kind) {
        Some(value) => value,
        None => return -2,
    };

    let payload = if payload_len == 0 {
        &[][..]
    } else {
        std::slice::from_raw_parts(payload_ptr, payload_len)
    };

    match append_runtime_event(event_kind, payload) {
        Ok(_) => 0,
        Err(_) => -3,
    }
}

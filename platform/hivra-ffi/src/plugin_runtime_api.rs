use super::*;

use hivra_wasm_runtime::invoke_json;

const INVALID_ARGUMENT: i32 = -1;
const RUNTIME_ERROR: i32 = -2;

#[no_mangle]
pub unsafe extern "C" fn hivra_wasm_invoke_json(
    module_ptr: *const u8,
    module_len: u64,
    entry_export: *const c_char,
    input_ptr: *const u8,
    input_len: u64,
    out_json: *mut *mut c_char,
) -> i32 {
    clear_last_error();
    if module_ptr.is_null()
        || module_len == 0
        || entry_export.is_null()
        || input_ptr.is_null()
        || input_len == 0
        || out_json.is_null()
    {
        set_last_error("invalid WASM invoke arguments");
        return INVALID_ARGUMENT;
    }
    *out_json = ptr::null_mut();
    let module_len = match usize::try_from(module_len) {
        Ok(value) => value,
        Err(_) => {
            set_last_error("WASM module length exceeds platform limits");
            return INVALID_ARGUMENT;
        }
    };
    let input_len = match usize::try_from(input_len) {
        Ok(value) => value,
        Err(_) => {
            set_last_error("WASM input length exceeds platform limits");
            return INVALID_ARGUMENT;
        }
    };

    let entry_export = match CStr::from_ptr(entry_export).to_str() {
        Ok(value) if !value.trim().is_empty() => value.trim(),
        _ => {
            set_last_error("invalid WASM entry export");
            return INVALID_ARGUMENT;
        }
    };
    let module = std::slice::from_raw_parts(module_ptr, module_len);
    let input = std::slice::from_raw_parts(input_ptr, input_len);
    let output = match invoke_json(module, entry_export, input) {
        Ok(output) => output,
        Err(error) => {
            set_last_error(error.to_string());
            return RUNTIME_ERROR;
        }
    };
    let output = match CString::new(output) {
        Ok(output) => output,
        Err(_) => {
            set_last_error("WASM output contains a NUL byte");
            return RUNTIME_ERROR;
        }
    };
    *out_json = output.into_raw();
    0
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn rejects_empty_arguments() {
        let mut out = ptr::null_mut();
        let code = unsafe {
            hivra_wasm_invoke_json(
                ptr::null(),
                0,
                ptr::null(),
                ptr::null(),
                0,
                &mut out,
            )
        };
        assert_eq!(code, INVALID_ARGUMENT);
        assert!(out.is_null());
    }
}

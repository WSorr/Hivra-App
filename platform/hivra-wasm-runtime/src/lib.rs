use std::fmt;

use wasmi::{Config, Engine, Linker, Module, Store, StoreLimitsBuilder};

pub const HOST_ABI_V2: &str = "hivra_host_abi_v2";
pub const ALLOC_EXPORT: &str = "hivra_alloc_v1";
pub const DEALLOC_EXPORT: &str = "hivra_dealloc_v1";
pub const DEFAULT_ENTRY_EXPORT: &str = "hivra_evaluate_v1";

const MAX_MODULE_BYTES: usize = 4 * 1024 * 1024;
const MAX_INPUT_BYTES: usize = 64 * 1024;
const MAX_OUTPUT_BYTES: usize = 128 * 1024;
const MAX_LINEAR_MEMORY_BYTES: usize = 128 * 1024 * 1024;
const FUEL_LIMIT: u64 = 5_000_000;

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum RuntimeError {
    ModuleTooLarge,
    InputTooLarge,
    InvalidModule(String),
    ImportsNotAllowed,
    InstantiationFailed(String),
    ExportMissing(&'static str),
    EntryExportMissing,
    SignatureMismatch(&'static str),
    FuelSetupFailed(String),
    AllocationFailed,
    MemoryAccessFailed(String),
    ExecutionFailed(String),
    OutputInvalid,
    OutputTooLarge,
}

impl fmt::Display for RuntimeError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Self::ModuleTooLarge => write!(f, "WASM module exceeds the size limit"),
            Self::InputTooLarge => write!(f, "WASM input exceeds the size limit"),
            Self::InvalidModule(error) => write!(f, "invalid WASM module: {error}"),
            Self::ImportsNotAllowed => write!(f, "WASM imports are not allowed"),
            Self::InstantiationFailed(error) => {
                write!(f, "WASM instantiation failed: {error}")
            }
            Self::ExportMissing(name) => write!(f, "required WASM export missing: {name}"),
            Self::EntryExportMissing => write!(f, "configured WASM entry export missing"),
            Self::SignatureMismatch(name) => {
                write!(f, "WASM export signature mismatch: {name}")
            }
            Self::FuelSetupFailed(error) => write!(f, "WASM fuel setup failed: {error}"),
            Self::AllocationFailed => write!(f, "WASM allocation failed"),
            Self::MemoryAccessFailed(error) => write!(f, "WASM memory access failed: {error}"),
            Self::ExecutionFailed(error) => write!(f, "WASM execution failed: {error}"),
            Self::OutputInvalid => write!(f, "WASM output pointer or length is invalid"),
            Self::OutputTooLarge => write!(f, "WASM output exceeds the size limit"),
        }
    }
}

impl std::error::Error for RuntimeError {}

pub fn invoke_json(
    module_bytes: &[u8],
    entry_export: &str,
    input_json: &[u8],
) -> Result<Vec<u8>, RuntimeError> {
    if module_bytes.len() > MAX_MODULE_BYTES {
        return Err(RuntimeError::ModuleTooLarge);
    }
    if input_json.is_empty() || input_json.len() > MAX_INPUT_BYTES {
        return Err(RuntimeError::InputTooLarge);
    }

    let mut config = Config::default();
    // Keep the existing binary-only, 32-bit memory ABI across runtime upgrades.
    config
        .consume_fuel(true)
        .wasm_memory64(false)
        .wasm_custom_page_sizes(false);
    let engine = Engine::new(&config);
    let module = Module::new(&engine, module_bytes)
        .map_err(|error| RuntimeError::InvalidModule(error.to_string()))?;
    if module.imports().next().is_some() {
        return Err(RuntimeError::ImportsNotAllowed);
    }

    let limits = StoreLimitsBuilder::new()
        .memory_size(MAX_LINEAR_MEMORY_BYTES)
        .memories(1)
        .tables(1)
        .instances(1)
        .trap_on_grow_failure(true)
        .build();
    let mut store = Store::new(&engine, limits);
    store.limiter(|limits| limits);
    store
        .set_fuel(FUEL_LIMIT)
        .map_err(|error| RuntimeError::FuelSetupFailed(error.to_string()))?;
    let linker = Linker::new(&engine);
    let instance = linker
        .instantiate(&mut store, &module)
        .and_then(|pre| pre.start(&mut store))
        .map_err(|error| RuntimeError::InstantiationFailed(error.to_string()))?;

    let memory = instance
        .get_memory(&store, "memory")
        .ok_or(RuntimeError::ExportMissing("memory"))?;
    let alloc = instance
        .get_typed_func::<u32, u32>(&store, ALLOC_EXPORT)
        .map_err(|_| RuntimeError::SignatureMismatch(ALLOC_EXPORT))?;
    let dealloc = instance
        .get_typed_func::<(u32, u32), ()>(&store, DEALLOC_EXPORT)
        .map_err(|_| RuntimeError::SignatureMismatch(DEALLOC_EXPORT))?;
    let evaluate = instance
        .get_typed_func::<(u32, u32), u64>(&store, entry_export)
        .map_err(|_| RuntimeError::EntryExportMissing)?;

    let input_len = input_json.len() as u32;
    let input_ptr = alloc
        .call(&mut store, input_len)
        .map_err(|error| RuntimeError::ExecutionFailed(error.to_string()))?;
    if input_ptr == 0 {
        return Err(RuntimeError::AllocationFailed);
    }
    memory
        .write(&mut store, input_ptr as usize, input_json)
        .map_err(|error| RuntimeError::MemoryAccessFailed(error.to_string()))?;

    let packed = evaluate
        .call(&mut store, (input_ptr, input_len))
        .map_err(|error| RuntimeError::ExecutionFailed(error.to_string()));
    let _ = dealloc.call(&mut store, (input_ptr, input_len));
    let packed = packed?;

    let output_ptr = (packed >> 32) as u32;
    let output_len = packed as u32;
    if output_ptr == 0 || output_len == 0 {
        return Err(RuntimeError::OutputInvalid);
    }
    if output_len as usize > MAX_OUTPUT_BYTES {
        let _ = dealloc.call(&mut store, (output_ptr, output_len));
        return Err(RuntimeError::OutputTooLarge);
    }

    let mut output = vec![0u8; output_len as usize];
    let read_result = memory.read(&store, output_ptr as usize, &mut output);
    let _ = dealloc.call(&mut store, (output_ptr, output_len));
    read_result.map_err(|error| RuntimeError::MemoryAccessFailed(error.to_string()))?;
    Ok(output)
}

#[cfg(test)]
mod tests {
    use super::*;

    fn echo_module() -> Vec<u8> {
        wat::parse_str(echo_module_text()).expect("test WASM compiles")
    }

    fn echo_module_text() -> String {
        module_text(
            "local.get $ptr
                i64.extend_i32_u
                i64.const 32
                i64.shl
                local.get $len
                i64.extend_i32_u
                i64.or",
        )
    }

    fn module_text(entry_body: &str) -> String {
        format!(
            r#"
            (module
              (memory (export "memory") 1)
              (global $next (mut i32) (i32.const 1024))
              (func (export "hivra_alloc_v1") (param $len i32) (result i32)
                (local $ptr i32)
                global.get $next
                local.tee $ptr
                local.get $len
                i32.add
                global.set $next
                local.get $ptr)
              (func (export "hivra_dealloc_v1") (param i32 i32))
              (func (export "hivra_evaluate_v1") (param $ptr i32) (param $len i32) (result i64)
                {entry_body}))
            "#
        )
    }

    #[test]
    fn invokes_json_abi_without_host_imports() {
        let input = br#"{"hello":"hivra"}"#;
        let output =
            invoke_json(&echo_module(), DEFAULT_ENTRY_EXPORT, input).expect("invoke succeeds");
        assert_eq!(output, input);
    }

    #[test]
    fn rejects_modules_with_imports() {
        let module = wat::parse_str(
            r#"(module (import "host" "clock" (func)) (memory (export "memory") 1))"#,
        )
        .expect("test WASM compiles");
        assert_eq!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::ImportsNotAllowed),
        );
    }

    #[test]
    fn accepts_only_binary_wasm() {
        for bytes in [echo_module_text().into_bytes(), b"not a module".to_vec()] {
            assert!(matches!(
                invoke_json(&bytes, DEFAULT_ENTRY_EXPORT, b"{}"),
                Err(RuntimeError::InvalidModule(_)),
            ));
        }
    }

    #[test]
    fn rejects_new_memory_profiles() {
        for memory in [
            "(memory (export \"memory\") i64 1)",
            "(memory (export \"memory\") 1 (pagesize 1))",
        ] {
            let text = echo_module_text().replace("(memory (export \"memory\") 1)", memory);
            let module = wat::parse_str(text).expect("valid extended-memory WASM");
            assert!(matches!(
                invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
                Err(RuntimeError::InvalidModule(_)),
            ));
        }
    }

    #[test]
    fn preserves_module_and_input_size_limits() {
        assert_eq!(
            invoke_json(&vec![0; MAX_MODULE_BYTES + 1], DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::ModuleTooLarge),
        );
        let module = echo_module();
        for input in [Vec::new(), vec![b' '; MAX_INPUT_BYTES + 1]] {
            assert_eq!(
                invoke_json(&module, DEFAULT_ENTRY_EXPORT, &input),
                Err(RuntimeError::InputTooLarge),
            );
        }
        let input = vec![b' '; MAX_INPUT_BYTES];
        let module = wat::parse_str(
            echo_module_text().replace("(export \"memory\") 1", "(export \"memory\") 2"),
        )
        .unwrap();
        assert_eq!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, &input),
            Ok(input)
        );
    }

    #[test]
    fn bounds_execution_fuel() {
        let module = wat::parse_str(module_text("(loop br 0) i64.const 0")).unwrap();
        assert!(matches!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::ExecutionFailed(_)),
        ));
    }

    #[test]
    fn bounds_start_function_fuel() {
        let module = wat::parse_str(echo_module_text().replacen(
            "(module",
            "(module (func $start (loop br 0)) (start $start)",
            1,
        ))
        .unwrap();
        assert!(matches!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::InstantiationFailed(_)),
        ));
    }

    #[test]
    fn preserves_output_pointer_and_size_checks() {
        for packed in [0, 1u64 << 32, 1] {
            let module = wat::parse_str(module_text(&format!("i64.const {packed}"))).unwrap();
            assert_eq!(
                invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
                Err(RuntimeError::OutputInvalid),
            );
        }
        let too_large = (1u64 << 32) | (MAX_OUTPUT_BYTES as u64 + 1);
        let module = wat::parse_str(module_text(&format!("i64.const {too_large}"))).unwrap();
        assert_eq!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::OutputTooLarge),
        );
        let outside_memory = (65535u64 << 32) | 2;
        let module = wat::parse_str(module_text(&format!("i64.const {outside_memory}"))).unwrap();
        assert!(matches!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::MemoryAccessFailed(_)),
        ));
    }

    #[test]
    fn preserves_entry_export_contract() {
        let module =
            wat::parse_str(echo_module_text().replace(DEFAULT_ENTRY_EXPORT, "replacement_entry"))
                .unwrap();
        assert_eq!(
            invoke_json(&module, "replacement_entry", b"{}"),
            Ok(b"{}".to_vec())
        );
        assert_eq!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::EntryExportMissing),
        );
        let wrong_signature = module_text("i32.const 1").replace("(result i64)", "(result i32)");
        assert_eq!(
            invoke_json(
                &wat::parse_str(wrong_signature).unwrap(),
                DEFAULT_ENTRY_EXPORT,
                b"{}"
            ),
            Err(RuntimeError::EntryExportMissing),
        );
    }

    #[test]
    fn preserves_instance_memory_and_table_limits() {
        for extra in ["(memory 1)", "(table 1 funcref) (table 1 funcref)"] {
            let module = wat::parse_str(echo_module_text().replacen(
                "(module",
                &format!("(module {extra}"),
                1,
            ))
            .unwrap();
            assert!(matches!(
                invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
                Err(RuntimeError::InstantiationFailed(_)),
            ));
        }
    }

    #[test]
    fn replacement_modules_can_change_private_state_shape() {
        let outputs: [&[u8]; 2] = [
            br#"{"state":{"count":7}}"#,
            br#"{"state":["replacement",7]}"#,
        ];
        let modules: Vec<_> = outputs
            .iter()
            .map(|output| {
                let data: String = output.iter().map(|byte| format!("\\{byte:02x}")).collect();
                let packed = (4096u64 << 32) | output.len() as u64;
                wat::parse_str(module_text(&format!("i64.const {packed}")).replacen(
                    "(module",
                    &format!("(module (data (i32.const 4096) \"{data}\")"),
                    1,
                ))
                .unwrap()
            })
            .collect();
        for index in [0, 1, 0] {
            assert_eq!(
                invoke_json(&modules[index], DEFAULT_ENTRY_EXPORT, b"{}"),
                Ok(outputs[index].to_vec()),
            );
        }
    }

    #[test]
    fn rejects_module_exceeding_linear_memory_limit() {
        let module = wat::parse_str(
            r#"
            (module
              (memory (export "memory") 2049)
              (func (export "hivra_alloc_v1") (param i32) (result i32) i32.const 1)
              (func (export "hivra_dealloc_v1") (param i32 i32))
              (func (export "hivra_evaluate_v1") (param i32 i32) (result i64) i64.const 0))
            "#,
        )
        .expect("test WASM compiles");
        assert!(matches!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Err(RuntimeError::InstantiationFailed(_)),
        ));
    }

    #[test]
    fn allows_memory_at_limit_but_rejects_growth_beyond_it() {
        let echo = echo_module_text();
        let at_limit = echo.replace("(export \"memory\") 1", "(export \"memory\") 2048");
        let module = wat::parse_str(&at_limit).unwrap();
        assert_eq!(
            invoke_json(&module, DEFAULT_ENTRY_EXPORT, b"{}"),
            Ok(b"{}".to_vec())
        );
        let growing = at_limit.replace("local.get $ptr\n                i64.extend_i32_u", "i32.const 1\n                memory.grow\n                drop\n                local.get $ptr\n                i64.extend_i32_u");
        assert!(matches!(
            invoke_json(
                &wat::parse_str(growing).unwrap(),
                DEFAULT_ENTRY_EXPORT,
                b"{}"
            ),
            Err(RuntimeError::ExecutionFailed(_)),
        ));
    }
}

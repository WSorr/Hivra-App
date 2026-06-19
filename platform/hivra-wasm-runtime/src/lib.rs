use std::fmt;

use wasmi::{Config, Engine, Linker, Module, Store, StoreLimitsBuilder};

pub const HOST_ABI_V2: &str = "hivra_host_abi_v2";
pub const ALLOC_EXPORT: &str = "hivra_alloc_v1";
pub const DEALLOC_EXPORT: &str = "hivra_dealloc_v1";
pub const DEFAULT_ENTRY_EXPORT: &str = "hivra_evaluate_v1";

const MAX_MODULE_BYTES: usize = 4 * 1024 * 1024;
const MAX_INPUT_BYTES: usize = 64 * 1024;
const MAX_OUTPUT_BYTES: usize = 128 * 1024;
const MAX_LINEAR_MEMORY_BYTES: usize = 16 * 1024 * 1024;
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
    config.consume_fuel(true);
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
        wat::parse_str(
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
                local.get $ptr
                i64.extend_i32_u
                i64.const 32
                i64.shl
                local.get $len
                i64.extend_i32_u
                i64.or))
            "#,
        )
        .expect("test WASM compiles")
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
    fn rejects_module_exceeding_linear_memory_limit() {
        let module = wat::parse_str(
            r#"
            (module
              (memory (export "memory") 300)
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
}

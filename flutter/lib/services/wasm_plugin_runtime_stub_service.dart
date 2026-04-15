import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:crypto/crypto.dart';

import 'plugin_host_api_service.dart';

class WasmPluginRuntimeStubService {
  static const String runtimeMode = 'wasm_stub_v1';
  static const String requiredRuntimeAbi = 'hivra_host_abi_v1';
  static const String requiredEntryExport = 'hivra_entry_v1';
  static const int _maxEntryInstructionCount = 2048;
  static const int _maxEntryStackDepth = 512;

  const WasmPluginRuntimeStubService();

  Future<PluginRuntimeInvokeEvidence?> invoke({
    required PluginHostApiRequest request,
    required PluginRuntimeBinding binding,
  }) async {
    if (binding.source != 'external_package') {
      return null;
    }
    final runtimeAbi = binding.runtimeAbi?.trim() ?? '';
    final runtimeEntryExport = binding.runtimeEntryExport?.trim() ?? '';
    if (runtimeAbi != requiredRuntimeAbi) {
      throw const FormatException('Plugin runtime ABI mismatch');
    }
    if (runtimeEntryExport != requiredEntryExport) {
      throw const FormatException('Plugin runtime entry export mismatch');
    }
    final packagePath = binding.packageFilePath?.trim() ?? '';
    final packageKind = binding.packageKind?.trim().toLowerCase() ?? '';
    if (packagePath.isEmpty || packageKind.isEmpty) {
      return null;
    }
    final packageFile = File(packagePath);
    if (!await packageFile.exists()) {
      return null;
    }
    await _verifyPackageDigestIfPresent(
      packageFile: packageFile,
      expectedDigestHex: binding.packageDigestHex,
    );

    final resolvedModule = await _extractModule(
      packageFile: packageFile,
      packageKind: packageKind,
      runtimeModulePath: binding.runtimeModulePath,
    );
    if (resolvedModule == null || resolvedModule.bytes.isEmpty) {
      return null;
    }
    _validateWasmModule(resolvedModule.bytes);
    _validateExportedEntryFunction(
      resolvedModule.bytes,
      runtimeEntryExport,
    );

    final moduleDigestHex = sha256.convert(resolvedModule.bytes).toString();
    final argsCanonical = _canonicalJson(request.args);
    final invokeInput =
        '$runtimeMode|${request.pluginId}|${request.method}|${resolvedModule.moduleSelection}|${resolvedModule.modulePath}|$moduleDigestHex|$argsCanonical';
    final invokeDigestHex = sha256.convert(utf8.encode(invokeInput)).toString();

    return PluginRuntimeInvokeEvidence(
      mode: runtimeMode,
      modulePath: resolvedModule.modulePath,
      moduleSelection: resolvedModule.moduleSelection,
      moduleDigestHex: moduleDigestHex,
      invokeDigestHex: invokeDigestHex,
    );
  }

  Future<_ResolvedModule?> _extractModule({
    required File packageFile,
    required String packageKind,
    required String? runtimeModulePath,
  }) async {
    if (packageKind == 'wasm') {
      return _ResolvedModule(
        modulePath: 'package/module.wasm',
        moduleSelection: 'package_wasm',
        bytes: await packageFile.readAsBytes(),
      );
    }
    if (packageKind != 'zip') {
      return null;
    }

    final archiveBytes = await packageFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(archiveBytes, verify: true);
    final normalizedRuntimeModulePath =
        _normalizeArchivePath(runtimeModulePath, rejectParentTraversal: true);
    if (normalizedRuntimeModulePath != null) {
      final matched = archive.files.where(
        (entry) {
          if (!entry.isFile) return false;
          final normalizedEntryPath = _normalizeArchivePath(entry.name);
          return normalizedEntryPath == normalizedRuntimeModulePath;
        },
      );
      if (matched.isEmpty) {
        throw const FormatException(
          'Plugin runtime module_path not found in package',
        );
      }
      final moduleBytes = _archiveContentBytes(matched.first.content);
      if (moduleBytes == null) return null;
      return _ResolvedModule(
        modulePath: _normalizeArchivePath(matched.first.name)!,
        moduleSelection: 'manifest_module_path',
        bytes: moduleBytes,
      );
    }

    var sawWasmEntry = false;
    final wasmCandidates = <_ResolvedModuleCandidate>[];
    for (final entry in archive.files) {
      if (!entry.isFile) continue;
      if (entry.name.toLowerCase().endsWith('.wasm')) {
        sawWasmEntry = true;
      }
      final normalizedEntryPath = _normalizeArchivePath(entry.name);
      if (normalizedEntryPath == null) continue;
      if (!normalizedEntryPath.toLowerCase().endsWith('.wasm')) continue;
      wasmCandidates.add(
        _ResolvedModuleCandidate(
          entry: entry,
          normalizedPath: normalizedEntryPath,
        ),
      );
    }
    wasmCandidates.sort(
      (a, b) => a.normalizedPath.compareTo(b.normalizedPath),
    );
    if (wasmCandidates.isEmpty) {
      if (sawWasmEntry) {
        throw const FormatException(
          'Plugin package has no safe WASM module paths',
        );
      }
      return null;
    }
    final first = wasmCandidates.first;
    final moduleBytes = _archiveContentBytes(first.entry.content);
    if (moduleBytes == null) return null;
    return _ResolvedModule(
      modulePath: first.normalizedPath,
      moduleSelection: 'lexical_first_wasm',
      bytes: moduleBytes,
    );
  }

  List<int>? _archiveContentBytes(Object? content) {
    if (content is List<int>) {
      return content;
    }
    if (content is String) {
      return utf8.encode(content);
    }
    return null;
  }

  Future<void> _verifyPackageDigestIfPresent({
    required File packageFile,
    required String? expectedDigestHex,
  }) async {
    final expected = expectedDigestHex?.trim().toLowerCase() ?? '';
    if (expected.isEmpty) {
      return;
    }
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(expected)) {
      throw const FormatException('Plugin package digest shape is invalid');
    }
    final actual = sha256.convert(await packageFile.readAsBytes()).toString();
    if (actual != expected) {
      throw const FormatException('Plugin package digest mismatch');
    }
  }

  String? _normalizeArchivePath(
    String? rawPath, {
    bool rejectParentTraversal = false,
  }) {
    var normalized = rawPath?.trim() ?? '';
    if (normalized.isEmpty) {
      return null;
    }
    normalized = normalized.replaceAll('\\', '/');
    while (normalized.startsWith('./')) {
      normalized = normalized.substring(2);
    }
    while (normalized.startsWith('/')) {
      normalized = normalized.substring(1);
    }
    final segments = normalized.split('/');
    final hasParentTraversal =
        segments.any((segment) => segment.trim() == '..');
    if (hasParentTraversal) {
      if (rejectParentTraversal) {
        throw const FormatException(
          'Plugin runtime module_path must not include parent traversal',
        );
      }
      return null;
    }
    return normalized;
  }

  void _validateWasmModule(List<int> bytes) {
    if (bytes.length < 8) {
      throw const FormatException('WASM module is too small');
    }
    if (bytes[0] != 0x00 ||
        bytes[1] != 0x61 ||
        bytes[2] != 0x73 ||
        bytes[3] != 0x6d) {
      throw const FormatException('Invalid WASM header magic');
    }
    if (bytes[4] != 0x01 ||
        bytes[5] != 0x00 ||
        bytes[6] != 0x00 ||
        bytes[7] != 0x00) {
      throw const FormatException('Unsupported WASM binary version');
    }
  }

  void _validateExportedEntryFunction(
    List<int> bytes,
    String requiredExportName,
  ) {
    final scan = _scanModuleForEntryExport(
      bytes: bytes,
      requiredExportName: requiredExportName,
    );
    final entryFunctionIndex = scan.entryFunctionIndex;
    if (entryFunctionIndex == null) {
      throw const FormatException('WASM entry export symbol not found');
    }
    if (scan.hasImports) {
      throw const FormatException(
        'WASM imports are not supported in wasm_stub_v1',
      );
    }
    if (scan.hasStartSection) {
      throw const FormatException(
        'WASM start section is not supported in wasm_stub_v1',
      );
    }
    if (entryFunctionIndex < scan.importedFunctionCount) {
      throw const FormatException(
        'WASM entry export must reference module-defined function',
      );
    }
    final definedFunctionIndex =
        entryFunctionIndex - scan.importedFunctionCount;
    if (definedFunctionIndex < 0 ||
        definedFunctionIndex >= scan.functionTypeIndices.length) {
      throw const FormatException('Malformed WASM function section');
    }
    final typeIndex = scan.functionTypeIndices[definedFunctionIndex];
    if (typeIndex < 0 || typeIndex >= scan.functionTypes.length) {
      throw const FormatException('Malformed WASM type index');
    }
    final funcType = scan.functionTypes[typeIndex];
    if (funcType.paramCount != 0 || funcType.resultCount != 0) {
      throw const FormatException('WASM entry export signature mismatch');
    }
    _executeEntryFunction(
      scan: scan,
      definedFunctionIndex: definedFunctionIndex,
    );
  }

  _WasmModuleScan _scanModuleForEntryExport({
    required List<int> bytes,
    required String requiredExportName,
  }) {
    var offset = 8;
    var hasImports = false;
    var hasStartSection = false;
    var importedFunctionCount = 0;
    var functionTypes = <_WasmFuncType>[];
    var functionTypeIndices = <int>[];
    var codeBodies = <List<int>>[];
    int? entryFunctionIndex;
    while (offset < bytes.length) {
      final sectionId = bytes[offset];
      offset += 1;
      final sectionLengthRead = _readU32Leb128(bytes, offset);
      final sectionLength = sectionLengthRead.value;
      offset = sectionLengthRead.nextOffset;
      final sectionEnd = offset + sectionLength;
      if (sectionEnd > bytes.length) {
        throw const FormatException('Malformed WASM section length');
      }
      switch (sectionId) {
        case 1:
          functionTypes = _parseTypeSection(
            bytes: bytes,
            sectionStart: offset,
            sectionEnd: sectionEnd,
          );
          break;
        case 2:
          final importSummary = _parseImportSection(
            bytes: bytes,
            sectionStart: offset,
            sectionEnd: sectionEnd,
          );
          hasImports = hasImports || importSummary.totalImports > 0;
          importedFunctionCount += importSummary.importedFunctionCount;
          break;
        case 3:
          functionTypeIndices = _parseFunctionSection(
            bytes: bytes,
            sectionStart: offset,
            sectionEnd: sectionEnd,
          );
          break;
        case 7:
          entryFunctionIndex ??= _findExportedFunctionIndex(
            bytes: bytes,
            sectionStart: offset,
            sectionEnd: sectionEnd,
            requiredExportName: requiredExportName,
          );
          break;
        case 8:
          hasStartSection = true;
          break;
        case 10:
          codeBodies = _parseCodeSection(
            bytes: bytes,
            sectionStart: offset,
            sectionEnd: sectionEnd,
          );
          break;
        default:
          break;
      }
      offset = sectionEnd;
    }
    return _WasmModuleScan(
      hasImports: hasImports,
      hasStartSection: hasStartSection,
      importedFunctionCount: importedFunctionCount,
      functionTypes: functionTypes,
      functionTypeIndices: functionTypeIndices,
      codeBodies: codeBodies,
      entryFunctionIndex: entryFunctionIndex,
    );
  }

  List<List<int>> _parseCodeSection({
    required List<int> bytes,
    required int sectionStart,
    required int sectionEnd,
  }) {
    var offset = sectionStart;
    final countRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final count = countRead.value;
    offset = countRead.nextOffset;
    final bodies = <List<int>>[];
    for (var i = 0; i < count; i++) {
      final bodySizeRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      final bodySize = bodySizeRead.value;
      offset = bodySizeRead.nextOffset;
      final bodyEnd = offset + bodySize;
      if (bodyEnd > sectionEnd) {
        throw const FormatException('Malformed WASM code section');
      }
      bodies.add(bytes.sublist(offset, bodyEnd));
      offset = bodyEnd;
    }
    if (offset != sectionEnd) {
      throw const FormatException('Malformed WASM code section');
    }
    return bodies;
  }

  void _executeEntryFunction({
    required _WasmModuleScan scan,
    required int definedFunctionIndex,
  }) {
    if (scan.codeBodies.isEmpty ||
        definedFunctionIndex >= scan.codeBodies.length) {
      throw const FormatException('Malformed WASM code section');
    }
    final body = scan.codeBodies[definedFunctionIndex];
    var offset = 0;
    final localsDeclCountRead = _readU32Leb128(body, offset);
    final localsDeclCount = localsDeclCountRead.value;
    offset = localsDeclCountRead.nextOffset;
    for (var i = 0; i < localsDeclCount; i++) {
      final countRead = _readU32Leb128(body, offset);
      offset = countRead.nextOffset;
      if (offset >= body.length) {
        throw const FormatException('Malformed WASM local decl section');
      }
      offset += 1; // local value type
    }
    final state = _WasmExecutionState(stack: <_WasmStackValue>[]);
    final execution = _executeInstructionSequence(
      body: body,
      offset: offset,
      state: state,
      labelDepth: 0,
      allowElse: false,
    );
    if (!execution.terminatedByEnd ||
        execution.terminatedByElse ||
        execution.branchSignal != null) {
      throw const FormatException('Malformed WASM function body');
    }
    if (execution.nextOffset != body.length) {
      throw const FormatException('Malformed WASM function body tail');
    }
    if (state.stack.isNotEmpty) {
      throw const FormatException(
        'WASM entry execution left non-empty stack',
      );
    }
  }

  _WasmInstructionSequenceResult _executeInstructionSequence({
    required List<int> body,
    required int offset,
    required _WasmExecutionState state,
    required int labelDepth,
    required bool allowElse,
  }) {
    var cursor = offset;
    while (cursor < body.length) {
      _incrementInstructionCount(state);
      final opcode = body[cursor];
      cursor += 1;
      switch (opcode) {
        case 0x00:
          throw const FormatException(
              'WASM entry execution trapped: unreachable');
        case 0x01:
          break; // nop
        case 0x02:
          final blockTypeRead = _readBlockTypeVoid(body, cursor);
          cursor = blockTypeRead.nextOffset;
          final nested = _executeInstructionSequence(
            body: body,
            offset: cursor,
            state: state,
            labelDepth: labelDepth + 1,
            allowElse: false,
          );
          if (nested.branchSignal != null) {
            final blockTail = _scanInstructionSequence(
              body: body,
              offset: nested.nextOffset,
              allowElse: false,
            );
            if (!blockTail.terminatedByEnd || blockTail.terminatedByElse) {
              throw const FormatException(
                  'Malformed WASM structured control flow');
            }
            cursor = blockTail.nextOffset;
            final propagated =
                _propagateBranchAcrossBoundary(nested.branchSignal);
            if (propagated != null) {
              return _WasmInstructionSequenceResult(
                nextOffset: cursor,
                terminatedByEnd: false,
                terminatedByElse: false,
                branchSignal: propagated,
              );
            }
            break;
          }
          if (!nested.terminatedByEnd || nested.terminatedByElse) {
            throw const FormatException(
                'Malformed WASM structured control flow');
          }
          cursor = nested.nextOffset;
          break;
        case 0x03:
          throw const FormatException(
            'WASM loop opcode is not supported in wasm_stub_v1',
          );
        case 0x04:
          final blockTypeRead = _readBlockTypeVoid(body, cursor);
          cursor = blockTypeRead.nextOffset;
          final condition = _popI32(state.stack, opcode: opcode);
          if (condition != 0) {
            final thenResult = _executeInstructionSequence(
              body: body,
              offset: cursor,
              state: state,
              labelDepth: labelDepth + 1,
              allowElse: true,
            );
            if (thenResult.branchSignal != null) {
              cursor = _scanIfRemainderToEnd(
                body: body,
                offset: thenResult.nextOffset,
              );
              final propagated =
                  _propagateBranchAcrossBoundary(thenResult.branchSignal);
              if (propagated != null) {
                return _WasmInstructionSequenceResult(
                  nextOffset: cursor,
                  terminatedByEnd: false,
                  terminatedByElse: false,
                  branchSignal: propagated,
                );
              }
            } else if (thenResult.terminatedByElse) {
              cursor = _scanIfRemainderToEnd(
                body: body,
                offset: thenResult.nextOffset,
              );
            } else if (thenResult.terminatedByEnd) {
              cursor = thenResult.nextOffset;
            } else {
              throw const FormatException(
                  'Malformed WASM structured control flow');
            }
          } else {
            final thenScan = _scanInstructionSequence(
              body: body,
              offset: cursor,
              allowElse: true,
            );
            if (thenScan.terminatedByElse) {
              final elseResult = _executeInstructionSequence(
                body: body,
                offset: thenScan.nextOffset,
                state: state,
                labelDepth: labelDepth + 1,
                allowElse: false,
              );
              if (elseResult.branchSignal != null) {
                final elseTail = _scanInstructionSequence(
                  body: body,
                  offset: elseResult.nextOffset,
                  allowElse: false,
                );
                if (!elseTail.terminatedByEnd || elseTail.terminatedByElse) {
                  throw const FormatException(
                      'Malformed WASM structured control flow');
                }
                cursor = elseTail.nextOffset;
                final propagated =
                    _propagateBranchAcrossBoundary(elseResult.branchSignal);
                if (propagated != null) {
                  return _WasmInstructionSequenceResult(
                    nextOffset: cursor,
                    terminatedByEnd: false,
                    terminatedByElse: false,
                    branchSignal: propagated,
                  );
                }
              } else if (!elseResult.terminatedByEnd ||
                  elseResult.terminatedByElse) {
                throw const FormatException(
                    'Malformed WASM structured control flow');
              } else {
                cursor = elseResult.nextOffset;
              }
            } else if (thenScan.terminatedByEnd) {
              cursor = thenScan.nextOffset;
            } else {
              throw const FormatException(
                  'Malformed WASM structured control flow');
            }
          }
          break;
        case 0x05:
          if (!allowElse) {
            throw const FormatException('Unexpected WASM else opcode');
          }
          return _WasmInstructionSequenceResult(
            nextOffset: cursor,
            terminatedByEnd: false,
            terminatedByElse: true,
          );
        case 0x0b:
          return _WasmInstructionSequenceResult(
            nextOffset: cursor,
            terminatedByEnd: true,
            terminatedByElse: false,
          );
        case 0x0c:
          final depthRead = _readU32Leb128(body, cursor);
          cursor = depthRead.nextOffset;
          if (depthRead.value >= labelDepth) {
            throw const FormatException('WASM branch depth out of range');
          }
          return _WasmInstructionSequenceResult(
            nextOffset: cursor,
            terminatedByEnd: false,
            terminatedByElse: false,
            branchSignal: _WasmBranchSignal(depthRead.value),
          );
        case 0x0d:
          final depthRead = _readU32Leb128(body, cursor);
          cursor = depthRead.nextOffset;
          final condition = _popI32(state.stack, opcode: opcode);
          if (condition != 0) {
            if (depthRead.value >= labelDepth) {
              throw const FormatException('WASM branch depth out of range');
            }
            return _WasmInstructionSequenceResult(
              nextOffset: cursor,
              terminatedByEnd: false,
              terminatedByElse: false,
              branchSignal: _WasmBranchSignal(depthRead.value),
            );
          }
          break;
        case 0x1a:
          if (state.stack.isEmpty) {
            throw const FormatException('WASM stack underflow on drop');
          }
          state.stack.removeLast();
          break;
        case 0x41:
          final valueRead = _readS32Leb128(body, cursor);
          cursor = valueRead.nextOffset;
          _pushStackValue(state.stack, _WasmStackValue.i32(valueRead.value));
          break;
        case 0x42:
          final valueRead = _readS64Leb128(body, cursor);
          cursor = valueRead.nextOffset;
          _pushStackValue(state.stack, _WasmStackValue.i64(valueRead.value));
          break;
        case 0x43:
          if (cursor + 4 > body.length) {
            throw const FormatException('Malformed WASM f32.const payload');
          }
          cursor += 4;
          _pushStackValue(state.stack, const _WasmStackValue.f32());
          break;
        case 0x44:
          if (cursor + 8 > body.length) {
            throw const FormatException('Malformed WASM f64.const payload');
          }
          cursor += 8;
          _pushStackValue(state.stack, const _WasmStackValue.f64());
          break;
        case 0x6a:
          final rhs = _popI32(state.stack, opcode: opcode);
          final lhs = _popI32(state.stack, opcode: opcode);
          _pushStackValue(state.stack, _WasmStackValue.i32(lhs + rhs));
          break;
        case 0x6b:
          final rhs = _popI32(state.stack, opcode: opcode);
          final lhs = _popI32(state.stack, opcode: opcode);
          _pushStackValue(state.stack, _WasmStackValue.i32(lhs - rhs));
          break;
        case 0x6c:
          final rhs = _popI32(state.stack, opcode: opcode);
          final lhs = _popI32(state.stack, opcode: opcode);
          _pushStackValue(state.stack, _WasmStackValue.i32(lhs * rhs));
          break;
        default:
          throw _unsupportedOpcode(opcode);
      }
    }
    return _WasmInstructionSequenceResult(
      nextOffset: cursor,
      terminatedByEnd: false,
      terminatedByElse: false,
    );
  }

  _WasmScanSequenceResult _scanInstructionSequence({
    required List<int> body,
    required int offset,
    required bool allowElse,
  }) {
    var cursor = offset;
    while (cursor < body.length) {
      final opcode = body[cursor];
      cursor += 1;
      switch (opcode) {
        case 0x00:
        case 0x01:
        case 0x1a:
        case 0x6a:
        case 0x6b:
        case 0x6c:
          break;
        case 0x02:
          final blockTypeRead = _readBlockTypeVoid(body, cursor);
          cursor = blockTypeRead.nextOffset;
          final nested = _scanInstructionSequence(
            body: body,
            offset: cursor,
            allowElse: false,
          );
          if (!nested.terminatedByEnd || nested.terminatedByElse) {
            throw const FormatException(
                'Malformed WASM structured control flow');
          }
          cursor = nested.nextOffset;
          break;
        case 0x03:
          throw const FormatException(
            'WASM loop opcode is not supported in wasm_stub_v1',
          );
        case 0x04:
          final blockTypeRead = _readBlockTypeVoid(body, cursor);
          cursor = blockTypeRead.nextOffset;
          final thenResult = _scanInstructionSequence(
            body: body,
            offset: cursor,
            allowElse: true,
          );
          if (thenResult.terminatedByElse) {
            final elseResult = _scanInstructionSequence(
              body: body,
              offset: thenResult.nextOffset,
              allowElse: false,
            );
            if (!elseResult.terminatedByEnd || elseResult.terminatedByElse) {
              throw const FormatException(
                  'Malformed WASM structured control flow');
            }
            cursor = elseResult.nextOffset;
          } else if (thenResult.terminatedByEnd) {
            cursor = thenResult.nextOffset;
          } else {
            throw const FormatException(
                'Malformed WASM structured control flow');
          }
          break;
        case 0x05:
          if (!allowElse) {
            throw const FormatException('Unexpected WASM else opcode');
          }
          return _WasmScanSequenceResult(
            nextOffset: cursor,
            terminatedByEnd: false,
            terminatedByElse: true,
          );
        case 0x0b:
          return _WasmScanSequenceResult(
            nextOffset: cursor,
            terminatedByEnd: true,
            terminatedByElse: false,
          );
        case 0x0c:
        case 0x0d:
          final depthRead = _readU32Leb128(body, cursor);
          cursor = depthRead.nextOffset;
          break;
        case 0x41:
          final valueRead = _readS32Leb128(body, cursor);
          cursor = valueRead.nextOffset;
          break;
        case 0x42:
          final valueRead = _readS64Leb128(body, cursor);
          cursor = valueRead.nextOffset;
          break;
        case 0x43:
          if (cursor + 4 > body.length) {
            throw const FormatException('Malformed WASM f32.const payload');
          }
          cursor += 4;
          break;
        case 0x44:
          if (cursor + 8 > body.length) {
            throw const FormatException('Malformed WASM f64.const payload');
          }
          cursor += 8;
          break;
        default:
          throw _unsupportedOpcode(opcode);
      }
    }
    return _WasmScanSequenceResult(
      nextOffset: cursor,
      terminatedByEnd: false,
      terminatedByElse: false,
    );
  }

  int _scanIfRemainderToEnd({
    required List<int> body,
    required int offset,
  }) {
    final afterThen = _scanInstructionSequence(
      body: body,
      offset: offset,
      allowElse: true,
    );
    if (afterThen.terminatedByElse) {
      final elseScan = _scanInstructionSequence(
        body: body,
        offset: afterThen.nextOffset,
        allowElse: false,
      );
      if (!elseScan.terminatedByEnd || elseScan.terminatedByElse) {
        throw const FormatException('Malformed WASM structured control flow');
      }
      return elseScan.nextOffset;
    }
    if (!afterThen.terminatedByEnd || afterThen.terminatedByElse) {
      throw const FormatException('Malformed WASM structured control flow');
    }
    return afterThen.nextOffset;
  }

  _WasmBlockTypeRead _readBlockTypeVoid(List<int> body, int offset) {
    if (offset >= body.length) {
      throw const FormatException('Malformed WASM block type');
    }
    if (body[offset] != 0x40) {
      throw const FormatException(
          'Unsupported WASM block type in wasm_stub_v1');
    }
    return _WasmBlockTypeRead(nextOffset: offset + 1);
  }

  _WasmBranchSignal? _propagateBranchAcrossBoundary(
    _WasmBranchSignal? signal,
  ) {
    if (signal == null) {
      return null;
    }
    if (signal.depth == 0) {
      return null;
    }
    return _WasmBranchSignal(signal.depth - 1);
  }

  void _incrementInstructionCount(_WasmExecutionState state) {
    state.instructionCount += 1;
    if (state.instructionCount > _maxEntryInstructionCount) {
      throw const FormatException(
        'WASM instruction limit exceeded in wasm_stub_v1',
      );
    }
  }

  FormatException _unsupportedOpcode(int opcode) {
    final hex = opcode.toRadixString(16).padLeft(2, '0');
    return FormatException('Unsupported WASM opcode in wasm_stub_v1: 0x$hex');
  }

  void _pushStackValue(
    List<_WasmStackValue> stack,
    _WasmStackValue value,
  ) {
    if (stack.length >= _maxEntryStackDepth) {
      throw const FormatException(
        'WASM stack depth limit exceeded in wasm_stub_v1',
      );
    }
    stack.add(value);
  }

  int _popI32(
    List<_WasmStackValue> stack, {
    required int opcode,
  }) {
    if (stack.isEmpty) {
      throw const FormatException('WASM stack underflow');
    }
    final value = stack.removeLast();
    if (value.type != _WasmStackValueType.i32 || value.i32 == null) {
      final hex = opcode.toRadixString(16).padLeft(2, '0');
      throw FormatException('WASM type mismatch on opcode 0x$hex');
    }
    return value.i32!;
  }

  List<_WasmFuncType> _parseTypeSection({
    required List<int> bytes,
    required int sectionStart,
    required int sectionEnd,
  }) {
    var offset = sectionStart;
    final countRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final count = countRead.value;
    offset = countRead.nextOffset;
    final types = <_WasmFuncType>[];
    for (var i = 0; i < count; i++) {
      if (offset >= sectionEnd) {
        throw const FormatException('Malformed WASM type section');
      }
      final kind = bytes[offset];
      offset += 1;
      if (kind != 0x60) {
        throw const FormatException('Unsupported WASM function type');
      }
      final paramCountRead =
          _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      final paramCount = paramCountRead.value;
      offset = paramCountRead.nextOffset;
      final paramEnd = offset + paramCount;
      if (paramEnd > sectionEnd) {
        throw const FormatException('Malformed WASM type section');
      }
      offset = paramEnd;
      final resultCountRead =
          _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      final resultCount = resultCountRead.value;
      offset = resultCountRead.nextOffset;
      final resultEnd = offset + resultCount;
      if (resultEnd > sectionEnd) {
        throw const FormatException('Malformed WASM type section');
      }
      offset = resultEnd;
      types.add(
        _WasmFuncType(
          paramCount: paramCount,
          resultCount: resultCount,
        ),
      );
    }
    if (offset != sectionEnd) {
      throw const FormatException('Malformed WASM type section');
    }
    return types;
  }

  _WasmImportSummary _parseImportSection({
    required List<int> bytes,
    required int sectionStart,
    required int sectionEnd,
  }) {
    var offset = sectionStart;
    final countRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final count = countRead.value;
    offset = countRead.nextOffset;
    var importedFunctionCount = 0;
    for (var i = 0; i < count; i++) {
      final moduleNameRead = _readName(bytes, offset, sectionEnd: sectionEnd);
      offset = moduleNameRead.nextOffset;
      final fieldNameRead = _readName(bytes, offset, sectionEnd: sectionEnd);
      offset = fieldNameRead.nextOffset;
      if (offset >= sectionEnd) {
        throw const FormatException('Malformed WASM import section');
      }
      final importKind = bytes[offset];
      offset += 1;
      switch (importKind) {
        case 0x00:
          final typeIndexRead =
              _readU32Leb128(bytes, offset, endOffset: sectionEnd);
          offset = typeIndexRead.nextOffset;
          importedFunctionCount += 1;
          break;
        case 0x01:
          offset = _skipTableType(bytes, offset, sectionEnd: sectionEnd);
          break;
        case 0x02:
          offset = _skipLimits(bytes, offset, sectionEnd: sectionEnd);
          break;
        case 0x03:
          if (offset + 2 > sectionEnd) {
            throw const FormatException('Malformed WASM import section');
          }
          offset += 2;
          break;
        case 0x04:
          final attrRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
          offset = attrRead.nextOffset;
          final typeIndexRead =
              _readU32Leb128(bytes, offset, endOffset: sectionEnd);
          offset = typeIndexRead.nextOffset;
          break;
        default:
          throw const FormatException('Unsupported WASM import kind');
      }
    }
    if (offset != sectionEnd) {
      throw const FormatException('Malformed WASM import section');
    }
    return _WasmImportSummary(
      totalImports: count,
      importedFunctionCount: importedFunctionCount,
    );
  }

  int _skipTableType(
    List<int> bytes,
    int offset, {
    required int sectionEnd,
  }) {
    if (offset >= sectionEnd) {
      throw const FormatException('Malformed WASM table type');
    }
    offset += 1;
    return _skipLimits(bytes, offset, sectionEnd: sectionEnd);
  }

  int _skipLimits(
    List<int> bytes,
    int offset, {
    required int sectionEnd,
  }) {
    final flagsRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final flags = flagsRead.value;
    offset = flagsRead.nextOffset;
    final minRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    offset = minRead.nextOffset;
    final hasMax = (flags & 0x01) != 0;
    if (hasMax) {
      final maxRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      offset = maxRead.nextOffset;
    }
    return offset;
  }

  List<int> _parseFunctionSection({
    required List<int> bytes,
    required int sectionStart,
    required int sectionEnd,
  }) {
    var offset = sectionStart;
    final countRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final count = countRead.value;
    offset = countRead.nextOffset;
    final functionTypeIndices = <int>[];
    for (var i = 0; i < count; i++) {
      final typeIndexRead =
          _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      offset = typeIndexRead.nextOffset;
      functionTypeIndices.add(typeIndexRead.value);
    }
    if (offset != sectionEnd) {
      throw const FormatException('Malformed WASM function section');
    }
    return functionTypeIndices;
  }

  int? _findExportedFunctionIndex({
    required List<int> bytes,
    required int sectionStart,
    required int sectionEnd,
    required String requiredExportName,
  }) {
    var offset = sectionStart;
    final exportCountRead =
        _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final exportCount = exportCountRead.value;
    offset = exportCountRead.nextOffset;
    int? matchedFunctionIndex;
    for (var i = 0; i < exportCount; i++) {
      final exportNameRead = _readName(bytes, offset, sectionEnd: sectionEnd);
      offset = exportNameRead.nextOffset;
      if (offset >= sectionEnd) {
        throw const FormatException('Malformed WASM export section');
      }
      final kind = bytes[offset];
      offset += 1;
      final indexRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
      offset = indexRead.nextOffset;
      if (kind == 0 && exportNameRead.value == requiredExportName) {
        matchedFunctionIndex = indexRead.value;
      }
    }
    if (offset != sectionEnd) {
      throw const FormatException('Malformed WASM export section');
    }
    return matchedFunctionIndex;
  }

  _ReadResult<String> _readName(
    List<int> bytes,
    int offset, {
    required int sectionEnd,
  }) {
    final lengthRead = _readU32Leb128(bytes, offset, endOffset: sectionEnd);
    final length = lengthRead.value;
    final start = lengthRead.nextOffset;
    final end = start + length;
    if (end > sectionEnd) {
      throw const FormatException('Malformed WASM name');
    }
    final valueBytes = bytes.sublist(start, end);
    late final String value;
    try {
      value = utf8.decode(valueBytes);
    } catch (_) {
      throw const FormatException('Malformed WASM name');
    }
    return _ReadResult<String>(
      value: value,
      nextOffset: end,
    );
  }

  _Leb128Read _readU32Leb128(
    List<int> bytes,
    int offset, {
    int? endOffset,
  }) {
    final limit = endOffset ?? bytes.length;
    if (offset >= limit) {
      throw const FormatException('Malformed WASM leb128');
    }
    var result = 0;
    var shift = 0;
    var cursor = offset;
    while (true) {
      if (cursor >= limit) {
        throw const FormatException('Malformed WASM leb128');
      }
      final byte = bytes[cursor];
      cursor += 1;
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return _Leb128Read(
          value: result,
          nextOffset: cursor,
        );
      }
      shift += 7;
      if (shift > 35) {
        throw const FormatException('Malformed WASM leb128');
      }
    }
  }

  _Leb128Read _readS32Leb128(List<int> bytes, int offset) {
    var result = 0;
    var shift = 0;
    var cursor = offset;
    var byte = 0;
    while (true) {
      if (cursor >= bytes.length) {
        throw const FormatException('Malformed WASM leb128');
      }
      byte = bytes[cursor];
      cursor += 1;
      result |= (byte & 0x7f) << shift;
      shift += 7;
      if ((byte & 0x80) == 0) break;
      if (shift > 35) {
        throw const FormatException('Malformed WASM leb128');
      }
    }
    if (shift < 32 && (byte & 0x40) != 0) {
      result |= -1 << shift;
    }
    return _Leb128Read(value: result, nextOffset: cursor);
  }

  _S64Leb128Read _readS64Leb128(List<int> bytes, int offset) {
    var result = BigInt.zero;
    var shift = 0;
    var cursor = offset;
    var byte = 0;
    while (true) {
      if (cursor >= bytes.length) {
        throw const FormatException('Malformed WASM leb128');
      }
      byte = bytes[cursor];
      cursor += 1;
      final chunk = BigInt.from(byte & 0x7f) << shift;
      result |= chunk;
      shift += 7;
      if ((byte & 0x80) == 0) break;
      if (shift > 70) {
        throw const FormatException('Malformed WASM leb128');
      }
    }
    if (shift < 64 && (byte & 0x40) != 0) {
      final signExt = (BigInt.one << shift) - BigInt.one;
      result |= ~signExt;
    }
    return _S64Leb128Read(
      value: result,
      nextOffset: cursor,
    );
  }

  String _canonicalJson(Object? input) {
    final normalized = _normalizeJson(input);
    return jsonEncode(normalized);
  }

  Object? _normalizeJson(Object? input) {
    if (input is Map) {
      final pairs = <MapEntry<String, Object?>>[];
      for (final entry in input.entries) {
        pairs.add(
          MapEntry(entry.key.toString(), _normalizeJson(entry.value)),
        );
      }
      pairs.sort((a, b) => a.key.compareTo(b.key));
      final output = <String, Object?>{};
      for (final pair in pairs) {
        output[pair.key] = pair.value;
      }
      return output;
    }
    if (input is List) {
      return input.map(_normalizeJson).toList();
    }
    return input;
  }
}

class _ResolvedModule {
  final String modulePath;
  final String moduleSelection;
  final List<int> bytes;

  const _ResolvedModule({
    required this.modulePath,
    required this.moduleSelection,
    required this.bytes,
  });
}

class _ResolvedModuleCandidate {
  final ArchiveFile entry;
  final String normalizedPath;

  const _ResolvedModuleCandidate({
    required this.entry,
    required this.normalizedPath,
  });
}

class _Leb128Read {
  final int value;
  final int nextOffset;

  const _Leb128Read({
    required this.value,
    required this.nextOffset,
  });
}

class _ReadResult<T> {
  final T value;
  final int nextOffset;

  const _ReadResult({
    required this.value,
    required this.nextOffset,
  });
}

class _WasmFuncType {
  final int paramCount;
  final int resultCount;

  const _WasmFuncType({
    required this.paramCount,
    required this.resultCount,
  });
}

class _WasmModuleScan {
  final bool hasImports;
  final bool hasStartSection;
  final int importedFunctionCount;
  final List<_WasmFuncType> functionTypes;
  final List<int> functionTypeIndices;
  final List<List<int>> codeBodies;
  final int? entryFunctionIndex;

  const _WasmModuleScan({
    required this.hasImports,
    required this.hasStartSection,
    required this.importedFunctionCount,
    required this.functionTypes,
    required this.functionTypeIndices,
    required this.codeBodies,
    required this.entryFunctionIndex,
  });
}

class _WasmImportSummary {
  final int totalImports;
  final int importedFunctionCount;

  const _WasmImportSummary({
    required this.totalImports,
    required this.importedFunctionCount,
  });
}

class _S64Leb128Read {
  final BigInt value;
  final int nextOffset;

  const _S64Leb128Read({
    required this.value,
    required this.nextOffset,
  });
}

class _WasmExecutionState {
  final List<_WasmStackValue> stack;
  int instructionCount = 0;

  _WasmExecutionState({
    required this.stack,
  });
}

class _WasmInstructionSequenceResult {
  final int nextOffset;
  final bool terminatedByEnd;
  final bool terminatedByElse;
  final _WasmBranchSignal? branchSignal;

  const _WasmInstructionSequenceResult({
    required this.nextOffset,
    required this.terminatedByEnd,
    required this.terminatedByElse,
    this.branchSignal,
  });
}

class _WasmScanSequenceResult {
  final int nextOffset;
  final bool terminatedByEnd;
  final bool terminatedByElse;

  const _WasmScanSequenceResult({
    required this.nextOffset,
    required this.terminatedByEnd,
    required this.terminatedByElse,
  });
}

class _WasmBlockTypeRead {
  final int nextOffset;

  const _WasmBlockTypeRead({
    required this.nextOffset,
  });
}

class _WasmBranchSignal {
  final int depth;

  const _WasmBranchSignal(this.depth);
}

enum _WasmStackValueType {
  i32,
  i64,
  f32,
  f64,
}

class _WasmStackValue {
  final _WasmStackValueType type;
  final int? i32;
  final BigInt? i64;

  const _WasmStackValue._({
    required this.type,
    this.i32,
    this.i64,
  });

  const _WasmStackValue.i32(int value)
      : this._(
          type: _WasmStackValueType.i32,
          i32: value,
        );

  const _WasmStackValue.i64(BigInt value)
      : this._(
          type: _WasmStackValueType.i64,
          i64: value,
        );

  const _WasmStackValue.f32()
      : this._(
          type: _WasmStackValueType.f32,
        );

  const _WasmStackValue.f64()
      : this._(
          type: _WasmStackValueType.f64,
        );
}

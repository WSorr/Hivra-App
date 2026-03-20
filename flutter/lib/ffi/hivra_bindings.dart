import 'dart:ffi';
import 'dart:typed_data';
import 'dart:io' show Directory, File, Platform;
import 'package:ffi/ffi.dart';

// C function typedefs
typedef HivraSeedToMnemonicC = Int32 Function(
  Pointer<Uint8> seed,
  Uint32 wordCount,
  Pointer<Pointer<Int8>> outPhrase,
);
typedef HivraSeedToMnemonicDart = int Function(
  Pointer<Uint8> seed,
  int wordCount,
  Pointer<Pointer<Int8>> outPhrase,
);

typedef HivraMnemonicToSeedC = Int32 Function(
  Pointer<Int8> phrase,
  Pointer<Uint8> outSeed,
);
typedef HivraMnemonicToSeedDart = int Function(
  Pointer<Int8> phrase,
  Pointer<Uint8> outSeed,
);

typedef HivraGenerateRandomSeedC = Int32 Function(Pointer<Uint8> outSeed);
typedef HivraGenerateRandomSeedDart = int Function(Pointer<Uint8> outSeed);

typedef HivraSeedRootPublicKeyC = Int32 Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);
typedef HivraSeedRootPublicKeyDart = int Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);

typedef HivraSeedNostrPublicKeyC = Int32 Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);
typedef HivraSeedNostrPublicKeyDart = int Function(
  Pointer<Uint8> seed,
  Pointer<Uint8> outKey,
);

typedef HivraFreeStringC = Void Function(Pointer<Int8> ptr);
typedef HivraFreeStringDart = void Function(Pointer<Int8> ptr);

typedef HivraLastErrorMessageC = Pointer<Int8> Function();
typedef HivraLastErrorMessageDart = Pointer<Int8> Function();

typedef HivraSeedExistsC = Int8 Function();
typedef HivraSeedExistsDart = int Function();

typedef HivraSeedSaveC = Int32 Function(Pointer<Uint8> seed);
typedef HivraSeedSaveDart = int Function(Pointer<Uint8> seed);

typedef HivraSeedLoadC = Int32 Function(Pointer<Uint8> outSeed);
typedef HivraSeedLoadDart = int Function(Pointer<Uint8> outSeed);

typedef HivraSeedDeleteC = Int32 Function();
typedef HivraSeedDeleteDart = int Function();

typedef HivraCapsuleCreateC = Int32 Function(
  Pointer<Uint8> seed,
  Uint8 network,
  Uint8 capsuleType,
  Uint8 ownerMode,
);
typedef HivraCapsuleCreateDart = int Function(
  Pointer<Uint8> seed,
  int network,
  int capsuleType,
  int ownerMode,
);

typedef HivraCapsuleRuntimeOwnerPublicKeyC = Int32 Function(Pointer<Uint8> outKey);
typedef HivraCapsuleRuntimeOwnerPublicKeyDart = int Function(Pointer<Uint8> outKey);

typedef HivraCapsuleRootPublicKeyC = Int32 Function(Pointer<Uint8> outKey);
typedef HivraCapsuleRootPublicKeyDart = int Function(Pointer<Uint8> outKey);

typedef HivraCapsuleNostrPublicKeyC = Int32 Function(Pointer<Uint8> outKey);
typedef HivraCapsuleNostrPublicKeyDart = int Function(Pointer<Uint8> outKey);

typedef HivraCapsuleResetC = Int32 Function();
typedef HivraCapsuleResetDart = int Function();

typedef HivraStarterGetIdC = Int32 Function(
  Uint8 slot,
  Pointer<Uint8> outId,
);
typedef HivraStarterGetIdDart = int Function(
  int slot,
  Pointer<Uint8> outId,
);

typedef HivraStarterGetTypeC = Int32 Function(Uint8 slot);
typedef HivraStarterGetTypeDart = int Function(int slot);

typedef HivraStarterExistsC = Int8 Function(Uint8 slot);
typedef HivraStarterExistsDart = int Function(int slot);

typedef HivraSendInvitationC = Int32 Function(
  Pointer<Uint8> toPubkey,
  Uint8 starterSlot,
);
typedef HivraSendInvitationDart = int Function(
  Pointer<Uint8> toPubkey,
  int starterSlot,
);

typedef HivraTransportReceiveC = Int32 Function();
typedef HivraTransportReceiveDart = int Function();
typedef HivraTransportReceiveQuickC = Int32 Function();
typedef HivraTransportReceiveQuickDart = int Function();

typedef HivraAcceptInvitationC = Int32 Function(
  Pointer<Uint8> invitationId,
  Pointer<Uint8> fromPubkey,
  Pointer<Uint8> createdStarterId,
);
typedef HivraAcceptInvitationDart = int Function(
  Pointer<Uint8> invitationId,
  Pointer<Uint8> fromPubkey,
  Pointer<Uint8> createdStarterId,
);

typedef HivraRejectInvitationC = Int32 Function(
  Pointer<Uint8> invitationId,
  Uint8 reason,
);
typedef HivraRejectInvitationDart = int Function(
  Pointer<Uint8> invitationId,
  int reason,
);

typedef HivraExpireInvitationC = Int32 Function(Pointer<Uint8> invitationId);
typedef HivraExpireInvitationDart = int Function(Pointer<Uint8> invitationId);

typedef HivraBreakRelationshipC = Int32 Function(
  Pointer<Uint8> peerPubkey,
  Pointer<Uint8> ownStarterId,
  Pointer<Uint8> peerStarterId,
);
typedef HivraBreakRelationshipDart = int Function(
  Pointer<Uint8> peerPubkey,
  Pointer<Uint8> ownStarterId,
  Pointer<Uint8> peerStarterId,
);

typedef HivraNostrSendPreparedSelfCheckC = Int32 Function();
typedef HivraNostrSendPreparedSelfCheckDart = int Function();

typedef HivraExportLedgerC = Int32 Function(Pointer<Pointer<Int8>> outJson);
typedef HivraExportLedgerDart = int Function(Pointer<Pointer<Int8>> outJson);

typedef HivraImportLedgerC = Int32 Function(Pointer<Int8> json);
typedef HivraImportLedgerDart = int Function(Pointer<Int8> json);

typedef HivraLedgerAppendEventC = Int32 Function(
  Uint8 kind,
  Pointer<Uint8> payload,
  Uint64 payloadLen,
);
typedef HivraLedgerAppendEventDart = int Function(
  int kind,
  Pointer<Uint8> payload,
  int payloadLen,
);

class HivraBindings {
  static final HivraBindings _instance = HivraBindings._internal();
  
  factory HivraBindings() => _instance;
  static HivraBindings load() => _instance;

  static final DynamicLibrary _lib = _openLibrary();

  static DynamicLibrary _openLibrary() {
    if (Platform.isMacOS) {
      final executable = File(Platform.resolvedExecutable);
      final candidates = <String>[
        '${executable.parent.parent.path}/Frameworks/libhivra_ffi.dylib',
        '${Directory.current.path}/libhivra_ffi.dylib',
        'libhivra_ffi.dylib',
      ];

      Object? lastError;
      for (final path in candidates) {
        try {
          return DynamicLibrary.open(path);
        } catch (error) {
          lastError = error;
        }
      }
      throw Exception(
        'Failed to load libhivra_ffi.dylib from app bundle Frameworks. '
        'Last error: $lastError',
      );
    }

    if (Platform.isAndroid) {
      return DynamicLibrary.open('libhivra_ffi.so');
    }

    return DynamicLibrary.process();
  }

  late final HivraSeedToMnemonicDart _seedToMnemonic;
  late final HivraMnemonicToSeedDart _mnemonicToSeed;
  late final HivraGenerateRandomSeedDart _generateRandomSeed;
  late final HivraSeedRootPublicKeyDart _seedRootPublicKey;
  late final HivraSeedNostrPublicKeyDart _seedNostrPublicKey;
  late final HivraFreeStringDart _freeString;
  late final HivraLastErrorMessageDart _lastErrorMessage;
  late final HivraSeedExistsDart _seedExists;
  late final HivraSeedSaveDart _seedSave;
  late final HivraSeedLoadDart _seedLoad;
  late final HivraSeedDeleteDart _seedDelete;
  late final HivraCapsuleCreateDart _capsuleCreate;
  late final HivraCapsuleRuntimeOwnerPublicKeyDart _capsuleRuntimeOwnerPublicKey;
  late final HivraCapsuleRootPublicKeyDart _capsuleRootPublicKey;
  late final HivraCapsuleNostrPublicKeyDart _capsuleNostrPublicKey;
  late final HivraCapsuleResetDart _capsuleReset;
  late final HivraStarterGetIdDart _starterGetId;
  late final HivraStarterGetTypeDart _starterGetType;
  late final HivraStarterExistsDart _starterExists;
  HivraSendInvitationDart? _sendInvitation;
  HivraTransportReceiveDart? _transportReceive;
  HivraTransportReceiveQuickDart? _transportReceiveQuick;
  HivraAcceptInvitationDart? _acceptInvitation;
  HivraRejectInvitationDart? _rejectInvitation;
  HivraExpireInvitationDart? _expireInvitation;
  HivraBreakRelationshipDart? _breakRelationship;
  HivraNostrSendPreparedSelfCheckDart? _nostrSendPreparedSelfCheck;
  late final HivraExportLedgerDart _exportLedger;
  late final HivraImportLedgerDart _importLedger;
  late final HivraLedgerAppendEventDart _ledgerAppendEvent;

  HivraBindings._internal() {
    _seedToMnemonic = _lib
        .lookup<NativeFunction<HivraSeedToMnemonicC>>('hivra_seed_to_mnemonic')
        .asFunction();
    
    _mnemonicToSeed = _lib
        .lookup<NativeFunction<HivraMnemonicToSeedC>>('hivra_mnemonic_to_seed')
        .asFunction();
    
    _generateRandomSeed = _lib
        .lookup<NativeFunction<HivraGenerateRandomSeedC>>('hivra_generate_random_seed')
        .asFunction();

    _seedRootPublicKey = _lib
        .lookup<NativeFunction<HivraSeedRootPublicKeyC>>('hivra_seed_root_public_key')
        .asFunction();

    _seedNostrPublicKey = _lib
        .lookup<NativeFunction<HivraSeedNostrPublicKeyC>>('hivra_seed_nostr_public_key')
        .asFunction();
    
    _freeString = _lib
        .lookup<NativeFunction<HivraFreeStringC>>('hivra_free_string')
        .asFunction();

    _lastErrorMessage = _lib
        .lookup<NativeFunction<HivraLastErrorMessageC>>('hivra_last_error_message')
        .asFunction();

    _seedExists = _lib
        .lookup<NativeFunction<HivraSeedExistsC>>('hivra_seed_exists')
        .asFunction();

    _seedSave = _lib
        .lookup<NativeFunction<HivraSeedSaveC>>('hivra_seed_save')
        .asFunction();

    _seedLoad = _lib
        .lookup<NativeFunction<HivraSeedLoadC>>('hivra_seed_load')
        .asFunction();

    _seedDelete = _lib
        .lookup<NativeFunction<HivraSeedDeleteC>>('hivra_seed_delete')
        .asFunction();

    _capsuleCreate = _lib
        .lookup<NativeFunction<HivraCapsuleCreateC>>('hivra_capsule_create')
        .asFunction();

    _capsuleRuntimeOwnerPublicKey = _lib
        .lookup<NativeFunction<HivraCapsuleRuntimeOwnerPublicKeyC>>('hivra_capsule_runtime_owner_public_key')
        .asFunction();

    _capsuleRootPublicKey = _lib
        .lookup<NativeFunction<HivraCapsuleRootPublicKeyC>>('hivra_capsule_root_public_key')
        .asFunction();

    _capsuleNostrPublicKey = _lib
        .lookup<NativeFunction<HivraCapsuleNostrPublicKeyC>>('hivra_capsule_nostr_public_key')
        .asFunction();

    _capsuleReset = _lib
        .lookup<NativeFunction<HivraCapsuleResetC>>('hivra_capsule_reset')
        .asFunction();

    _starterGetId = _lib
        .lookup<NativeFunction<HivraStarterGetIdC>>('hivra_starter_get_id')
        .asFunction();

    _starterGetType = _lib
        .lookup<NativeFunction<HivraStarterGetTypeC>>('hivra_starter_get_type')
        .asFunction();

    _starterExists = _lib
        .lookup<NativeFunction<HivraStarterExistsC>>('hivra_starter_exists')
        .asFunction();

    try {
      _sendInvitation = _lib
          .lookup<NativeFunction<HivraSendInvitationC>>('hivra_send_invitation')
          .asFunction();
    } catch (_) {
      _sendInvitation = null;
    }

    try {
      _transportReceive = _lib
          .lookup<NativeFunction<HivraTransportReceiveC>>('hivra_transport_receive')
          .asFunction();
    } catch (_) {
      _transportReceive = null;
    }

    try {
      _transportReceiveQuick = _lib
          .lookup<NativeFunction<HivraTransportReceiveQuickC>>(
              'hivra_transport_receive_quick')
          .asFunction();
    } catch (_) {
      _transportReceiveQuick = null;
    }

    try {
      _acceptInvitation = _lib
          .lookup<NativeFunction<HivraAcceptInvitationC>>('hivra_accept_invitation')
          .asFunction();
    } catch (_) {
      _acceptInvitation = null;
    }

    try {
      _rejectInvitation = _lib
          .lookup<NativeFunction<HivraRejectInvitationC>>('hivra_reject_invitation')
          .asFunction();
    } catch (_) {
      _rejectInvitation = null;
    }

    try {
      _expireInvitation = _lib
          .lookup<NativeFunction<HivraExpireInvitationC>>('hivra_expire_invitation')
          .asFunction();
    } catch (_) {
      _expireInvitation = null;
    }

    try {
      _breakRelationship = _lib
          .lookup<NativeFunction<HivraBreakRelationshipC>>('hivra_break_relationship')
          .asFunction();
    } catch (_) {
      _breakRelationship = null;
    }

    _exportLedger = _lib
        .lookup<NativeFunction<HivraExportLedgerC>>('hivra_export_ledger')
        .asFunction();

    _importLedger = _lib
        .lookup<NativeFunction<HivraImportLedgerC>>('hivra_import_ledger')
        .asFunction();

    _ledgerAppendEvent = _lib
        .lookup<NativeFunction<HivraLedgerAppendEventC>>('hivra_ledger_append_event')
        .asFunction();

    try {
      _nostrSendPreparedSelfCheck = _lib
          .lookup<NativeFunction<HivraNostrSendPreparedSelfCheckC>>('hivra_nostr_send_prepared_self_check')
          .asFunction();
    } catch (_) {
      _nostrSendPreparedSelfCheck = null;
    }
  }

  // Alias for seedExists for compatibility
  bool initSeed() => _seedExists() != 0;
  
  static const int legacyNostrOwnerMode = 0;
  static const int rootOwnerMode = 1;

  bool seedExists() => _seedExists() != 0;

  String? lastErrorMessage() {
    final ptr = _lastErrorMessage();
    if (ptr == nullptr) return null;
    try {
      return ptr.cast<Utf8>().toDartString();
    } finally {
      _freeString(ptr);
    }
  }
  
  bool saveSeed(Uint8List seed) {
    if (seed.length != 32) return false;
    final seedPtr = calloc<Uint8>(32);
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      return _seedSave(seedPtr) == 0;
    } finally {
      calloc.free(seedPtr);
    }
  }

  Uint8List? seedRootPublicKey(Uint8List seed) {
    if (seed.length != 32) return null;
    final seedPtr = calloc<Uint8>(32);
    final outPtr = calloc<Uint8>(32);
    try {
      seedPtr.asTypedList(32).setAll(0, seed);
      final result = _seedRootPublicKey(seedPtr, outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      key.setAll(0, outPtr.asTypedList(32));
      return key;
    } finally {
      calloc.free(seedPtr);
      calloc.free(outPtr);
    }
  }

  Uint8List? seedNostrPublicKey(Uint8List seed) {
    if (seed.length != 32) return null;
    final seedPtr = calloc<Uint8>(32);
    final outPtr = calloc<Uint8>(32);
    try {
      seedPtr.asTypedList(32).setAll(0, seed);
      final result = _seedNostrPublicKey(seedPtr, outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      key.setAll(0, outPtr.asTypedList(32));
      return key;
    } finally {
      calloc.free(seedPtr);
      calloc.free(outPtr);
    }
  }

  Uint8List? loadSeed() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _seedLoad(outPtr);
      if (result != 0) return null;
      final seed = Uint8List(32);
      final seedNative = outPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool deleteSeed() => _seedDelete() == 0;

  bool createCapsule(
    Uint8List seed, {
    bool isNeste = true,
    bool isGenesis = false,
    int ownerMode = rootOwnerMode,
  }) {
    if (seed.length != 32) return false;
    final seedPtr = calloc<Uint8>(32);
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      final network = isNeste ? 1 : 0;
      final capsuleType = isGenesis ? 1 : 0;
      return _capsuleCreate(seedPtr, network, capsuleType, ownerMode) == 0;
    } finally {
      calloc.free(seedPtr);
    }
  }

  String? createCapsuleError(
    Uint8List seed, {
    bool isNeste = true,
    bool isGenesis = false,
    int ownerMode = rootOwnerMode,
  }) {
    if (createCapsule(
      seed,
      isNeste: isNeste,
      isGenesis: isGenesis,
      ownerMode: ownerMode,
    )) {
      return null;
    }
    return lastErrorMessage() ?? 'Failed to create capsule';
  }

  Uint8List? capsuleRuntimeOwnerPublicKey() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _capsuleRuntimeOwnerPublicKey(outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      final keyNative = outPtr.asTypedList(32);
      key.setAll(0, keyNative);
      return key;
    } finally {
      calloc.free(outPtr);
    }
  }

  Uint8List? capsuleRootPublicKey() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _capsuleRootPublicKey(outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      final keyNative = outPtr.asTypedList(32);
      key.setAll(0, keyNative);
      return key;
    } finally {
      calloc.free(outPtr);
    }
  }

  Uint8List? capsuleNostrPublicKey() {
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _capsuleNostrPublicKey(outPtr);
      if (result != 0) return null;
      final key = Uint8List(32);
      final keyNative = outPtr.asTypedList(32);
      key.setAll(0, keyNative);
      return key;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool resetCapsule() => _capsuleReset() == 0;

  Uint8List? getStarterId(int slot) {
    if (slot < 0 || slot > 4) return null;
    final outPtr = calloc<Uint8>(32);
    try {
      final result = _starterGetId(slot, outPtr);
      if (result != 0) return null;
      final id = Uint8List(32);
      final idNative = outPtr.asTypedList(32);
      id.setAll(0, idNative);
      return id;
    } finally {
      calloc.free(outPtr);
    }
  }

  String getStarterType(int slot) {
    final typeIndex = _starterGetType(slot);
    switch (typeIndex) {
      case 0: return 'Juice';
      case 1: return 'Spark';
      case 2: return 'Seed';
      case 3: return 'Pulse';
      case 4: return 'Kick';
      default: return 'Unknown';
    }
  }

  bool starterExists(int slot) => _starterExists(slot) != 0;

  int sendInvitationCode(Uint8List toPubkey, int starterSlot) {
    if (toPubkey.length != 32 || starterSlot < 0 || starterSlot > 4) return -1;
    final toPtr = calloc<Uint8>(32);
    try {
      final sendInvitationFn = _sendInvitation;
      if (sendInvitationFn == null) {
        return -1002;
      }
      toPtr.asTypedList(32).setAll(0, toPubkey);
      return sendInvitationFn(toPtr, starterSlot);
    } finally {
      calloc.free(toPtr);
    }
  }

  bool sendInvitation(Uint8List toPubkey, int starterSlot) =>
      sendInvitationCode(toPubkey, starterSlot) == 0;

  int receiveTransportMessages() => _transportReceive?.call() ?? -1002;

  int receiveTransportMessagesQuick() => _transportReceiveQuick?.call() ?? -1002;

  int acceptInvitationCode(Uint8List invitationId, Uint8List fromPubkey, Uint8List createdStarterId) {
    if (invitationId.length != 32 || fromPubkey.length != 32 || createdStarterId.length != 32) {
      return -1;
    }
    final invitationIdPtr = calloc<Uint8>(32);
    final fromPubkeyPtr = calloc<Uint8>(32);
    final createdStarterIdPtr = calloc<Uint8>(32);
    try {
      final acceptInvitationFn = _acceptInvitation;
      if (acceptInvitationFn == null) {
        return -1002;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      fromPubkeyPtr.asTypedList(32).setAll(0, fromPubkey);
      createdStarterIdPtr.asTypedList(32).setAll(0, createdStarterId);
      return acceptInvitationFn(invitationIdPtr, fromPubkeyPtr, createdStarterIdPtr);
    } finally {
      calloc.free(invitationIdPtr);
      calloc.free(fromPubkeyPtr);
      calloc.free(createdStarterIdPtr);
    }
  }

  bool acceptInvitation(Uint8List invitationId, Uint8List fromPubkey, Uint8List createdStarterId) {
    return acceptInvitationCode(invitationId, fromPubkey, createdStarterId) == 0;
  }

  bool rejectInvitation(Uint8List invitationId, int reason) {
    if (invitationId.length != 32) return false;
    final invitationIdPtr = calloc<Uint8>(32);
    try {
      final rejectInvitationFn = _rejectInvitation;
      if (rejectInvitationFn == null) {
        return false;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      return rejectInvitationFn(invitationIdPtr, reason) == 0;
    } finally {
      calloc.free(invitationIdPtr);
    }
  }

  bool expireInvitation(Uint8List invitationId) {
    if (invitationId.length != 32) return false;
    final invitationIdPtr = calloc<Uint8>(32);
    try {
      final expireInvitationFn = _expireInvitation;
      if (expireInvitationFn == null) {
        return false;
      }
      invitationIdPtr.asTypedList(32).setAll(0, invitationId);
      return expireInvitationFn(invitationIdPtr) == 0;
    } finally {
      calloc.free(invitationIdPtr);
    }
  }

  bool breakRelationship(
    Uint8List peerPubkey,
    Uint8List ownStarterId,
    Uint8List peerStarterId,
  ) {
    if (peerPubkey.length != 32 ||
        ownStarterId.length != 32 ||
        peerStarterId.length != 32) {
      return false;
    }
    final peerPtr = calloc<Uint8>(32);
    final ownPtr = calloc<Uint8>(32);
    final peerStarterPtr = calloc<Uint8>(32);
    try {
      final breakRelationshipFn = _breakRelationship;
      if (breakRelationshipFn == null) {
        return false;
      }
      peerPtr.asTypedList(32).setAll(0, peerPubkey);
      ownPtr.asTypedList(32).setAll(0, ownStarterId);
      peerStarterPtr.asTypedList(32).setAll(0, peerStarterId);
      return breakRelationshipFn(peerPtr, ownPtr, peerStarterPtr) == 0;
    } finally {
      calloc.free(peerPtr);
      calloc.free(ownPtr);
      calloc.free(peerStarterPtr);
    }
  }

  int nostrSendPreparedSelfCheck() => _nostrSendPreparedSelfCheck?.call() ?? -1001;

  String? exportLedger() {
    final outPtr = calloc<Pointer<Int8>>();
    try {
      if (_exportLedger(outPtr) != 0) return null;
      final cstr = outPtr.value;
      if (cstr == nullptr) return null;
      final json = cstr.cast<Utf8>().toDartString();
      _freeString(cstr);
      return json;
    } finally {
      calloc.free(outPtr);
    }
  }

  bool importLedger(String json) {
    final jsonPtr = json.toNativeUtf8();
    try {
      return _importLedger(jsonPtr.cast<Int8>()) == 0;
    } finally {
      calloc.free(jsonPtr);
    }
  }

  bool ledgerAppendEvent(int kind, Uint8List payload) {
    final payloadPtr = calloc<Uint8>(payload.length);
    try {
      if (payload.isNotEmpty) {
        payloadPtr.asTypedList(payload.length).setAll(0, payload);
      }
      return _ledgerAppendEvent(kind, payloadPtr, payload.length) == 0;
    } finally {
      calloc.free(payloadPtr);
    }
  }

  String seedToMnemonic(Uint8List seed, {int wordCount = 24}) {
    if (seed.length != 32) throw ArgumentError('Seed must be 32 bytes');
    final seedPtr = calloc<Uint8>(32);
    final outPhrasePtr = calloc<Pointer<Int8>>();
    try {
      final seedNative = seedPtr.asTypedList(32);
      seedNative.setAll(0, seed);
      final result = _seedToMnemonic(seedPtr, wordCount, outPhrasePtr);
      if (result != 0) throw Exception('Failed to convert seed (code: $result)');
      final phraseCStr = outPhrasePtr.value;
      if (phraseCStr == nullptr) throw Exception('Null phrase');
      final phrase = phraseCStr.cast<Utf8>().toDartString();
      _freeString(phraseCStr);
      return phrase;
    } finally {
      calloc.free(seedPtr);
      calloc.free(outPhrasePtr);
    }
  }

  Uint8List mnemonicToSeed(String phrase) {
    final phraseCStr = phrase.toNativeUtf8();
    final seedPtr = calloc<Uint8>(32);
    try {
      final result = _mnemonicToSeed(phraseCStr as Pointer<Int8>, seedPtr);
      if (result != 0) throw Exception('Failed to convert mnemonic (code: $result)');
      final seed = Uint8List(32);
      final seedNative = seedPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(phraseCStr);
      calloc.free(seedPtr);
    }
  }

  bool validateMnemonic(String phrase) {
    try {
      mnemonicToSeed(phrase);
      return true;
    } catch (_) {
      return false;
    }
  }

  Uint8List generateRandomSeed() {
    final seedPtr = calloc<Uint8>(32);
    try {
      final result = _generateRandomSeed(seedPtr);
      if (result != 0) throw Exception('Failed to generate seed (code: $result)');
      final seed = Uint8List(32);
      final seedNative = seedPtr.asTypedList(32);
      seed.setAll(0, seedNative);
      return seed;
    } finally {
      calloc.free(seedPtr);
    }
  }
}

import 'dart:convert';
import 'dart:typed_data';

import 'package:bech32/bech32.dart';

class HivraIdFormat {
  static String formatCapsuleKeyBytes(Uint8List bytes) =>
      _format32(bytes, hrp: 'h');

  static String formatNostrKeyBytes(Uint8List bytes) =>
      _format32(bytes, hrp: 'npub');

  static String formatStarterIdBytes(Uint8List bytes) =>
      _format32(bytes, hrp: 'hs');

  static String formatCapsuleKeyFromBase64(String raw) =>
      _formatFromBase64(raw, hrp: 'h');

  static String formatNostrKeyFromBase64(String raw) =>
      _formatFromBase64(raw, hrp: 'npub');

  static String formatStarterIdFromBase64(String raw) =>
      _formatFromBase64(raw, hrp: 'hs');

  static String short(String value, {int head = 12, int tail = 6}) {
    if (value.isEmpty) return 'unknown';
    if (value.length <= head + tail + 3) return value;
    return '${value.substring(0, head)}...${value.substring(value.length - tail)}';
  }

  static String _formatFromBase64(String raw, {required String hrp}) {
    try {
      final bytes = base64.decode(raw);
      if (bytes.length == 32) {
        return _format32(Uint8List.fromList(bytes), hrp: hrp);
      }
    } catch (_) {}
    return raw;
  }

  static String _format32(Uint8List bytes, {required String hrp}) {
    if (bytes.length != 32) {
      throw ArgumentError('Expected 32 bytes, got ${bytes.length}');
    }
    final words = _convertBits(bytes, 8, 5, true);
    if (words == null) {
      throw ArgumentError('Invalid byte sequence for bech32 conversion');
    }
    return bech32.encode(Bech32(hrp, words));
  }

  static List<int>? _convertBits(
    List<int> data,
    int fromBits,
    int toBits,
    bool pad,
  ) {
    var acc = 0;
    var bits = 0;
    final result = <int>[];
    final maxv = (1 << toBits) - 1;

    for (final value in data) {
      if (value < 0 || (value >> fromBits) != 0) {
        return null;
      }
      acc = (acc << fromBits) | value;
      bits += fromBits;
      while (bits >= toBits) {
        bits -= toBits;
        result.add((acc >> bits) & maxv);
      }
    }

    if (pad) {
      if (bits > 0) {
        result.add((acc << (toBits - bits)) & maxv);
      }
    } else if (bits >= fromBits || ((acc << (toBits - bits)) & maxv) != 0) {
      return null;
    }

    return result;
  }
}

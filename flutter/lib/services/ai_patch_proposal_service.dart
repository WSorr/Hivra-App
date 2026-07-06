import 'dart:convert';

import 'package:crypto/crypto.dart';

class AiPatchProposalRequest {
  final String proposalText;
  final String? sourceLabel;

  const AiPatchProposalRequest({
    required this.proposalText,
    this.sourceLabel,
  });
}

class AiPatchProposalFileChange {
  final String oldPath;
  final String newPath;
  final int addedLines;
  final int removedLines;

  const AiPatchProposalFileChange({
    required this.oldPath,
    required this.newPath,
    required this.addedLines,
    required this.removedLines,
  });
}

class AiPatchProposalReport {
  final int schemaVersion;
  final String sourceLabel;
  final String proposalHashHex;
  final int payloadBytes;
  final List<AiPatchProposalFileChange> fileChanges;
  final bool previewOnly;
  final bool applySkipped;
  final bool gitSkipped;
  final bool releaseSkipped;
  final String reportHashHex;

  const AiPatchProposalReport({
    required this.schemaVersion,
    required this.sourceLabel,
    required this.proposalHashHex,
    required this.payloadBytes,
    required this.fileChanges,
    required this.previewOnly,
    required this.applySkipped,
    required this.gitSkipped,
    required this.releaseSkipped,
    required this.reportHashHex,
  });
}

class AiPatchProposalService {
  static const int maxProposalBytes = 128 * 1024;

  const AiPatchProposalService();

  AiPatchProposalReport preview(AiPatchProposalRequest request) {
    final proposal = request.proposalText.trim();
    if (proposal.isEmpty) {
      throw ArgumentError('Patch proposal text is empty');
    }
    final payloadBytes = utf8.encode(proposal).length;
    if (payloadBytes > maxProposalBytes) {
      throw StateError(
        'Patch proposal is too large: $payloadBytes > $maxProposalBytes bytes',
      );
    }
    final changes = _parseUnifiedDiff(proposal);
    if (changes.isEmpty) {
      throw StateError('Patch proposal does not contain unified diff changes');
    }
    final sourceLabel = (request.sourceLabel?.trim().isNotEmpty ?? false)
        ? request.sourceLabel!.trim()
        : 'ai_patch_proposal';
    final proposalHash = sha256.convert(utf8.encode(proposal)).toString();
    final canonical = <String, dynamic>{
      'schema_version': 1,
      'source_label': sourceLabel,
      'proposal_hash_hex': proposalHash,
      'payload_bytes': payloadBytes,
      'file_changes': changes
          .map((change) => <String, dynamic>{
                'old_path': change.oldPath,
                'new_path': change.newPath,
                'added_lines': change.addedLines,
                'removed_lines': change.removedLines,
              })
          .toList(growable: false),
      'preview_only': true,
      'apply_skipped': true,
      'git_skipped': true,
      'release_skipped': true,
    };
    return AiPatchProposalReport(
      schemaVersion: 1,
      sourceLabel: sourceLabel,
      proposalHashHex: proposalHash,
      payloadBytes: payloadBytes,
      fileChanges: changes,
      previewOnly: true,
      applySkipped: true,
      gitSkipped: true,
      releaseSkipped: true,
      reportHashHex: _hashCanonical(canonical),
    );
  }

  List<AiPatchProposalFileChange> _parseUnifiedDiff(String proposal) {
    final lines = const LineSplitter().convert(proposal);
    final changes = <AiPatchProposalFileChange>[];
    String? oldPath;
    String? newPath;
    var added = 0;
    var removed = 0;

    void flush() {
      if (oldPath == null && newPath == null) return;
      changes.add(AiPatchProposalFileChange(
        oldPath: oldPath ?? '/dev/null',
        newPath: newPath ?? '/dev/null',
        addedLines: added,
        removedLines: removed,
      ));
      oldPath = null;
      newPath = null;
      added = 0;
      removed = 0;
    }

    for (final line in lines) {
      if (line.startsWith('diff --git ')) {
        flush();
        continue;
      }
      if (line.startsWith('--- ')) {
        oldPath = _normalizeDiffPath(line.substring(4).trim());
        continue;
      }
      if (line.startsWith('+++ ')) {
        newPath = _normalizeDiffPath(line.substring(4).trim());
        continue;
      }
      if (oldPath == null && newPath == null) continue;
      if (line.startsWith('+') && !line.startsWith('+++ ')) {
        added++;
      } else if (line.startsWith('-') && !line.startsWith('--- ')) {
        removed++;
      }
    }
    flush();
    return changes
        .where((change) =>
            change.oldPath != '/dev/null' ||
            change.newPath != '/dev/null' ||
            change.addedLines > 0 ||
            change.removedLines > 0)
        .toList(growable: false);
  }

  String _normalizeDiffPath(String rawPath) {
    if (rawPath == '/dev/null') return rawPath;
    if (rawPath.startsWith('a/') || rawPath.startsWith('b/')) {
      return rawPath.substring(2);
    }
    return rawPath;
  }

  String _hashCanonical(Object? value) {
    return sha256.convert(utf8.encode(_canonicalJson(value))).toString();
  }

  String _canonicalJson(Object? value) {
    if (value is Map) {
      final keys = value.keys.map((key) => key.toString()).toList()..sort();
      return '{${keys.map((key) => '${jsonEncode(key)}:${_canonicalJson(value[key])}').join(',')}}';
    }
    if (value is List) {
      return '[${value.map(_canonicalJson).join(',')}]';
    }
    return jsonEncode(value);
  }
}

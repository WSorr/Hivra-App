import 'dart:io';

class AtomicFileWriteService {
  const AtomicFileWriteService();

  Future<void> writeString(File target, String contents) async {
    await _write(target, (temp) => temp.writeAsString(contents, flush: true));
  }

  Future<void> writeBytes(File target, List<int> bytes) async {
    await _write(target, (temp) => temp.writeAsBytes(bytes, flush: true));
  }

  Future<void> _write(
    File target,
    Future<File> Function(File temp) writeTemp,
  ) async {
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temp = File(_tempPathFor(target));
    if (await temp.exists()) {
      await temp.delete();
    }

    try {
      await writeTemp(temp);
      // `rename` replaces a same-directory target atomically on the supported
      // macOS, Linux, and Android filesystems. Do not delete the target as a
      // fallback: a failed replacement must retain the previous durable file.
      await temp.rename(target.path);
    } catch (_) {
      if (await temp.exists()) {
        await temp.delete();
      }
      rethrow;
    }
  }

  String _tempPathFor(File target) {
    final now = DateTime.now().microsecondsSinceEpoch;
    return '${target.path}.tmp.$pid.$now';
  }
}

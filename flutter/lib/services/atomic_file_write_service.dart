import 'dart:io';

class AtomicFileWriteService {
  const AtomicFileWriteService();

  Future<void> writeString(File target, String contents) async {
    final parent = target.parent;
    if (!await parent.exists()) {
      await parent.create(recursive: true);
    }

    final temp = File(_tempPathFor(target));
    if (await temp.exists()) {
      await temp.delete();
    }

    try {
      await temp.writeAsString(contents, flush: true);
      try {
        await temp.rename(target.path);
      } on FileSystemException {
        if (await target.exists()) {
          await target.delete();
        }
        await temp.rename(target.path);
      }
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

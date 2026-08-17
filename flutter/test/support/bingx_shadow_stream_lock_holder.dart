import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) exit(64);
  final directory = Directory(arguments[0]);
  await directory.create(recursive: true);
  final lock = await File(
    '${directory.path}/stream.lock',
  ).open(mode: FileMode.append);
  await lock.lock(FileLock.exclusive);
  await File(arguments[1]).writeAsString('ready', flush: true);
  try {
    await Future<void>.delayed(const Duration(seconds: 4));
  } finally {
    await lock.unlock();
    await lock.close();
  }
}

import 'dart:io';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 2) exit(64);
  final directory = Directory(arguments[0]);
  await directory.create(recursive: true);
  final lock = File('${directory.path}/stream.lock.v2');
  await lock.create(exclusive: true);
  await File(arguments[1]).writeAsString('ready', flush: true);
  try {
    await Future<void>.delayed(const Duration(seconds: 4));
  } finally {
    await lock.delete();
  }
}

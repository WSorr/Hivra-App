import 'dart:io';

Future<Directory> resolveApplicationDocumentsDirectory() {
  throw UnsupportedError(
    'Application documents directory is unavailable without Flutter; '
    'provide an explicit home override',
  );
}

import 'dart:io';

import 'application_documents_directory_stub.dart'
    if (dart.library.ui) 'application_documents_directory_flutter.dart'
    as platform;

Future<Directory> resolveApplicationDocumentsDirectory() {
  return platform.resolveApplicationDocumentsDirectory();
}

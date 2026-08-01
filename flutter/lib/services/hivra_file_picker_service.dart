import 'dart:io';

import 'package:file_selector/file_selector.dart';

class HivraFilePickerService {
  const HivraFilePickerService._();

  static const String androidDownloadsDocumentUri =
      'content://com.android.externalstorage.documents/document/primary%3ADownload';

  static String? initialDirectoryFor({required bool isAndroid}) {
    return isAndroid ? androidDownloadsDocumentUri : null;
  }

  static Future<XFile?> openJsonDocument() {
    return _openDocument(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
  }

  static Future<XFile?> openPluginPackage() {
    return _openDocument(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'WASM plugin packages', extensions: ['wasm', 'zip']),
      ],
    );
  }

  static Future<String?> selectDirectory({required String confirmButtonText}) {
    return getDirectoryPath(
      initialDirectory: initialDirectoryFor(isAndroid: Platform.isAndroid),
      confirmButtonText: confirmButtonText,
    );
  }

  static Future<XFile?> _openDocument({
    required List<XTypeGroup> acceptedTypeGroups,
  }) {
    return openFile(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectoryFor(isAndroid: Platform.isAndroid),
    );
  }
}

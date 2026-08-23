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

  static Future<XFile?> openRunnerPublicKey() {
    return _openDocument(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Runner public key', extensions: ['hex', 'txt']),
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

  static Future<String?> saveJsonDocument({
    required String suggestedName,
    required String confirmButtonText,
  }) async {
    final location = await getSaveLocation(
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
      initialDirectory: initialDirectoryFor(isAndroid: Platform.isAndroid),
      suggestedName: suggestedName,
      confirmButtonText: confirmButtonText,
    );
    return location?.path;
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

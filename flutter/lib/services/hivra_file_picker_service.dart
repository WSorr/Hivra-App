import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class HivraFilePickerService {
  const HivraFilePickerService._();

  static const _documents = MethodChannel('hivra/file_documents');

  static Future<String?> saveExistingJsonDocument({
    required String sourcePath,
    required String suggestedName,
  }) => _documents.invokeMethod<String>('saveJsonDocument', {
    'sourcePath': sourcePath,
    'suggestedName': suggestedName,
  });

  static const String androidDownloadsDocumentUri =
      'content://com.android.externalstorage.documents/document/primary%3ADownload';

  static String? initialDirectoryFor({required bool isAndroid}) {
    return isAndroid ? androidDownloadsDocumentUri : null;
  }

  static Future<XFile?> openJsonDocument() {
    return _openDocument(
      mimeType: 'application/json',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'JSON', extensions: ['json']),
      ],
    );
  }

  static Future<XFile?> openPluginPackage() {
    return _openDocument(
      mimeType: 'application/zip',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'WASM plugin packages', extensions: ['zip']),
      ],
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
    required String mimeType,
    required List<XTypeGroup> acceptedTypeGroups,
  }) async {
    if (defaultTargetPlatform == TargetPlatform.android) {
      // The Android selector eagerly returns file bytes across the channel.
      // Use the existing document bridge to stage the selected stream instead.
      final path = await _documents.invokeMethod<String>('openDocument', {
        'mimeType': mimeType,
        'initialDirectory': androidDownloadsDocumentUri,
      });
      return path == null ? null : XFile(path);
    }
    return openFile(
      acceptedTypeGroups: acceptedTypeGroups,
      initialDirectory: initialDirectoryFor(isAndroid: Platform.isAndroid),
    );
  }
}

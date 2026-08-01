import 'package:flutter_test/flutter_test.dart';
import 'package:hivra_app/services/hivra_file_picker_service.dart';

void main() {
  test('Android JSON picker starts at local Downloads', () {
    expect(
      HivraFilePickerService.initialDirectoryFor(isAndroid: true),
      HivraFilePickerService.androidDownloadsDocumentUri,
    );
  });

  test('desktop picker keeps the platform default location', () {
    expect(
      HivraFilePickerService.initialDirectoryFor(isAndroid: false),
      isNull,
    );
  });
}

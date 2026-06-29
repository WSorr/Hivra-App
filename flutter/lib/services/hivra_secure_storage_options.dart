import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class HivraMacOsSecureStorageOptions extends MacOsOptions {
  const HivraMacOsSecureStorageOptions()
      : super(usesDataProtectionKeychain: false);

  @override
  Map<String, String> toMap() => <String, String>{
        ...super.toMap(),
        // flutter_secure_storage 10.0.0 emits "usesDataProtectionKeychain",
        // while the bundled Darwin plugin reads "useDataProtectionKeyChain".
        'useDataProtectionKeyChain': 'false',
      };
}

const HivraMacOsSecureStorageOptions hivraMacOsSecureStorageOptions =
    HivraMacOsSecureStorageOptions();

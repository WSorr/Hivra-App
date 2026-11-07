import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/screens/settings_screen.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/settings_service.dart';

class _FakeCapsuleAddressService extends CapsuleAddressService {
  int count = 0;
  String? imported;
  String? removedRootKey;
  List<CapsuleAddressCard> cards = <CapsuleAddressCard>[];

  @override
  Future<int> contactCount() async => count;

  @override
  Future<void> importCardJson(String raw) async {
    imported = raw;
  }

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async => cards;

  @override
  Future<bool> removeTrustedCard(String rootKey) async {
    removedRootKey = rootKey;
    return true;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('reads seed and neste flag through injected boundaries', () async {
    final seed = Uint8List.fromList(List<int>.filled(32, 3));

    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => seed,
      buildOwnCard: () async => null,
      exportOwnCardJson: () async => null,
      contactCards: _FakeCapsuleAddressService(),
    );

    expect(service.loadIsNeste(), isTrue);
    expect(service.loadSeed(), seed);
  });

  test('reads app version label through injected boundary', () async {
    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => null,
      buildOwnCard: () async => null,
      exportOwnCardJson: () async => null,
      loadAppVersionLabel: () async => 'Hivra v9.9.9 (999)',
      contactCards: _FakeCapsuleAddressService(),
    );

    expect(await service.appVersionLabel(), 'Hivra v9.9.9 (999)');
  });

  test('opens local data folder through injected boundary', () async {
    var opened = false;
    final service = SettingsService(
      loadIsNeste: () => true,
      loadSeed: () => null,
      buildOwnCard: () async => null,
      exportOwnCardJson: () async => null,
      openLocalDataFolder: () async {
        opened = true;
        return '/tmp/Hivra';
      },
      contactCards: _FakeCapsuleAddressService(),
    );

    expect(await service.openLocalDataFolder(), '/tmp/Hivra');
    expect(opened, isTrue);
  });

  test(
    'delegates contact-card management to contact service and card boundaries',
    () async {
      final fakeContacts =
          _FakeCapsuleAddressService()
            ..count = 2
            ..cards = <CapsuleAddressCard>[
              const CapsuleAddressCard(
                rootKey: 'h1abc',
                rootHex: '11',
                nostrNpub: 'npub1abc',
                nostrHex: '22',
              ),
            ];
      final card = const CapsuleAddressCard(
        rootKey: 'h1self',
        rootHex: 'aa',
        nostrNpub: 'npub1self',
        nostrHex: 'bb',
      );

      final service = SettingsService(
        loadIsNeste: () => true,
        loadSeed: () => null,
        buildOwnCard: () async => card,
        exportOwnCardJson: () async => '{"version":1}',
        contactCards: fakeContacts,
      );

      expect(await service.contactCount(), 2);
      expect(await service.buildOwnCard(), same(card));
      expect(await service.exportOwnCardJson(), '{"version":1}');

      await service.importCardJson('{"root":"peer"}');
      expect(fakeContacts.imported, '{"root":"peer"}');

      expect(await service.listTrustedCards(), fakeContacts.cards);
      expect(await service.removeTrustedCard('h1abc'), isTrue);
      expect(fakeContacts.removedRootKey, 'h1abc');
    },
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.macOS]) {
    testWidgets(
      'long card keeps import actions reachable on ${platform.name}',
      (tester) async {
        final contacts = _FakeCapsuleAddressService()..count = 2;
        final cardJson =
            CapsuleAddressCard(
              version: 2,
              rootKey: 'h1${'a' * 58}',
              rootHex: '11' * 32,
              nostrNpub: 'npub1${'b' * 58}',
              nostrHex: '22' * 32,
              signatureHex: '33' * 64,
            ).toPrettyJson();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async =>
              call.method == 'Clipboard.getData' ? {'text': cardJson} : null,
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
        });
        addTearDown(() => tester.binding.setSurfaceSize(null));
        var keyboardHeight = 0.0;
        var textScale = 1.0;
        late StateSetter updateMetrics;
        final size =
            platform == TargetPlatform.android
                ? const Size(360, 800)
                : const Size(1000, 720);
        await tester.binding.setSurfaceSize(size);
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(platform: platform),
            builder:
                (context, child) => StatefulBuilder(
                  builder: (context, setState) {
                    updateMetrics = setState;
                    return MediaQuery(
                      data: MediaQuery.of(context).copyWith(
                        viewInsets: EdgeInsets.only(bottom: keyboardHeight),
                        textScaler: TextScaler.linear(textScale),
                      ),
                      child: child!,
                    );
                  },
                ),
            home: SettingsScreen(
              service: SettingsService(
                loadIsNeste: () => true,
                loadSeed: () => null,
                buildOwnCard: () async => null,
                exportOwnCardJson: () async => null,
                loadAppVersionLabel: () async => 'Hivra test',
                contactCards: contacts,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Add a capsule'), 250);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Add a capsule'));
        await tester.pumpAndSettle();

        final editor = find.byType(TextField);
        final submit = find.widgetWithText(FilledButton, 'Import');
        final cancel = find.widgetWithText(TextButton, 'Cancel');
        expect(tester.widget<TextField>(editor).controller!.text, cardJson);
        expect(tester.takeException(), isNull);
        expect(submit.hitTestable(), findsOneWidget);
        expect(cancel.hitTestable(), findsOneWidget);
        final submitPosition = tester.getTopLeft(submit);
        await tester.drag(editor, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(tester.getTopLeft(submit), submitPosition);

        if (platform == TargetPlatform.android) {
          await tester.binding.setSurfaceSize(const Size(640, 360));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          expect(submit.hitTestable(), findsOneWidget);
          expect(cancel.hitTestable(), findsOneWidget);
          expect(tester.widget<TextField>(editor).controller!.text, cardJson);
          await tester.binding.setSurfaceSize(size);
          await tester.pumpAndSettle();
        }

        await tester.tap(editor);
        updateMetrics(() {
          keyboardHeight = 300;
          textScale = 1.3;
        });
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (final action in [submit, cancel]) {
          expect(action.hitTestable(), findsOneWidget);
          expect(
            tester.getRect(action).bottom,
            lessThanOrEqualTo(size.height - keyboardHeight),
          );
        }
        expect(tester.widget<TextField>(editor).controller!.text, cardJson);
        await tester.enterText(editor, '');
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(find.text('Card JSON is empty'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.ensureVisible(find.text('Paste'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Paste'));
        await tester.pumpAndSettle();
        expect(tester.widget<TextField>(editor).controller!.text, cardJson);
        expect(submit.hitTestable(), findsOneWidget);
        await tester.tap(submit);
        await tester.pumpAndSettle();
        expect(contacts.imported, cardJson);
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);
      },
    );
  }
}

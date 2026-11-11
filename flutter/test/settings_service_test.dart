import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:hivra_app/screens/settings_screen.dart';
import 'package:hivra_app/services/capsule_address_service.dart';
import 'package:hivra_app/services/capsule_contact_label_store.dart';
import 'package:hivra_app/services/capsule_file_store.dart';
import 'package:hivra_app/services/settings_service.dart';
import 'package:hivra_app/services/user_visible_data_directory_service.dart';

class _FakeCapsuleAddressService extends CapsuleAddressService {
  String? imported;
  String? removedRootKey;
  List<CapsuleAddressCard> cards = <CapsuleAddressCard>[];
  Object? readError;
  Future<List<CapsuleAddressCard>>? pendingRead;

  @override
  Future<void> importCardJson(String raw) async {
    imported = raw;
  }

  @override
  Future<List<CapsuleAddressCard>> listTrustedCards() async {
    if (readError != null) throw readError!;
    return pendingRead ?? cards;
  }

  @override
  Future<bool> removeTrustedCard(String rootKey) async {
    removedRootKey = rootKey;
    return true;
  }
}

class _FailingContactLabels extends CapsuleContactLabelStore {
  bool unavailable = true;

  _FailingContactLabels() : super(readActiveCapsuleRootHex: () => null);

  @override
  Future<Map<String, String>> load() async {
    if (unavailable) throw const FileSystemException('private local path');
    return {'h1peer': 'Saved name'};
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
      'saved cards remain readable when names are unavailable on ${platform.name}',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.android
              ? const Size(360, 800)
              : const Size(1000, 720),
        );
        final labels = _FailingContactLabels();
        final contacts =
            _FakeCapsuleAddressService()
              ..cards = [
                const CapsuleAddressCard(
                  rootKey: 'h1peer',
                  rootHex: '11',
                  nostrNpub: 'npub1peer',
                  nostrHex: '22',
                ),
              ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(platform: platform),
            home: SettingsScreen(
              service: SettingsService(
                loadIsNeste: () => true,
                loadSeed: () => null,
                buildOwnCard: () async => null,
                exportOwnCardJson: () async => null,
                loadAppVersionLabel: () async => 'Hivra test',
                contactCards: contacts,
                contactLabels: labels,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.scrollUntilVisible(find.text('Trusted peer cards'), 250);
        await tester.pumpAndSettle();
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(
          find.text('Contact names unavailable. Showing capsule addresses.'),
          findsOneWidget,
        );
        expect(find.text('Verified delivery card'), findsOneWidget);
        expect(find.textContaining('private local path'), findsNothing);
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(find.text('1 saved'), findsOneWidget);
        labels.unavailable = false;
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(find.text('Saved name'), findsOneWidget);
        expect(
          find.text('Contact names unavailable. Showing capsule addresses.'),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'saved cards distinguish unavailable, populated and empty on ${platform.name}',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(
          platform == TargetPlatform.android
              ? const Size(360, 800)
              : const Size(1000, 720),
        );
        final contacts =
            _FakeCapsuleAddressService()
              ..readError = const FormatException('private saved content')
              ..cards = [
                const CapsuleAddressCard(
                  rootKey: 'h1peer',
                  rootHex: '11',
                  nostrNpub: 'npub1peer',
                  nostrHex: '22',
                ),
              ];
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(platform: platform),
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
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Trusted peer cards'), 250);
        await tester.pumpAndSettle();
        expect(
          find.text('Saved cards unavailable. Tap to retry.'),
          findsOneWidget,
        );
        expect(find.text('0 saved'), findsNothing);
        expect(find.textContaining('private saved content'), findsNothing);
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        expect(tester.takeException(), isNull);

        contacts.readError = null;
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(find.text('Verified delivery card'), findsOneWidget);
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(find.text('1 saved'), findsOneWidget);

        contacts.readError = const FileSystemException('private local path');
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.byType(AlertDialog), findsNothing);
        expect(
          find.text('Saved cards unavailable. Tap to retry.'),
          findsOneWidget,
        );
        expect(find.text('1 saved'), findsNothing);
        expect(find.textContaining('private local path'), findsNothing);

        contacts.readError = null;
        contacts.cards = [];
        await tester.tap(find.text('Trusted peer cards'));
        await tester.pumpAndSettle();
        expect(
          find.text('No trusted peer cards imported yet.'),
          findsOneWidget,
        );
        await tester.tap(find.widgetWithText(TextButton, 'Close'));
        await tester.pumpAndSettle();
        expect(find.text('0 saved'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'saved cards stay loading and ignore completion after disposal on ${platform.name}',
      (tester) async {
        final pending = Completer<List<CapsuleAddressCard>>();
        final contacts =
            _FakeCapsuleAddressService()..pendingRead = pending.future;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData.dark().copyWith(platform: platform),
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
        await tester.scrollUntilVisible(find.text('Trusted peer cards'), 250);
        await tester.pumpAndSettle();
        expect(find.text('Loading saved cards...'), findsOneWidget);
        expect(find.text('0 saved'), findsNothing);
        await tester.pumpWidget(const SizedBox.shrink());
        pending.completeError(const FileSystemException('private local path'));
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      },
    );

    testWidgets(
      'failed name save retains input and allows retry on ${platform.name}',
      (tester) async {
        await tester.runAsync(() async {
          Future<void> waitFor(Finder finder, {bool present = true}) async {
            for (var attempt = 0; attempt < 100; attempt++) {
              await tester.pump(const Duration(milliseconds: 20));
              if (finder.evaluate().isNotEmpty == present) break;
              await Future<void>.delayed(const Duration(milliseconds: 10));
            }
            expect(finder, present ? findsWidgets : findsNothing);
            await tester.pumpAndSettle();
          }

          final temp = await Directory.systemTemp.createTemp('hivra-label-ui-');
          addTearDown(() => temp.delete(recursive: true));
          addTearDown(() => tester.binding.setSurfaceSize(null));
          await tester.binding.setSurfaceSize(
            platform == TargetPlatform.android
                ? const Size(360, 800)
                : const Size(1000, 720),
          );
          final files = CapsuleFileStore(
            dirs: UserVisibleDataDirectoryService(homeOverride: temp.path),
          );
          final owner = 'a' * 64;
          const peer = 'h1peer';
          final labels = CapsuleContactLabelStore(
            fileStore: files,
            readActiveCapsuleRootHex: () => owner,
          );
          await labels.save(peerRootKey: peer, label: 'Old name');
          await labels.save(peerRootKey: 'h1other', label: 'Retained name');
          final file = files.contactLabelsFile(
            await files.capsuleDirForHex(owner),
          );
          final original = await file.readAsString();
          final contacts =
              _FakeCapsuleAddressService()
                ..cards = [
                  const CapsuleAddressCard(
                    rootKey: peer,
                    rootHex: '11',
                    nostrNpub: 'npub1peer',
                    nostrHex: '22',
                  ),
                ];
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData.dark().copyWith(platform: platform),
              home: SettingsScreen(
                service: SettingsService(
                  loadIsNeste: () => true,
                  loadSeed: () => null,
                  buildOwnCard: () async => null,
                  exportOwnCardJson: () async => null,
                  loadAppVersionLabel: () async => 'Hivra test',
                  contactCards: contacts,
                  contactLabels: labels,
                ),
              ),
            ),
          );
          await tester.pumpAndSettle();
          await tester.scrollUntilVisible(find.text('Trusted peer cards'), 250);
          await tester.pumpAndSettle();
          await tester.tap(find.text('Trusted peer cards'));
          await waitFor(find.byTooltip('Name capsule'));
          await tester.tap(find.byTooltip('Name capsule'));
          await tester.pumpAndSettle();
          await tester.enterText(find.byType(TextField), 'New name');
          await file.writeAsString('{broken');
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await waitFor(
            find.text('Name could not be saved. Existing names were kept.'),
          );
          expect(tester.takeException(), isNull);
          expect(find.text('Name capsule'), findsOneWidget);
          expect(
            find.text('Name could not be saved. Existing names were kept.'),
            findsOneWidget,
          );
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller!.text,
            'New name',
          );
          expect(await file.readAsString(), '{broken');
          expect(
            find.widgetWithText(FilledButton, 'Save').hitTestable(),
            findsOneWidget,
          );

          await file.writeAsString(original);
          await tester.tap(find.widgetWithText(FilledButton, 'Save'));
          await waitFor(find.text('Name capsule'), present: false);
          expect(tester.takeException(), isNull);
          expect(find.text('Name capsule'), findsNothing);
          expect(find.text('New name'), findsOneWidget);
          expect(await labels.load(), {
            peer: 'New name',
            'h1other': 'Retained name',
          });

          // Optional name cleanup cannot undo a successfully removed card.
          await file.writeAsString('{broken');
          await tester.tap(find.byTooltip('Remove'));
          await waitFor(find.text('New name'), present: false);
          expect(tester.takeException(), isNull);
          expect(contacts.removedRootKey, peer);
          expect(find.text('New name'), findsNothing);
          expect(await file.readAsString(), '{broken');
          await tester.tap(find.widgetWithText(TextButton, 'Close'));
          await tester.pumpAndSettle();
          expect(
            find.text('Card removed. Its local name could not be cleared.'),
            findsOneWidget,
          );
        });
      },
    );

    testWidgets(
      'long card keeps import actions reachable on ${platform.name}',
      (tester) async {
        final contacts = _FakeCapsuleAddressService();
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

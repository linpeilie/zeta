import 'dart:async';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:settings_client/settings_client.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeGeneralSettingsStore generalStore;
  late FakeAppearanceSettingsStore appearanceStore;
  late FakeSystemFontCatalogApi fontCatalog;
  late SettingsRepository repository;

  setUp(() {
    generalStore = FakeGeneralSettingsStore();
    appearanceStore = FakeAppearanceSettingsStore();
    fontCatalog = FakeSystemFontCatalogApi();
  });

  tearDown(() async {
    try {
      await repository.close();
    } on Object {
      // Failure-path tests assert the first close error explicitly.
    }
  });

  SettingsRepository createRepository() {
    return repository = SettingsRepository(
      generalStore: generalStore,
      appearanceStore: appearanceStore,
      fontCatalog: fontCatalog,
    );
  }

  group('initialization', () {
    test('publishes one fully mapped external-data snapshot', () async {
      generalStore.response = const GeneralSettingsResponse(
        sendMessageShortcut: MessageSendShortcutResponse.primaryModifierEnter,
        notifications: AgentNotificationSettingsResponse(
          enabled: false,
          turnTerminalEnabled: false,
          actionRequiredEnabled: false,
        ),
        appLanguage: AppLanguageResponse.english,
      );
      appearanceStore.response = AppearanceSettingsResponse(
        themeMode: AppearanceThemeModeResponse.dark,
        uiFontChoice: AppearanceFontChoiceResponse.system(' Inter '),
        uiFontSize: 14,
        codeFontSize: 16,
      );
      final changes = <SettingsSnapshot>[];
      createRepository().settingsChanges.listen(changes.add);

      expect(repository.settings, SettingsSnapshot.initial);
      await repository.ready;

      expect(repository.settings.revision, 1);
      expect(
        repository.settings.general,
        const GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(
            enabled: false,
            turnTerminalEnabled: false,
            actionRequiredEnabled: false,
          ),
          appLanguage: AppLanguage.english,
        ),
      );
      expect(repository.settings.appearance.themeMode, SettingsThemeMode.dark);
      expect(
        repository.settings.appearance.uiFontChoice,
        SettingsFontChoice.system('Inter'),
      );
      expect(
        repository.settings.appearance.codeFontChoice,
        const SettingsFontChoice.bundledJetBrainsMono(),
      );
      expect(repository.settings.appearance.uiFontSize, 14);
      expect(repository.settings.appearance.codeFontSize, 16);
      expect(changes, <SettingsSnapshot>[repository.settings]);
      expect(generalStore.loadCount, 1);
      expect(appearanceStore.loadCount, 1);
    });

    test('maps light/default/system font input variants', () async {
      appearanceStore.response = AppearanceSettingsResponse(
        themeMode: AppearanceThemeModeResponse.light,
        codeFontChoice: AppearanceFontChoiceResponse.system('Mono'),
      );
      createRepository();

      await repository.ready;

      expect(repository.settings.appearance.themeMode, SettingsThemeMode.light);
      expect(
        repository.settings.appearance.uiFontChoice,
        const SettingsFontChoice.systemDefault(),
      );
      expect(
        repository.settings.appearance.codeFontChoice,
        SettingsFontChoice.system('Mono'),
      );
    });

    test('maps Data decode and external failures for both stores', () async {
      const generalDecode = SettingsDecodeException(
        document: SettingsDocumentKind.general,
        code: SettingsDecodeFailureCode.invalidField,
      );
      generalStore.loadError = generalDecode;
      createRepository();
      await expectLater(
        repository.ready,
        throwsFailure(
          SettingsRepositoryFailureCode.invalidData,
          SettingsRepositoryOperation.initializeGeneral,
          'general_settings_invalid',
          cause: generalDecode,
        ),
      );
      await repository.close().catchError((_) {});

      generalStore = FakeGeneralSettingsStore();
      appearanceStore = FakeAppearanceSettingsStore();
      const appearanceDecode = SettingsDecodeException(
        document: SettingsDocumentKind.appearance,
        code: SettingsDecodeFailureCode.unsupportedVersion,
      );
      appearanceStore.loadError = appearanceDecode;
      createRepository();
      await expectLater(
        repository.ready,
        throwsFailure(
          SettingsRepositoryFailureCode.invalidData,
          SettingsRepositoryOperation.initializeAppearance,
          'appearance_settings_invalid',
          cause: appearanceDecode,
        ),
      );
      await repository.close().catchError((_) {});

      generalStore = FakeGeneralSettingsStore()
        ..loadError = StateError('general secret');
      appearanceStore = FakeAppearanceSettingsStore();
      createRepository();
      await expectLater(
        repository.ready,
        throwsFailure(
          SettingsRepositoryFailureCode.externalFailure,
          SettingsRepositoryOperation.initializeGeneral,
          'general_settings_load_failed',
          cause: generalStore.loadError,
        ),
      );
      await repository.close().catchError((_) {});

      generalStore = FakeGeneralSettingsStore();
      appearanceStore = FakeAppearanceSettingsStore()
        ..loadError = StateError('appearance secret');
      createRepository();
      await expectLater(
        repository.ready,
        throwsFailure(
          SettingsRepositoryFailureCode.externalFailure,
          SettingsRepositoryOperation.initializeAppearance,
          'appearance_settings_load_failed',
          cause: appearanceStore.loadError,
        ),
      );
    });
  });

  group('persistence', () {
    test(
      'persists one document before publishing and skips unchanged values',
      () async {
        final changes = <SettingsSnapshot>[];
        createRepository().settingsChanges.listen(changes.add);
        await repository.ready;

        expect(
          await repository.persist(
            const GeneralSettingsUpdate(GeneralSettings()),
          ),
          SettingsPersistResult.unchanged,
        );
        const nextGeneral = GeneralSettings(
          sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
          notifications: AgentNotificationSettings(
            enabled: false,
            turnTerminalEnabled: false,
            actionRequiredEnabled: false,
          ),
          appLanguage: AppLanguage.english,
        );
        expect(
          await repository.persist(const GeneralSettingsUpdate(nextGeneral)),
          SettingsPersistResult.applied,
        );
        expect(
          generalStore.saves.single.sendMessageShortcut,
          MessageSendShortcutResponse.primaryModifierEnter,
        );
        expect(generalStore.saves.single.notifications.enabled, isFalse);
        expect(
          generalStore.saves.single.notifications.turnTerminalEnabled,
          isFalse,
        );
        expect(
          generalStore.saves.single.notifications.actionRequiredEnabled,
          isFalse,
        );
        expect(
          generalStore.saves.single.appLanguage,
          AppLanguageResponse.english,
        );
        expect(repository.settings.general, nextGeneral);
        expect(repository.settings.revision, 2);
        expect(changes, hasLength(2));
      },
    );

    test(
      'maps every appearance output variant and skips unchanged values',
      () async {
        createRepository();
        await repository.ready;
        expect(
          await repository.persist(
            const AppearanceSettingsUpdate(AppearanceSettings()),
          ),
          SettingsPersistResult.unchanged,
        );
        final values = <AppearanceSettings>[
          AppearanceSettings(
            themeMode: SettingsThemeMode.light,
            uiFontChoice: SettingsFontChoice.system('Inter'),
            codeFontChoice: SettingsFontChoice.system('Mono'),
            uiFontSize: 13,
            codeFontSize: 14,
          ),
          const AppearanceSettings(
            themeMode: SettingsThemeMode.dark,
            uiFontSize: 14,
            codeFontSize: 15,
          ),
          AppearanceSettings(
            uiFontChoice: SettingsFontChoice.system('Other'),
            uiFontSize: 15,
            codeFontSize: 16,
          ),
        ];

        for (final value in values) {
          expect(
            await repository.persist(AppearanceSettingsUpdate(value)),
            SettingsPersistResult.applied,
          );
        }

        expect(
          appearanceStore.saves.map((value) => value.themeMode),
          <AppearanceThemeModeResponse>[
            AppearanceThemeModeResponse.light,
            AppearanceThemeModeResponse.dark,
            AppearanceThemeModeResponse.system,
          ],
        );
        expect(
          appearanceStore.saves.first.uiFontChoice,
          AppearanceFontChoiceResponse.system('Inter'),
        );
        expect(
          appearanceStore.saves.first.codeFontChoice,
          AppearanceFontChoiceResponse.system('Mono'),
        );
        expect(
          appearanceStore.saves[1].uiFontChoice,
          const AppearanceFontChoiceResponse.systemDefault(),
        );
        expect(
          appearanceStore.saves[1].codeFontChoice,
          const AppearanceFontChoiceResponse.bundledJetBrainsMono(),
        );
        expect(repository.settings.appearance, values.last);
        expect(repository.settings.revision, 4);
      },
    );

    test('serializes concurrent writes in invocation order', () async {
      createRepository();
      await repository.ready;
      final firstGate = Completer<void>();
      generalStore.saveCompleter = firstGate;
      const firstValue = GeneralSettings(
        appLanguage: AppLanguage.english,
      );
      const secondValue = GeneralSettings(
        sendMessageShortcut: MessageSendShortcut.primaryModifierEnter,
      );

      final first = repository.persist(const GeneralSettingsUpdate(firstValue));
      final second = repository.persist(
        const GeneralSettingsUpdate(secondValue),
      );
      await Future<void>.delayed(Duration.zero);

      expect(generalStore.saves, <GeneralSettingsResponse>[
        const GeneralSettingsResponse(appLanguage: AppLanguageResponse.english),
      ]);
      generalStore.saveCompleter = null;
      firstGate.complete();
      expect(await first, SettingsPersistResult.applied);
      expect(await second, SettingsPersistResult.applied);
      expect(repository.settings.general, secondValue);
      expect(generalStore.saves, hasLength(2));
    });

    test(
      'translates both write failures and never publishes failed state',
      () async {
        createRepository();
        await repository.ready;
        final initial = repository.settings;
        final generalError = StateError('general write secret');
        generalStore.saveError = generalError;
        await expectLater(
          repository.persist(
            const GeneralSettingsUpdate(
              GeneralSettings(appLanguage: AppLanguage.english),
            ),
          ),
          throwsFailure(
            SettingsRepositoryFailureCode.externalFailure,
            SettingsRepositoryOperation.persistGeneral,
            'general_settings_save_failed',
            cause: generalError,
          ),
        );
        expect(repository.settings, initial);

        generalStore.saveError = null;
        final appearanceError = StateError('appearance write secret');
        appearanceStore.saveError = appearanceError;
        await expectLater(
          repository.persist(
            const AppearanceSettingsUpdate(
              AppearanceSettings(themeMode: SettingsThemeMode.dark),
            ),
          ),
          throwsFailure(
            SettingsRepositoryFailureCode.externalFailure,
            SettingsRepositoryOperation.persistAppearance,
            'appearance_settings_save_failed',
            cause: appearanceError,
          ),
        );
        expect(repository.settings, initial);

        expect(
          await repository.persist(
            const GeneralSettingsUpdate(
              GeneralSettings(appLanguage: AppLanguage.english),
            ),
          ),
          SettingsPersistResult.applied,
        );
      },
    );

    test('rejects both update kinds after close', () async {
      createRepository();
      await repository.ready;
      await repository.close();

      await expectLater(
        repository.persist(
          const GeneralSettingsUpdate(
            GeneralSettings(appLanguage: AppLanguage.english),
          ),
        ),
        throwsFailure(
          SettingsRepositoryFailureCode.closed,
          SettingsRepositoryOperation.persistGeneral,
          'repository_closed',
        ),
      );
      await expectLater(
        repository.persist(
          const AppearanceSettingsUpdate(
            AppearanceSettings(themeMode: SettingsThemeMode.dark),
          ),
        ),
        throwsFailure(
          SettingsRepositoryFailureCode.closed,
          SettingsRepositoryOperation.persistAppearance,
          'repository_closed',
        ),
      );
    });
  });

  group('font catalog', () {
    test('maps, deduplicates, sorts, filters, and freezes families', () async {
      fontCatalog.families = <SystemFontFamily>[
        SystemFontFamily(
          id: 'z',
          familyName: 'Mono',
          displayName: 'Zulu',
          aliases: const <String>['M'],
          isMonospace: true,
        ),
        SystemFontFamily(
          id: 'a',
          familyName: 'Alpha',
          displayName: 'alpha',
          aliases: const <String>['A'],
          isMonospace: false,
        ),
        SystemFontFamily(
          id: 'z',
          familyName: 'Duplicate',
          displayName: 'Duplicate',
          aliases: const <String>[],
          isMonospace: true,
        ),
      ];
      createRepository();

      final all = await repository.fontFamilies(localeName: ' zh-Hans ');
      final monospace = await repository.fontFamilies(
        localeName: 'en',
        monospaceOnly: true,
      );

      expect(fontCatalog.localeNames, <String>['zh-Hans', 'en']);
      expect(all.map((family) => family.id), <String>['a', 'z']);
      expect(all.first.familyName, 'Alpha');
      expect(all.first.displayName, 'alpha');
      expect(all.first.aliases, <String>['A']);
      expect(all.first.isMonospace, isFalse);
      expect(monospace.map((family) => family.id), <String>['z']);
      expect(all.clear, throwsUnsupportedError);
      expect(all.first.aliases.clear, throwsUnsupportedError);
    });

    test('rejects blank locale and invalid external font data', () async {
      createRepository();
      await expectLater(
        repository.fontFamilies(localeName: ' '),
        throwsFailure(
          SettingsRepositoryFailureCode.invalidInput,
          SettingsRepositoryOperation.fontFamilies,
          'locale_name_missing',
        ),
      );

      fontCatalog.families = <SystemFontFamily>[
        SystemFontFamily(
          id: ' ',
          familyName: 'Family',
          displayName: 'Family',
          aliases: const <String>[],
          isMonospace: false,
        ),
      ];
      await expectLater(
        repository.fontFamilies(localeName: 'en'),
        throwsFailure(
          SettingsRepositoryFailureCode.invalidData,
          SettingsRepositoryOperation.fontFamilies,
          'font_catalog_invalid',
        ),
      );
    });

    test('translates platform failure and rejects calls after close', () async {
      final error = StateError('font secret');
      fontCatalog.error = error;
      createRepository();
      await expectLater(
        repository.fontFamilies(localeName: 'en'),
        throwsFailure(
          SettingsRepositoryFailureCode.externalFailure,
          SettingsRepositoryOperation.fontFamilies,
          'font_catalog_failed',
          cause: error,
        ),
      );

      fontCatalog.error = null;
      await repository.close();
      await expectLater(
        repository.fontFamilies(localeName: 'en'),
        throwsFailure(
          SettingsRepositoryFailureCode.closed,
          SettingsRepositoryOperation.fontFamilies,
          'repository_closed',
        ),
      );
    });
  });

  group('close', () {
    test('is idempotent and closes both stores and the stream', () async {
      final done = Completer<void>();
      createRepository().settingsChanges.listen(null, onDone: done.complete);
      await repository.ready;

      final first = repository.close();
      final second = repository.close();
      await Future.wait(<Future<void>>[first, second, done.future]);

      expect(identical(first, second), isTrue);
      expect(generalStore.closeCount, 1);
      expect(appearanceStore.closeCount, 1);
    });

    test(
      'waits for initialization and suppresses a late initial publish',
      () async {
        final load = Completer<GeneralSettingsResponse>();
        generalStore.loadCompleter = load;
        final changes = <SettingsSnapshot>[];
        createRepository().settingsChanges.listen(changes.add);

        final close = repository.close();
        load.complete(const GeneralSettingsResponse());
        await close;

        expect(repository.settings, SettingsSnapshot.initial);
        expect(changes, isEmpty);
      },
    );

    test(
      'attempts both stores and reports the first close failure safely',
      () async {
        final generalError = StateError('general close secret');
        generalStore.closeError = generalError;
        appearanceStore.closeError = StateError('appearance close secret');
        createRepository();
        await repository.ready;

        await expectLater(
          repository.close(),
          throwsFailure(
            SettingsRepositoryFailureCode.externalFailure,
            SettingsRepositoryOperation.close,
            'settings_close_failed',
            cause: generalError,
          ),
        );
        expect(generalStore.closeCount, 1);
        expect(appearanceStore.closeCount, 1);
      },
    );

    test('still closes stores after initialization fails', () async {
      generalStore.loadError = StateError('load secret');
      createRepository();
      await expectLater(
        repository.ready,
        throwsA(isA<SettingsRepositoryException>()),
      );

      await expectLater(
        repository.close(),
        throwsFailure(
          SettingsRepositoryFailureCode.externalFailure,
          SettingsRepositoryOperation.close,
          'settings_close_failed',
        ),
      );
      expect(generalStore.closeCount, 1);
      expect(appearanceStore.closeCount, 1);
    });
  });
}

Matcher throwsFailure(
  SettingsRepositoryFailureCode code,
  SettingsRepositoryOperation operation,
  String diagnosticCode, {
  Object? cause,
}) {
  var matcher = isA<SettingsRepositoryException>()
      .having((error) => error.failure.code, 'code', code)
      .having((error) => error.failure.operation, 'operation', operation)
      .having(
        (error) => error.failure.diagnosticCode,
        'diagnosticCode',
        diagnosticCode,
      )
      .having(
        (error) => error.toString(),
        'safe string',
        isNot(contains('secret')),
      );
  if (cause != null) {
    matcher = matcher.having((error) => error.cause, 'cause', same(cause));
  }
  return throwsA(matcher);
}

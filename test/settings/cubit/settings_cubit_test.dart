import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/settings/settings.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  final font = SettingsFontFamily(
    id: 'ui',
    familyName: 'Geist',
    displayName: 'Geist',
    aliases: const <String>['Geist'],
    isMonospace: false,
  );
  final mono = SettingsFontFamily(
    id: 'mono',
    familyName: 'JetBrainsMono',
    displayName: 'JetBrainsMono',
    aliases: const <String>['Mono'],
    isMonospace: true,
  );
  const persistFailure = SettingsRepositoryFailure(
    operation: SettingsRepositoryOperation.persistGeneral,
    code: SettingsRepositoryFailureCode.externalFailure,
    diagnosticCode: 'save',
  );

  group(SettingsCubit, () {
    late SettingsRepository repository;
    late StreamController<SettingsSnapshot> changes;
    late Completer<void> appearancePersistStarted;

    setUpAll(() {
      registerFallbackValue(const GeneralSettingsUpdate(GeneralSettings()));
      registerFallbackValue(
        const AppearanceSettingsUpdate(AppearanceSettings()),
      );
    });

    setUp(() {
      repository = _MockSettingsRepository();
      changes = StreamController<SettingsSnapshot>.broadcast();
      when(() => repository.ready).thenAnswer((_) async {});
      when(() => repository.settings).thenReturn(SettingsSnapshot.initial);
      when(() => repository.settingsChanges).thenAnswer((_) => changes.stream);
      when(
        () => repository.fontFamilies(localeName: any(named: 'localeName')),
      ).thenAnswer((_) async => <SettingsFontFamily>[font]);
      when(
        () => repository.fontFamilies(
          localeName: any(named: 'localeName'),
          monospaceOnly: any(named: 'monospaceOnly'),
        ),
      ).thenAnswer((invocation) async {
        final monospace =
            invocation.namedArguments[#monospaceOnly] as bool? ?? false;
        return monospace
            ? <SettingsFontFamily>[mono]
            : <SettingsFontFamily>[font];
      });
      when(
        () => repository.persist(any()),
      ).thenAnswer((_) async => SettingsPersistResult.applied);
    });

    tearDown(() async {
      await changes.close();
    });

    SettingsCubit build() {
      return SettingsCubit(
        settingsRepository: repository,
        processLanguage: AppLanguage.english,
        fontLocaleName: 'en',
      );
    }

    blocTest<SettingsCubit, SettingsState>(
      'loads snapshot and font catalogs',
      build: build,
      act: (cubit) => cubit.load(),
      expect: () => <Matcher>[
        isA<SettingsState>().having(
          (state) => state.status,
          'status',
          SettingsStatus.loading,
        ),
        isA<SettingsState>()
            .having((state) => state.status, 'status', SettingsStatus.ready)
            .having(
              (state) => state.uiFontOptions,
              'uiFontOptions',
              hasLength(2),
            )
            .having(
              (state) => state.codeFontOptions,
              'codeFontOptions',
              hasLength(2),
            ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits failure when load throws',
      build: () {
        when(() => repository.ready).thenThrow(
          SettingsRepositoryException(
            failure: const SettingsRepositoryFailure(
              operation: SettingsRepositoryOperation.initializeGeneral,
              code: SettingsRepositoryFailureCode.externalFailure,
              diagnosticCode: 'load',
            ),
            cause: Exception(),
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (cubit) => cubit.load(),
      expect: () => <Matcher>[
        isA<SettingsState>().having(
          (state) => state.status,
          'status',
          SettingsStatus.loading,
        ),
        isA<SettingsState>().having(
          (state) => state.status,
          'status',
          SettingsStatus.failure,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'persists message shortcut sequentially',
      build: build,
      act: (cubit) => cubit.setMessageSendShortcut(
        MessageSendShortcut.primaryModifierEnter,
      ),
      verify: (cubit) {
        verify(
          () => repository.persist(any(that: isA<GeneralSettingsUpdate>())),
        ).called(1);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'persists notification preference flags',
      build: build,
      act: (cubit) async {
        await cubit.setNotificationsEnabled(enabled: false);
        await cubit.setTurnTerminalNotificationsEnabled(enabled: false);
        await cubit.setActionRequiredNotificationsEnabled(enabled: false);
      },
      verify: (_) {
        verify(
          () => repository.persist(any(that: isA<GeneralSettingsUpdate>())),
        ).called(3);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'marks language restart when the process language differs',
      build: build,
      act: (cubit) => cubit.setAppLanguage(AppLanguage.simplifiedChinese),
      expect: () => <Matcher>[
        isA<SettingsState>().having(
          (state) => state.languageRestartRequired,
          'languageRestartRequired',
          isTrue,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'does not mark language restart when matching the process language',
      build: build,
      act: (cubit) => cubit.setAppLanguage(AppLanguage.english),
      expect: () => <Matcher>[
        isA<SettingsState>().having(
          (state) => state.languageRestartRequired,
          'languageRestartRequired',
          isFalse,
        ),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'emits failure when general persist throws',
      build: () {
        when(() => repository.persist(any())).thenThrow(
          SettingsRepositoryException(
            failure: persistFailure,
            cause: Exception(),
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (cubit) => cubit.setNotificationsEnabled(enabled: false),
      expect: () => <Matcher>[
        isA<SettingsState>()
            .having(
              (state) => state.status,
              'status',
              SettingsStatus.failure,
            )
            .having((state) => state.failure, 'failure', persistFailure),
      ],
    );

    test(
      'propagates unexpected persist errors through the write queue',
      () async {
        when(() => repository.persist(any())).thenThrow(Exception('io'));
        final cubit = build();
        addTearDown(cubit.close);
        await expectLater(
          cubit.setNotificationsEnabled(enabled: false),
          throwsA(isA<Exception>()),
        );
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'applies languageRestartRequired when persist reports unchanged',
      build: () {
        when(
          () => repository.persist(any()),
        ).thenAnswer((_) async => SettingsPersistResult.unchanged);
        return build();
      },
      act: (cubit) => cubit.setAppLanguage(AppLanguage.simplifiedChinese),
      verify: (cubit) {
        expect(cubit.state.languageRestartRequired, isTrue);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'coalesces rapid appearance writes to the latest value',
      build: build,
      act: (cubit) {
        cubit
          ..setThemeMode(SettingsThemeMode.dark)
          ..setThemeMode(SettingsThemeMode.light);
      },
      wait: const Duration(milliseconds: 10),
      verify: (cubit) {
        final captured = verify(
          () => repository.persist(captureAny()),
        ).captured;
        expect(captured, isNotEmpty);
        final last = captured.last as AppearanceSettingsUpdate;
        expect(last.value.themeMode, SettingsThemeMode.light);
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'flushes leftover appearance writes after an in-flight persist',
      build: () {
        appearancePersistStarted = Completer<void>();
        var calls = 0;
        when(() => repository.persist(any())).thenAnswer((_) async {
          calls += 1;
          if (calls == 1) {
            appearancePersistStarted.complete();
            await Future<void>.delayed(const Duration(milliseconds: 20));
          }
          return SettingsPersistResult.applied;
        });
        return build();
      },
      act: (cubit) async {
        cubit.setUiFontSize(14);
        await appearancePersistStarted.future;
        cubit
          ..setCodeFontSize(16)
          ..setUiFontChoice(SettingsFontChoice.system('Geist'))
          ..setCodeFontChoice(
            const SettingsFontChoice.bundledJetBrainsMono(),
          );
      },
      wait: const Duration(milliseconds: 40),
      verify: (_) {
        verify(
          () => repository.persist(any(that: isA<AppearanceSettingsUpdate>())),
        ).called(greaterThanOrEqualTo(2));
      },
    );

    blocTest<SettingsCubit, SettingsState>(
      'reverts appearance draft when persist fails',
      build: () {
        when(() => repository.persist(any())).thenThrow(
          SettingsRepositoryException(
            failure: const SettingsRepositoryFailure(
              operation: SettingsRepositoryOperation.persistAppearance,
              code: SettingsRepositoryFailureCode.externalFailure,
              diagnosticCode: 'save',
            ),
            cause: Exception(),
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (cubit) => cubit.setThemeMode(SettingsThemeMode.dark),
      wait: const Duration(milliseconds: 10),
      expect: () => <Matcher>[
        isA<SettingsState>().having(
          (state) => state.appearance.themeMode,
          'themeMode',
          SettingsThemeMode.dark,
        ),
        isA<SettingsState>()
            .having((state) => state.status, 'status', SettingsStatus.failure)
            .having((state) => state.appearanceDraft, 'draft', isNull),
      ],
    );

    blocTest<SettingsCubit, SettingsState>(
      'applies external snapshot updates',
      build: build,
      act: (cubit) {
        changes.add(
          const SettingsSnapshot(
            general: GeneralSettings(appLanguage: AppLanguage.english),
            appearance: AppearanceSettings(),
            revision: 4,
          ),
        );
      },
      expect: () => <Matcher>[
        isA<SettingsState>()
            .having((state) => state.snapshot.revision, 'revision', 4)
            .having(
              (state) => state.general.appLanguage,
              'appLanguage',
              AppLanguage.english,
            ),
      ],
    );

    test('AppearanceFontOption matches labels and aliases', () {
      const bundled = AppearanceFontOption.bundledJetBrainsMono();
      const systemDefault = AppearanceFontOption.systemDefault();
      final system = AppearanceFontOption.system(font);
      expect(bundled.matches(''), isTrue);
      expect(bundled.matches('jetbrains'), isTrue);
      expect(bundled.matches('missing'), isFalse);
      expect(systemDefault.matches('Geist'), isTrue);
      expect(systemDefault.matches('system default'), isTrue);
      expect(system.matches('Geist'), isTrue);
      expect(
        const SettingsState().copyWith(clearFailure: true).failure,
        isNull,
      );
    });
  });
}

import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/settings/settings.dart';

import '../../helpers/helpers.dart';

class _MockSettingsCubit extends MockCubit<SettingsState>
    implements SettingsCubit {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

void main() {
  group(SettingsPage, () {
    late SettingsRepository repository;

    setUp(() {
      repository = _MockSettingsRepository();
      when(() => repository.ready).thenAnswer((_) async {});
      when(() => repository.settings).thenReturn(SettingsSnapshot.initial);
      when(
        () => repository.settingsChanges,
      ).thenAnswer((_) => const Stream<SettingsSnapshot>.empty());
      when(
        () => repository.fontFamilies(localeName: any(named: 'localeName')),
      ).thenAnswer((_) async => const <SettingsFontFamily>[]);
      when(
        () => repository.fontFamilies(
          localeName: any(named: 'localeName'),
          monospaceOnly: any(named: 'monospaceOnly'),
        ),
      ).thenAnswer((_) async => const <SettingsFontFamily>[]);
    });

    testWidgets('renders $SettingsView', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<SettingsRepository>.value(value: repository),
            RepositoryProvider<AppDependencies>.value(
              value: AppDependencies(
                locale: const Locale('en'),
                failureMessages: FailureMessages(l10n),
                desktopNotificationCopyResolver:
                    DesktopNotificationCopyResolver(l10n),
                desktopChromeCopyResolver: DesktopChromeCopyResolver(
                  l10n,
                ),
              ),
            ),
          ],
          child: const SettingsPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(SettingsView), findsOneWidget);
    });
  });

  group(SettingsView, () {
    late SettingsCubit cubit;

    setUpAll(() {
      registerFallbackValue(MessageSendShortcut.enter);
      registerFallbackValue(AppLanguage.english);
      registerFallbackValue(SettingsThemeMode.system);
    });

    setUp(() {
      cubit = _MockSettingsCubit();
      when(() => cubit.state).thenReturn(
        const SettingsState(status: SettingsStatus.ready),
      );
      when(
        () => cubit.setMessageSendShortcut(any()),
      ).thenAnswer((_) async {});
      when(
        () => cubit.setNotificationsEnabled(enabled: any(named: 'enabled')),
      ).thenAnswer((_) async {});
      when(
        () => cubit.setTurnTerminalNotificationsEnabled(
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => cubit.setActionRequiredNotificationsEnabled(
          enabled: any(named: 'enabled'),
        ),
      ).thenAnswer((_) async {});
      when(() => cubit.setAppLanguage(any())).thenAnswer((_) async {});
      when(() => cubit.setThemeMode(any())).thenReturn(null);
    });

    testWidgets('renders a loading indicator before settings are ready', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(
        const SettingsState(status: SettingsStatus.loading),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders a loading indicator for $SettingsStatus.initial', (
      tester,
    ) async {
      when(() => cubit.state).thenReturn(const SettingsState());
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('renders general settings sections', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      expect(find.text('General'), findsOneWidget);
      expect(find.text('Notifications'), findsOneWidget);
    });

    testWidgets('renders a settings failure and restart hint', (tester) async {
      when(() => cubit.state).thenReturn(
        const SettingsState(
          status: SettingsStatus.failure,
          languageRestartRequired: true,
          failure: SettingsRepositoryFailure(
            operation: SettingsRepositoryOperation.persistGeneral,
            code: SettingsRepositoryFailureCode.externalFailure,
            diagnosticCode: 'save',
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).settingsFailure(
            SettingsRepositoryFailureCode.externalFailure,
          ),
        ),
        findsOneWidget,
      );
      expect(find.text(l10n.settingsLanguageRestartToApply), findsOneWidget);
    });

    testWidgets('calls setNotificationsEnabled when the switch is toggled', (
      tester,
    ) async {
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      await tester.tap(find.byType(Switch).at(1));
      await tester.pump();
      verify(
        () => cubit.setNotificationsEnabled(enabled: false),
      ).called(1);
    });

    testWidgets('toggles remaining settings controls', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: cubit, child: const SettingsView()),
      );
      await tester.tap(find.byType(Switch).at(0));
      await tester.tap(find.byType(Switch).at(2));
      await tester.tap(find.byType(Switch).at(3));
      await tester.tap(find.byType(Switch).at(4));
      final themeSwitch = find.byType(Switch).at(5);
      await tester.ensureVisible(themeSwitch);
      await tester.pump();
      await tester.tap(themeSwitch);
      await tester.pump();
      verify(
        () => cubit.setMessageSendShortcut(
          MessageSendShortcut.primaryModifierEnter,
        ),
      ).called(1);
      verify(
        () => cubit.setTurnTerminalNotificationsEnabled(enabled: false),
      ).called(1);
      verify(
        () => cubit.setActionRequiredNotificationsEnabled(enabled: false),
      ).called(1);
      verify(() => cubit.setAppLanguage(AppLanguage.english)).called(1);
      verify(() => cubit.setThemeMode(SettingsThemeMode.dark)).called(1);
    });
  });
}

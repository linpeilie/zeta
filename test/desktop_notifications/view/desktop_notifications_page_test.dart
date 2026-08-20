import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/desktop_notifications/desktop_notifications.dart';
import 'package:zeta/l10n/l10n.dart';

import '../../helpers/helpers.dart';

class _MockDesktopNotificationsBloc
    extends MockBloc<DesktopNotificationsEvent, DesktopNotificationsState>
    implements DesktopNotificationsBloc {}

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockNotificationsRepository extends Mock
    implements DesktopNotificationsRepository {}

void main() {
  const attention = AgentWorkspaceAttention(
    signal: AgentAttentionSignal(
      kind: AgentAttentionKind.turnCompleted,
      phase: AgentAttentionPhase.raised,
      sourceId: 'turn-1',
      threadId: 'thread-1',
    ),
    providerId: 'codex',
    threadId: 'thread-1',
    projectPath: '/repo',
  );

  group(DesktopNotificationsPage, () {
    late SettingsRepository settingsRepository;
    late DesktopNotificationsRepository notificationsRepository;

    setUp(() {
      settingsRepository = _MockSettingsRepository();
      notificationsRepository = _MockNotificationsRepository();
      when(() => settingsRepository.ready).thenAnswer((_) async {});
      when(
        () => settingsRepository.settings,
      ).thenReturn(SettingsSnapshot.initial);
      when(
        () => settingsRepository.settingsChanges,
      ).thenAnswer((_) => const Stream<SettingsSnapshot>.empty());
    });

    testWidgets('renders $DesktopNotificationsView', (tester) async {
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<SettingsRepository>.value(
              value: settingsRepository,
            ),
            RepositoryProvider<DesktopNotificationsRepository>.value(
              value: notificationsRepository,
            ),
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
          child: const DesktopNotificationsPage(),
        ),
      );
      await tester.pump();
      expect(find.byType(DesktopNotificationsView), findsOneWidget);
    });
  });

  group(DesktopNotificationsView, () {
    late DesktopNotificationsBloc bloc;

    setUp(() {
      bloc = _MockDesktopNotificationsBloc();
      when(() => bloc.state).thenReturn(
        const DesktopNotificationsState(
          status: DesktopNotificationsStatus.ready,
        ),
      );
    });

    testWidgets('renders unread badge count', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(
          value: bloc,
          child: const DesktopNotificationsView(),
        ),
      );
      expect(find.text('Notifications: 0'), findsOneWidget);
    });

    testWidgets('renders a notification failure message', (tester) async {
      when(() => bloc.state).thenReturn(
        const DesktopNotificationsState(
          status: DesktopNotificationsStatus.failure,
          failure: DesktopNotificationOperation.notify,
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(
          value: bloc,
          child: const DesktopNotificationsView(),
        ),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).desktopNotificationFailure(
            DesktopNotificationOperation.notify,
          ),
        ),
        findsOneWidget,
      );
    });

    testWidgets('marks the first unread thread read', (tester) async {
      when(() => bloc.state).thenReturn(
        const DesktopNotificationsState(
          status: DesktopNotificationsStatus.ready,
          unread: <String, AgentWorkspaceAttention>{
            'turnCompleted:codex:thread-1:turn-1': attention,
          },
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(
          value: bloc,
          child: const DesktopNotificationsView(),
        ),
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      verify(
        () => bloc.add(
          const DesktopNotificationsThreadMarkedRead(
            providerId: 'codex',
            threadId: 'thread-1',
          ),
        ),
      ).called(1);
    });
  });
}

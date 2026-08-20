import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/desktop_notifications/desktop_notifications.dart';
import 'package:zeta/l10n/l10n.dart';

class _MockSettingsRepository extends Mock implements SettingsRepository {}

class _MockNotificationsRepository extends Mock
    implements DesktopNotificationsRepository {}

void main() {
  AgentWorkspaceAttention attentionFor(
    AgentAttentionKind kind, {
    AgentAttentionPhase phase = AgentAttentionPhase.raised,
    String sourceId = 'turn-1',
  }) {
    return AgentWorkspaceAttention(
      signal: AgentAttentionSignal(
        kind: kind,
        phase: phase,
        sourceId: sourceId,
        threadId: 'thread-1',
      ),
      providerId: 'codex',
      threadId: 'thread-1',
      projectPath: '/repo',
    );
  }

  final attention = attentionFor(AgentAttentionKind.turnCompleted);

  group(DesktopNotificationsBloc, () {
    late SettingsRepository settingsRepository;
    late DesktopNotificationsRepository notificationsRepository;
    late StreamController<SettingsSnapshot> settingsChanges;
    late DesktopNotificationCopyResolver copyResolver;

    setUpAll(() {
      registerFallbackValue(
        const NotificationRequest(title: 't', body: 'b'),
      );
    });

    setUp(() {
      settingsRepository = _MockSettingsRepository();
      notificationsRepository = _MockNotificationsRepository();
      settingsChanges = StreamController<SettingsSnapshot>.broadcast();
      copyResolver = DesktopNotificationCopyResolver(
        lookupAppLocalizations(const Locale('en')),
      );
      when(() => settingsRepository.ready).thenAnswer((_) async {});
      when(
        () => settingsRepository.settings,
      ).thenReturn(SettingsSnapshot.initial);
      when(
        () => settingsRepository.settingsChanges,
      ).thenAnswer((_) => settingsChanges.stream);
      when(
        () => notificationsRepository.notify(any()),
      ).thenAnswer((_) async {});
      when(
        () => notificationsRepository.setBadge(any()),
      ).thenAnswer((_) async {});
      when(
        () => notificationsRepository.requestAttention(),
      ).thenAnswer((_) async {});
    });

    tearDown(() async {
      await settingsChanges.close();
    });

    DesktopNotificationsBloc build() {
      return DesktopNotificationsBloc(
        settingsRepository: settingsRepository,
        notificationsRepository: notificationsRepository,
        copyResolver: copyResolver,
      );
    }

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'subscribes to settings and becomes ready',
      build: build,
      act: (bloc) =>
          bloc.add(const DesktopNotificationsSubscriptionRequested()),
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.status,
          'status',
          DesktopNotificationsStatus.ready,
        ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'emits failure when settings ready throws',
      build: () {
        when(() => settingsRepository.ready).thenThrow(
          const SettingsRepositoryException(
            failure: SettingsRepositoryFailure(
              operation: SettingsRepositoryOperation.initializeGeneral,
              code: SettingsRepositoryFailureCode.externalFailure,
              diagnosticCode: 'ready',
            ),
            cause: 'notify',
            stackTrace: StackTrace.empty,
          ),
        );
        return build();
      },
      act: (bloc) =>
          bloc.add(const DesktopNotificationsSubscriptionRequested()),
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>()
            .having(
              (state) => state.status,
              'status',
              DesktopNotificationsStatus.failure,
            )
            .having(
              (state) => state.failure,
              'failure',
              DesktopNotificationOperation.notify,
            ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'notifies and badges a raised attention signal',
      build: build,
      act: (bloc) async {
        bloc.add(const DesktopNotificationsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      verify: (bloc) {
        expect(bloc.state.badgeCount, 1);
        verify(() => notificationsRepository.notify(any())).called(1);
        verify(() => notificationsRepository.setBadge(1)).called(1);
        verify(() => notificationsRepository.requestAttention()).called(1);
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'notifies every enabled attention kind',
      build: build,
      act: (bloc) async {
        bloc.add(const DesktopNotificationsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        for (final kind in AgentAttentionKind.values) {
          bloc.add(
            DesktopNotificationsAttentionReceived(
              attentionFor(kind, sourceId: kind.name),
            ),
          );
        }
      },
      wait: const Duration(milliseconds: 100),
      verify: (bloc) {
        expect(bloc.state.badgeCount, AgentAttentionKind.values.length);
        verify(
          () => notificationsRepository.notify(any()),
        ).called(AgentAttentionKind.values.length);
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'ignores attention when the current canvas already shows it',
      build: build,
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        visibility: DesktopNotificationsVisibility(
          windowFocused: true,
          agentCanvasVisible: true,
          providerId: 'codex',
          threadId: 'thread-1',
        ),
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => const <DesktopNotificationsState>[],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'ignores duplicate unread identities',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => const <DesktopNotificationsState>[],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'ignores attention when notifications are disabled',
      build: build,
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        notifications: AgentNotificationSettings(enabled: false),
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => const <DesktopNotificationsState>[],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'filters unread items when settings disable a category',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
          attentionFor(
            AgentAttentionKind.permissionRequired,
            sourceId: 'perm-1',
          ).identity: attentionFor(
            AgentAttentionKind.permissionRequired,
            sourceId: 'perm-1',
          ),
        },
      ),
      act: (bloc) async {
        bloc.add(const DesktopNotificationsSubscriptionRequested());
        await Future<void>.delayed(Duration.zero);
        settingsChanges.add(
          const SettingsSnapshot(
            general: GeneralSettings(
              notifications: AgentNotificationSettings(
                turnTerminalEnabled: false,
              ),
            ),
            appearance: AppearanceSettings(),
            revision: 2,
          ),
        );
        await Future<void>.delayed(Duration.zero);
      },
      verify: (bloc) {
        expect(bloc.state.unread.length, 1);
        expect(
          bloc.state.unread.values.single.signal.kind,
          AgentAttentionKind.permissionRequired,
        );
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'clears a resolved attention identity',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(
          DesktopNotificationsAttentionReceived(
            attentionFor(
              AgentAttentionKind.turnCompleted,
              phase: AgentAttentionPhase.resolved,
            ),
          ),
        );
      },
      verify: (bloc) {
        expect(bloc.state.unread, isEmpty);
        verify(() => notificationsRepository.setBadge(0)).called(1);
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'marks a visible thread read',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(
          const DesktopNotificationsVisibilityUpdated(
            DesktopNotificationsVisibility(
              windowFocused: true,
              agentCanvasVisible: true,
              providerId: 'codex',
              threadId: 'thread-1',
            ),
          ),
        );
      },
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.visibility.windowFocused,
          'focused',
          isTrue,
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.unread,
          'unread',
          isEmpty,
        ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'does not clear unread when the canvas is not focused',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(
          const DesktopNotificationsVisibilityUpdated(
            DesktopNotificationsVisibility(
              agentCanvasVisible: true,
              providerId: 'codex',
              threadId: 'thread-1',
            ),
          ),
        );
      },
      verify: (bloc) {
        expect(bloc.state.unread, isNotEmpty);
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'marks a thread read through an explicit event',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(
          const DesktopNotificationsThreadMarkedRead(
            providerId: 'codex',
            threadId: 'thread-1',
          ),
        );
      },
      verify: (bloc) {
        expect(bloc.state.unread, isEmpty);
      },
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'ignores mark-read when the thread is already empty',
      build: build,
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
      ),
      act: (bloc) {
        bloc.add(
          const DesktopNotificationsThreadMarkedRead(
            providerId: 'codex',
            threadId: 'thread-1',
          ),
        );
      },
      expect: () => const <DesktopNotificationsState>[],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'emits and clears an activation request',
      build: build,
      seed: () => DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
        unread: <String, AgentWorkspaceAttention>{
          attention.identity: attention,
        },
      ),
      act: (bloc) {
        bloc.add(
          const DesktopNotificationsActivationRequested(
            providerId: 'codex',
            threadId: 'thread-1',
          ),
        );
      },
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.activation?.threadId,
          'activation',
          'thread-1',
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.unread,
          'unread',
          isEmpty,
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.activation,
          'activation',
          isNull,
        ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'emits failure when notify throws',
      build: () {
        when(() => notificationsRepository.notify(any())).thenThrow(
          const DesktopNotificationException(
            operation: DesktopNotificationOperation.notify,
            cause: 'notify',
          ),
        );
        return build();
      },
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.badgeCount,
          'badgeCount',
          1,
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.failure,
          'failure',
          DesktopNotificationOperation.notify,
        ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'emits failure when setBadge throws',
      build: () {
        when(() => notificationsRepository.setBadge(any())).thenThrow(
          const DesktopNotificationException(
            operation: DesktopNotificationOperation.setBadge,
            cause: 'notify',
          ),
        );
        return build();
      },
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.badgeCount,
          'badgeCount',
          1,
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.failure,
          'failure',
          DesktopNotificationOperation.setBadge,
        ),
      ],
    );

    blocTest<DesktopNotificationsBloc, DesktopNotificationsState>(
      'emits failure when requestAttention throws',
      build: () {
        when(() => notificationsRepository.requestAttention()).thenThrow(
          const DesktopNotificationException(
            operation: DesktopNotificationOperation.requestAttention,
            cause: 'notify',
          ),
        );
        return build();
      },
      seed: () => const DesktopNotificationsState(
        status: DesktopNotificationsStatus.ready,
      ),
      act: (bloc) {
        bloc.add(DesktopNotificationsAttentionReceived(attention));
      },
      expect: () => <Matcher>[
        isA<DesktopNotificationsState>().having(
          (state) => state.badgeCount,
          'badgeCount',
          1,
        ),
        isA<DesktopNotificationsState>().having(
          (state) => state.failure,
          'failure',
          DesktopNotificationOperation.requestAttention,
        ),
      ],
    );

    test('event equality uses value props', () {
      const settings = AgentNotificationSettings();
      const visibility = DesktopNotificationsVisibility();
      expect(
        const DesktopNotificationsSubscriptionRequested().props,
        isEmpty,
      );
      expect(
        const DesktopNotificationsSettingsChanged(settings).props,
        <Object?>[settings],
      );
      expect(
        DesktopNotificationsAttentionReceived(attention).props,
        <Object?>[attention],
      );
      expect(
        const DesktopNotificationsVisibilityUpdated(visibility).props,
        <Object?>[visibility],
      );
      expect(
        const DesktopNotificationsThreadMarkedRead(
          providerId: 'codex',
          threadId: 'thread-1',
        ).props,
        <Object?>['codex', 'thread-1'],
      );
      expect(
        const DesktopNotificationsActivationRequested(
          providerId: 'codex',
          threadId: 'thread-1',
        ).props,
        <Object?>['codex', 'thread-1'],
      );
    });

    test('visibility and copyWith cover remaining state flags', () {
      const visibility = DesktopNotificationsVisibility(
        windowFocused: true,
        agentCanvasVisible: true,
        providerId: 'codex',
        threadId: 'thread-1',
      );
      expect(visibility.shows(attention), isTrue);
      const state = DesktopNotificationsState(
        activation: DesktopNotificationsActivation(
          providerId: 'codex',
          threadId: 'thread-1',
        ),
        failure: DesktopNotificationOperation.notify,
      );
      final cleared = state.copyWith(
        clearActivation: true,
        clearFailure: true,
      );
      expect(cleared.activation, isNull);
      expect(cleared.failure, isNull);
      expect(cleared.badgeCount, 0);
    });
  });
}

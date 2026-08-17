import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_controller.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

void main() {
  test(
    'suppresses the visible thread and deduplicates background signals',
    () async {
      final harness = await _createHarness();
      addTearDown(harness.dispose);
      final attention = _attention();
      harness.controller.updateVisibility(
        const DesktopAttentionVisibility(
          windowFocused: true,
          agentCanvasVisible: true,
          providerId: 'codex',
          threadId: 'thread-1',
        ),
      );

      await harness.controller.handleAttention(attention);

      expect(harness.notifications.shown, isEmpty);
      expect(harness.controller.unreadCount, 0);

      harness.controller.updateVisibility(
        const DesktopAttentionVisibility(windowFocused: false),
      );
      await harness.controller.handleAttention(attention);
      await harness.controller.handleAttention(attention);

      expect(harness.notifications.shown, hasLength(1));
      expect(harness.notifications.shown.single.title, '任务已完成');
      expect(harness.notifications.shown.single.body, 'zeta · Agent 会话');
      expect(
        harness.notifications.shown.single.body,
        isNot(contains('secret')),
      );
      expect(harness.controller.unreadCount, 1);
      expect(harness.indicator.counts.last, 1);
      expect(harness.indicator.attentionRequests, 1);
    },
  );

  test('resolved signal cancels the notification and clears unread', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);
    await harness.controller.handleAttention(_attention());
    final shownId = harness.notifications.shown.single.id;

    await harness.controller.handleAttention(
      _attention(phase: AgentAttentionPhase.resolved),
    );

    expect(harness.notifications.cancelledIds, <int>[shownId]);
    expect(harness.controller.unreadCount, 0);
    expect(harness.indicator.counts.last, 0);
  });

  test('notification activation opens its thread and marks it read', () async {
    final activations = <(String, String)>[];
    final harness = await _createHarness(
      activateTarget: (providerId, threadId) async {
        activations.add((providerId, threadId));
        return true;
      },
    );
    addTearDown(harness.dispose);
    await harness.controller.handleAttention(
      _attention(kind: AgentAttentionKind.permissionRequired),
    );

    await harness.notifications.activateLast();

    expect(activations, <(String, String)>[('codex', 'thread-1')]);
    expect(harness.controller.unreadCount, 0);
    expect(harness.notifications.cancelledIds, hasLength(1));
  });

  test(
    'initial launch payload activates its thread after initialization',
    () async {
      final activations = <(String, String)>[];
      final harness = await _createHarness(
        initialPayload:
            '{"version":1,"providerId":"codex","threadId":"thread-cold"}',
        activateTarget: (providerId, threadId) async {
          activations.add((providerId, threadId));
          return true;
        },
      );
      addTearDown(harness.dispose);

      await pumpEventQueue();

      expect(activations, <(String, String)>[('codex', 'thread-cold')]);
    },
  );

  test('category switches clear and suppress matching notifications', () async {
    final harness = await _createHarness();
    addTearDown(harness.dispose);
    await harness.controller.handleAttention(_attention());
    expect(harness.controller.unreadCount, 1);

    await harness.settings.setTurnTerminalNotificationsEnabled(false);
    await pumpEventQueue();

    expect(harness.controller.unreadCount, 0);
    await harness.controller.handleAttention(_attention(sourceId: 'turn-2'));
    expect(harness.notifications.shown, hasLength(1));

    await harness.controller.handleAttention(
      _attention(
        kind: AgentAttentionKind.questionRequired,
        sourceId: 'question-1',
      ),
    );
    expect(harness.notifications.shown, hasLength(2));

    expect(harness.notifications.permissionRequests, 1);
    await harness.settings.setNotificationsEnabled(false);
    await harness.settings.setNotificationsEnabled(true);
    await pumpEventQueue();
    expect(harness.notifications.permissionRequests, 2);
  });

  test(
    'localizes every attention kind and keeps payload fields identical',
    () async {
      const zhCatalog = FallbackDesktopAttentionTextCatalog();
      final enCatalog = AppDesktopAttentionTextCatalog(
        lookupAppLocalizations(ZetaLocalization.english),
      );
      final expectedZh = <AgentAttentionKind, String>{
        AgentAttentionKind.turnCompleted: '任务已完成',
        AgentAttentionKind.turnFailed: '任务执行失败',
        AgentAttentionKind.turnInterrupted: '任务已中断',
        AgentAttentionKind.permissionRequired: '需要确认权限',
        AgentAttentionKind.questionRequired: '需要回答问题',
        AgentAttentionKind.planApprovalRequired: '需要确认计划',
        AgentAttentionKind.planExecutionRequired: '计划可以执行',
      };
      final expectedEn = <AgentAttentionKind, String>{
        AgentAttentionKind.turnCompleted: 'Task completed',
        AgentAttentionKind.turnFailed: 'Task failed',
        AgentAttentionKind.turnInterrupted: 'Task interrupted',
        AgentAttentionKind.permissionRequired: 'Permission required',
        AgentAttentionKind.questionRequired: 'Question required',
        AgentAttentionKind.planApprovalRequired: 'Plan approval required',
        AgentAttentionKind.planExecutionRequired: 'Plan ready to execute',
      };

      for (final kind in AgentAttentionKind.values) {
        final zhHarness = await _createHarness(textCatalog: zhCatalog);
        final enHarness = await _createHarness(textCatalog: enCatalog);
        addTearDown(zhHarness.dispose);
        addTearDown(enHarness.dispose);

        await zhHarness.controller.handleAttention(_attention(kind: kind));
        await enHarness.controller.handleAttention(_attention(kind: kind));

        final zhRequest = zhHarness.notifications.shown.single;
        final enRequest = enHarness.notifications.shown.single;
        expect(zhRequest.title, expectedZh[kind]);
        expect(enRequest.title, expectedEn[kind]);
        expect(zhRequest.body, 'zeta · Agent 会话');
        expect(enRequest.body, 'zeta · Agent session');
        expect(jsonDecode(zhRequest.payload), jsonDecode(enRequest.payload));
        expect(jsonDecode(zhRequest.payload), <String, Object?>{
          'version': 1,
          'providerId': 'codex',
          'threadId': 'thread-1',
          'identity': '${kind.name}:codex:thread-1:turn-1',
        });
        expect(zhRequest.payload, isNot(contains(zhRequest.body)));
        expect(enRequest.payload, isNot(contains(enRequest.body)));
        expect(zhRequest.payload, isNot(contains(zhRequest.title)));
        expect(enRequest.payload, isNot(contains(enRequest.title)));
      }
    },
  );

  test('uses catalog fallback when the project path has no name', () async {
    final enHarness = await _createHarness(
      textCatalog: AppDesktopAttentionTextCatalog(
        lookupAppLocalizations(ZetaLocalization.english),
      ),
    );
    addTearDown(enHarness.dispose);

    await enHarness.controller.handleAttention(_attention(projectPath: ''));

    expect(
      enHarness.notifications.shown.single.body,
      'Current project · Agent session',
    );
  });
}

Future<_Harness> _createHarness({
  String? initialPayload,
  DesktopAttentionTargetActivator? activateTarget,
  DesktopAttentionTextCatalog textCatalog =
      const FallbackDesktopAttentionTextCatalog(),
}) async {
  final notifications = _FakeNotificationService(
    initialPayload: initialPayload,
  );
  final indicator = _FakeAttentionIndicator();
  final settings = GeneralSettingsController(
    store: MemoryGeneralSettingsStore(),
  );
  final controller = DesktopAttentionController(
    notificationService: notifications,
    indicator: indicator,
    generalSettingsController: settings,
    activateTarget: activateTarget ?? (_, _) async => true,
    textCatalog: textCatalog,
  );
  await controller.initialize();
  return _Harness(
    controller: controller,
    notifications: notifications,
    indicator: indicator,
    settings: settings,
  );
}

AgentWorkspaceAttention _attention({
  AgentAttentionKind kind = AgentAttentionKind.turnCompleted,
  AgentAttentionPhase phase = AgentAttentionPhase.raised,
  String sourceId = 'turn-1',
  String projectPath = r'C:\secret\zeta',
}) {
  return AgentWorkspaceAttention(
    signal: AgentAttentionSignal(
      kind: kind,
      phase: phase,
      sourceId: sourceId,
      threadId: 'thread-1',
      turnId: 'turn-1',
    ),
    providerId: 'codex',
    threadId: 'thread-1',
    projectPath: projectPath,
  );
}

final class _Harness {
  const _Harness({
    required this.controller,
    required this.notifications,
    required this.indicator,
    required this.settings,
  });

  final DesktopAttentionController controller;
  final _FakeNotificationService notifications;
  final _FakeAttentionIndicator indicator;
  final GeneralSettingsController settings;

  void dispose() {
    controller.dispose();
    settings.dispose();
  }
}

final class _FakeNotificationService implements DesktopNotificationService {
  _FakeNotificationService({this.initialPayload});

  final String? initialPayload;
  DesktopNotificationActivation? _onActivate;
  final List<DesktopNotificationRequest> shown = <DesktopNotificationRequest>[];
  final List<int> cancelledIds = <int>[];
  int permissionRequests = 0;

  @override
  Future<String?> initialize({
    required DesktopNotificationActivation onActivate,
  }) async {
    _onActivate = onActivate;
    return initialPayload;
  }

  @override
  Future<bool?> requestPermissions() async {
    permissionRequests += 1;
    return true;
  }

  @override
  Future<void> show(DesktopNotificationRequest request) async {
    shown.add(request);
  }

  @override
  Future<void> cancel(int id) async {
    cancelledIds.add(id);
  }

  Future<void> activateLast() async {
    _onActivate?.call(shown.last.payload);
    await pumpEventQueue();
  }

  @override
  void dispose() {}
}

final class _FakeAttentionIndicator implements DesktopAttentionIndicator {
  final List<int> counts = <int>[];
  int attentionRequests = 0;

  @override
  Future<void> setUnreadCount(int count) async {
    counts.add(count);
  }

  @override
  Future<void> requestAttention() async {
    attentionRequests += 1;
  }
}

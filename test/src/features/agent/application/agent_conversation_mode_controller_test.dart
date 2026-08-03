import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/domain/agent_conversation_mode_models.dart';
import 'package:zeta/src/features/agent/domain/agent_event_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

void main() {
  group('AgentConversationModeState', () {
    test('exposes an immutable preset snapshot', () {
      final source = <AgentConversationModePreset>[_defaultPreset];
      final state = AgentConversationModeState(
        status: AgentConversationModeLoadStatus.ready,
        presets: source,
      );

      source.add(_planPreset);

      expect(state.presets, <AgentConversationModePreset>[_defaultPreset]);
      expect(() => state.presets.add(_planPreset), throwsUnsupportedError);
    });
  });

  group('AgentConversationModeController catalog', () {
    test('loads a complete catalog and defaults the next turn mode', () async {
      final controller = AgentConversationModeController();
      addTearDown(controller.dispose);

      await controller.loadCatalog(
        providerId: 'codex',
        port: _FakeModeCatalogPort(() async => _catalog()),
      );

      expect(controller.state.status, AgentConversationModeLoadStatus.ready);
      expect(controller.state.presets, <AgentConversationModePreset>[
        _defaultPreset,
        _planPreset,
      ]);
      expect(controller.state.draftMode, AgentConversationModeId.defaultMode);
      expect(controller.state.confirmedMode, isNull);
    });

    test('keeps an unsupported or incomplete provider unavailable', () async {
      final controller = AgentConversationModeController();
      addTearDown(controller.dispose);

      await controller.loadCatalog(providerId: 'grok', port: null);

      expect(
        controller.state.status,
        AgentConversationModeLoadStatus.unavailable,
      );
      expect(controller.state.presets, isEmpty);

      await controller.loadCatalog(
        providerId: 'codex',
        port: _FakeModeCatalogPort(
          () async => AgentConversationModeCatalog(
            presets: const <AgentConversationModePreset>[_defaultPreset],
          ),
        ),
      );

      expect(
        controller.state.status,
        AgentConversationModeLoadStatus.unavailable,
      );
      expect(controller.state.presets, isEmpty);
    });

    test('reports catalog failures and retries the same provider', () async {
      var attempts = 0;
      final retryResult = Completer<AgentConversationModeCatalog>();
      final controller = AgentConversationModeController();
      addTearDown(controller.dispose);
      final port = _FakeModeCatalogPort(() {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('temporary failure');
        }
        return retryResult.future;
      });

      await controller.loadCatalog(providerId: 'codex', port: port);

      expect(controller.state.status, AgentConversationModeLoadStatus.error);
      expect(controller.state.errorMessage, isNotEmpty);

      final retry = controller.retryCatalog();
      expect(controller.state.status, AgentConversationModeLoadStatus.loading);
      retryResult.complete(_catalog());
      await retry;

      expect(controller.state.status, AgentConversationModeLoadStatus.ready);
      expect(port.callCount, 2);
    });

    test('drops an old provider catalog result after a fast switch', () async {
      final providerAResult = Completer<AgentConversationModeCatalog>();
      final controller = AgentConversationModeController();
      addTearDown(controller.dispose);

      final providerALoad = controller.loadCatalog(
        providerId: 'provider-a',
        port: _FakeModeCatalogPort(() => providerAResult.future),
      );
      await controller.loadCatalog(
        providerId: 'provider-b',
        port: _FakeModeCatalogPort(
          () async => AgentConversationModeCatalog(
            presets: const <AgentConversationModePreset>[
              AgentConversationModePreset(
                id: AgentConversationModeId.defaultMode,
                displayName: 'Default B',
              ),
              AgentConversationModePreset(
                id: AgentConversationModeId.plan,
                displayName: 'Plan B',
                suggestedReasoningEffort: 'medium',
              ),
            ],
          ),
        ),
      );
      providerAResult.complete(_catalog());
      await providerALoad;

      expect(
        controller.state.presets.map((preset) => preset.displayName),
        <String>['Default B', 'Plan B'],
      );
    });

    test('drops an old retry result after switching providers', () async {
      var providerAAttempts = 0;
      final providerARetryResult = Completer<AgentConversationModeCatalog>();
      final controller = AgentConversationModeController();
      addTearDown(controller.dispose);
      final providerAPort = _FakeModeCatalogPort(() {
        providerAAttempts += 1;
        if (providerAAttempts == 1) {
          throw StateError('provider A is temporarily unavailable');
        }
        return providerARetryResult.future;
      });

      await controller.loadCatalog(
        providerId: 'provider-a',
        port: providerAPort,
      );
      final providerARetry = controller.retryCatalog();
      expect(controller.state.status, AgentConversationModeLoadStatus.loading);

      await controller.loadCatalog(
        providerId: 'provider-b',
        port: _FakeModeCatalogPort(
          () async => AgentConversationModeCatalog(
            presets: const <AgentConversationModePreset>[
              AgentConversationModePreset(
                id: AgentConversationModeId.defaultMode,
                displayName: 'Default B',
              ),
              AgentConversationModePreset(
                id: AgentConversationModeId.plan,
                displayName: 'Plan B',
                suggestedReasoningEffort: 'medium',
              ),
            ],
          ),
        ),
      );
      providerARetryResult.complete(_catalog());
      await providerARetry;

      expect(providerAPort.callCount, 2);
      expect(
        controller.state.presets.map((preset) => preset.displayName),
        <String>['Default B', 'Plan B'],
      );
    });

    test('does not notify when a stale load completes after dispose', () async {
      final loadResult = Completer<AgentConversationModeCatalog>();
      final controller = AgentConversationModeController();
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      final load = controller.loadCatalog(
        providerId: 'codex',
        port: _FakeModeCatalogPort(() => loadResult.future),
      );
      expect(notifications, 1);

      controller.dispose();
      loadResult.complete(_catalog());
      await load;

      expect(notifications, 1);
    });
  });

  group('AgentConversationModeController thread state', () {
    late AgentConversationModeController controller;

    setUp(() async {
      controller = AgentConversationModeController();
      await controller.loadCatalog(
        providerId: 'codex',
        port: _FakeModeCatalogPort(() async => _catalog()),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('binds new and restored threads without persisting a preference', () {
      controller.bindThread(threadId: 'new-thread');

      expect(
        controller.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
      expect(controller.state.draftMode, AgentConversationModeId.defaultMode);

      controller.bindThread(
        threadId: 'restored-thread',
        historyMode: AgentConversationModeId.plan,
      );

      expect(controller.state.confirmedMode, AgentConversationModeId.plan);
      expect(controller.state.draftMode, AgentConversationModeId.plan);
      expect(controller.state.pendingTurnMode, isNull);
    });

    test('preserves an unknown history mode as read-only state', () {
      final unknown = AgentConversationModeId.fromRaw('future-mode');
      controller.bindThread(threadId: 'thread-a', historyMode: unknown);

      controller.selectMode(unknown);
      final snapshot = controller.snapshotForNewTurn(
        effectiveModelId: 'gpt-5.6',
        selectedReasoningEffort: 'high',
      );

      expect(controller.state.confirmedMode, unknown);
      expect(controller.state.draftMode, unknown);
      expect(snapshot.conversationMode, isNull);
      expect(controller.state.pendingTurnMode, isNull);
    });

    test('freezes Plan preset settings for each new turn', () {
      controller.bindThread(threadId: 'thread-a');
      controller.selectMode(AgentConversationModeId.plan);

      final first = controller.snapshotForNewTurn(
        effectiveModelId: 'gpt-5.5',
        selectedReasoningEffort: 'xhigh',
      );
      final firstSelection = first.conversationMode!;
      controller.markTurnFailed(
        threadId: 'thread-a',
        selection: firstSelection,
      );
      final second = controller.snapshotForNewTurn(
        effectiveModelId: 'gpt-5.6',
        selectedReasoningEffort: 'low',
      );

      expect(firstSelection.modeId, AgentConversationModeId.plan);
      expect(firstSelection.effectiveModelId, 'gpt-5.5');
      expect(firstSelection.effectiveReasoningEffort, 'medium');
      expect(second.conversationMode!.effectiveModelId, 'gpt-5.6');
      expect(second.conversationMode!.effectiveReasoningEffort, 'medium');
      expect(firstSelection.effectiveModelId, 'gpt-5.5');
    });

    test('marks active-turn selections as applying to the next turn', () {
      controller.setTurnRunning(true);
      controller.selectMode(AgentConversationModeId.plan);

      expect(controller.state.appliesToNextTurn, isTrue);
      expect(
        controller.state.confirmedMode,
        isNot(AgentConversationModeId.plan),
      );
      expect(controller.state.draftMode, AgentConversationModeId.plan);

      controller.setTurnRunning(false);
      expect(controller.state.appliesToNextTurn, isFalse);
    });

    test('failed sends clear only their own pending snapshot', () {
      controller.bindThread(threadId: 'thread-a');
      controller.selectMode(AgentConversationModeId.plan);
      final oldSelection = controller
          .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
          .conversationMode!;
      final currentSelection = controller
          .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
          .conversationMode!;

      controller.markTurnFailed(threadId: 'thread-a', selection: oldSelection);

      expect(controller.state.pendingTurnMode, same(currentSelection));

      controller.markTurnFailed(
        threadId: 'thread-a',
        selection: currentSelection,
      );
      expect(controller.state.pendingTurnMode, isNull);
      expect(controller.state.draftMode, AgentConversationModeId.plan);
      expect(
        controller.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
    });

    test(
      'accepted sends confirm their snapshot but preserve a newer draft',
      () {
        controller.bindThread(threadId: 'thread-a');
        controller.selectMode(AgentConversationModeId.plan);
        final selection = controller
            .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
            .conversationMode!;
        controller.selectMode(AgentConversationModeId.defaultMode);

        controller.markTurnAccepted(threadId: 'thread-a', selection: selection);

        expect(controller.state.confirmedMode, AgentConversationModeId.plan);
        expect(controller.state.draftMode, AgentConversationModeId.defaultMode);
        expect(controller.state.pendingTurnMode, isNull);
      },
    );

    test(
      'clearPendingTurn drops plan pending so late markTurnAccepted is a no-op',
      () {
        controller.bindThread(threadId: 'thread-a');
        controller.selectMode(AgentConversationModeId.plan);
        final selection = controller
            .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
            .conversationMode!;

        // 普通 server 更新只清与自身匹配的 pending，plan→default 会留下 pending。
        controller.applyServerMode(AgentConversationModeId.defaultMode);
        expect(
          controller.state.confirmedMode,
          AgentConversationModeId.defaultMode,
        );
        expect(controller.state.pendingTurnMode, same(selection));

        // 计划审批消费路径强制清 pending，并同步 draft。
        controller.applyServerMode(
          AgentConversationModeId.defaultMode,
          clearPendingTurn: true,
        );
        expect(
          controller.state.confirmedMode,
          AgentConversationModeId.defaultMode,
        );
        expect(controller.state.draftMode, AgentConversationModeId.defaultMode);
        expect(controller.state.pendingTurnMode, isNull);

        // Grok 阻塞 session/prompt 返回后的迟到确认不得写回 plan。
        controller.markTurnAccepted(threadId: 'thread-a', selection: selection);
        expect(
          controller.state.confirmedMode,
          AgentConversationModeId.defaultMode,
        );
        expect(controller.state.pendingTurnMode, isNull);
      },
    );

    test('settings are authoritative without replacing a newer user draft', () {
      controller.bindThread(threadId: 'thread-a');
      controller.selectMode(AgentConversationModeId.plan);
      final pending = controller
          .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
          .conversationMode!;
      controller.selectMode(AgentConversationModeId.defaultMode);

      controller.applyThreadSettings(
        AgentThreadSettingsUpdatedEvent(
          threadId: 'thread-a',
          collaborationMode: pending,
        ),
      );

      expect(controller.state.confirmedMode, AgentConversationModeId.plan);
      expect(controller.state.draftMode, AgentConversationModeId.defaultMode);
      expect(controller.state.pendingTurnMode, isNull);
    });

    test('settings override history when no newer draft exists', () {
      controller.bindThread(
        threadId: 'thread-a',
        historyMode: AgentConversationModeId.plan,
      );

      controller.applyThreadSettings(
        AgentThreadSettingsUpdatedEvent(
          threadId: 'thread-a',
          collaborationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.defaultMode,
            effectiveModelId: 'gpt-5.6',
            effectiveReasoningEffort: 'high',
          ),
        ),
      );

      expect(
        controller.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
      expect(controller.state.draftMode, AgentConversationModeId.defaultMode);
    });

    test(
      'an older same-mode setting does not clear a newer pending snapshot',
      () {
        controller.bindThread(threadId: 'thread-a');
        controller.selectMode(AgentConversationModeId.plan);
        final pending = controller
            .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
            .conversationMode!;

        controller.applyThreadSettings(
          AgentThreadSettingsUpdatedEvent(
            threadId: 'thread-a',
            collaborationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'gpt-5.5',
              effectiveReasoningEffort: 'medium',
            ),
          ),
        );

        expect(controller.state.confirmedMode, AgentConversationModeId.plan);
        expect(controller.state.pendingTurnMode, same(pending));
      },
    );

    test('drops settings and send callbacks from another thread', () {
      controller.bindThread(threadId: 'thread-a');
      controller.selectMode(AgentConversationModeId.plan);
      final oldSelection = controller
          .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
          .conversationMode!;
      controller.bindThread(threadId: 'thread-b');
      final currentSelection = controller
          .snapshotForNewTurn(effectiveModelId: 'gpt-5.6')
          .conversationMode!;

      controller.applyThreadSettings(
        AgentThreadSettingsUpdatedEvent(
          threadId: 'thread-a',
          collaborationMode: oldSelection,
        ),
      );
      controller.markTurnAccepted(
        threadId: 'thread-a',
        selection: oldSelection,
      );
      controller.markTurnFailed(threadId: 'thread-a', selection: oldSelection);

      expect(
        controller.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
      expect(controller.state.pendingTurnMode, same(currentSelection));
    });

    test('notifies listeners only for observable state changes', () {
      controller.bindThread(threadId: 'thread-a');
      var notifications = 0;
      controller.addListener(() => notifications += 1);

      controller.selectMode(AgentConversationModeId.defaultMode);
      controller.setTurnRunning(false);
      controller.applyThreadSettings(
        AgentThreadSettingsUpdatedEvent(
          threadId: 'another-thread',
          collaborationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.plan,
            effectiveModelId: 'gpt-5.6',
          ),
        ),
      );

      expect(notifications, 0);
    });
  });
}

const AgentConversationModePreset _defaultPreset = AgentConversationModePreset(
  id: AgentConversationModeId.defaultMode,
  displayName: 'Default',
);

const AgentConversationModePreset _planPreset = AgentConversationModePreset(
  id: AgentConversationModeId.plan,
  displayName: 'Plan',
  suggestedReasoningEffort: 'medium',
);

AgentConversationModeCatalog _catalog() => AgentConversationModeCatalog(
  presets: const <AgentConversationModePreset>[_defaultPreset, _planPreset],
);

final class _FakeModeCatalogPort implements AgentConversationModeCatalogPort {
  _FakeModeCatalogPort(this.load);

  final Future<AgentConversationModeCatalog> Function() load;
  int callCount = 0;

  @override
  Future<AgentConversationModeCatalog> listConversationModes() {
    callCount += 1;
    return load();
  }
}

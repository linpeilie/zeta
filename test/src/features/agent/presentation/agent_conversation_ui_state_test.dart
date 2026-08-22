import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_ui_state.dart';
import 'agent_conversation_ui_state_fixtures.dart';

void main() {
  group('typed Agent conversation UI state', () {
    test('header uses structural token equality and stable hashCode', () {
      final first = agentHeaderStateFixture(
        tokenUsage: const AgentTokenUsage(totalTokens: 42),
      );
      final second = agentHeaderStateFixture(
        tokenUsage: const AgentTokenUsage(totalTokens: 42),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(agentHeaderStateFixture(title: 'Other'), isNot(first));
    });

    test('composer snapshots collections and compares nested model state', () {
      final modes = <AgentConversationModePreset>[
        const AgentConversationModePreset(
          id: AgentConversationModeId.defaultMode,
          displayName: 'Default',
        ),
      ];
      final configs = <AgentSessionConfigOption>[
        const AgentSessionConfigOption(
          id: 'mode',
          name: 'Mode',
          kind: AgentSessionConfigOptionKind.select,
          values: <AgentSessionConfigValue>[
            AgentSessionConfigValue(id: 'default', label: 'Default'),
          ],
        ),
      ];
      final first = agentComposerStateFixture(
        conversationModes: modes,
        sessionConfigOptions: configs,
      );
      final second = agentComposerStateFixture(
        conversationModes: List<AgentConversationModePreset>.of(modes),
        sessionConfigOptions: List<AgentSessionConfigOption>.of(configs),
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(
        () => first.conversationModeOptions.add(modes.single),
        throwsUnsupportedError,
      );
      expect(() => first.sessionConfigOptions.clear(), throwsUnsupportedError);
    });

    test('pending and expansion collections are immutable and structural', () {
      final amendment = <String>['git status'];
      final request = AgentPermissionRequest(
        id: 'permission-1',
        title: 'Run',
        kind: AgentPermissionKind.commandExecution,
        proposedExecpolicyAmendment: amendment,
      );
      final first = agentPendingInteractionStateFixture(
        permissions: <AgentPermissionRequest>[request],
      );
      amendment.add('git diff');
      final second = agentPendingInteractionStateFixture(
        permissions: <AgentPermissionRequest>[
          AgentPermissionRequest(
            id: 'permission-1',
            title: 'Run',
            kind: AgentPermissionKind.commandExecution,
            proposedExecpolicyAmendment: const <String>['git status'],
          ),
        ],
      );
      final expansion = AgentExpansionState(
        toolCallIds: const <String>['tool-1'],
        planMessageIds: const <String>[],
        activePlanTurnIds: const <String>[],
        commandGroupIds: const <String>['group-1'],
        fileEditItemIds: const <String>[],
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(first.permissions.single.proposedExecpolicyAmendment, <String>[
        'git status',
      ]);
      expect(() => first.permissions.clear(), throwsUnsupportedError);
      expect(expansion.isToolCallExpanded('tool-1'), isTrue);
      expect(() => expansion.toolCallIds.add('tool-2'), throwsUnsupportedError);
      expect(
        expansion,
        AgentExpansionState(
          toolCallIds: const <String>['tool-1'],
          planMessageIds: const <String>[],
          activePlanTurnIds: const <String>[],
          commandGroupIds: const <String>['group-1'],
          fileEditItemIds: const <String>[],
        ),
      );
    });

    test('history equality uses immutable turn snapshots and revisions', () {
      final entries = <AgentTimelineEntry>[
        AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'message-1',
            role: AgentMessageRole.agent,
            text: 'hello',
          ),
        ),
      ];
      final first = agentConversationHistoryStateFixture(
        entries: entries,
        contentRevision: 1,
      );
      final second = agentConversationHistoryStateFixture(
        entries: List<AgentTimelineEntry>.of(entries),
        contentRevision: 1,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
      expect(() => first.visibleTurns.clear(), throwsUnsupportedError);
      expect(
        agentConversationHistoryStateFixture(
          entries: entries,
          contentRevision: 2,
        ),
        isNot(first),
      );
    });

    test('thread snapshot equality remains structural', () {
      const first = AgentConversationThreadSnapshot(
        sessionId: 'thread-1',
        providerId: 'provider',
        threadTitle: 'Thread',
        isTurnRunning: true,
        runtimeStatus: AgentThreadRuntimeStatus.active,
        waitingOnApproval: false,
        waitingOnUserInput: true,
      );
      const second = AgentConversationThreadSnapshot(
        sessionId: 'thread-1',
        providerId: 'provider',
        threadTitle: 'Thread',
        isTurnRunning: true,
        runtimeStatus: AgentThreadRuntimeStatus.active,
        waitingOnApproval: false,
        waitingOnUserInput: true,
      );

      expect(first, second);
      expect(first.hashCode, second.hashCode);
    });
  });

  group('AgentConversationUiStateStore publish boundary', () {
    late AgentConversationTimelineStore timeline;
    late AgentHeaderState header;
    late AgentComposerState composer;
    late AgentPendingInteractionState pending;
    late AgentExpansionState expansion;
    late AgentConversationHistoryState history;
    late AgentConversationUiStateStore store;
    var disposed = false;

    setUp(() {
      timeline = AgentConversationTimelineStore();
      header = agentHeaderStateFixture();
      composer = agentComposerStateFixture();
      pending = agentPendingInteractionStateFixture();
      expansion = AgentExpansionState(
        toolCallIds: const <String>[],
        planMessageIds: const <String>[],
        activePlanTurnIds: const <String>[],
        commandGroupIds: const <String>[],
        fileEditItemIds: const <String>[],
      );
      history = agentConversationHistoryStateFixture();
      disposed = false;
      store = AgentConversationUiStateStore(
        timeline: timeline,
        buildHeaderState: () => header,
        buildComposerState: () => composer,
        buildPendingInteractionState: () => pending,
        buildExpansionState: () => expansion,
        buildHistoryState: () => history,
        isDisposed: () => disposed,
      );
    });

    tearDown(() {
      store.dispose();
      timeline.dispose();
    });

    test(
      'equal state does not notify and one slice does not notify others',
      () {
        var headerNotifications = 0;
        var composerNotifications = 0;
        var pendingNotifications = 0;
        var expansionNotifications = 0;
        var historyNotifications = 0;
        store.header.addListener(() => headerNotifications += 1);
        store.composer.addListener(() => composerNotifications += 1);
        store.pendingInteractions.addListener(() => pendingNotifications += 1);
        store.expansion.addListener(() => expansionNotifications += 1);
        store.history.addListener(() => historyNotifications += 1);

        store.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{
              AgentUiRegion.header,
              AgentUiRegion.composer,
              AgentUiRegion.pendingInteraction,
              AgentUiRegion.expansion,
              AgentUiRegion.history,
            },
            urgency: AgentUiUpdateUrgency.immediate,
          ),
        );
        expect(headerNotifications, 0);
        expect(composerNotifications, 0);
        expect(pendingNotifications, 0);
        expect(expansionNotifications, 0);
        expect(historyNotifications, 0);

        header = agentHeaderStateFixture(title: 'Renamed');
        store.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
            urgency: AgentUiUpdateUrgency.immediate,
          ),
        );

        expect(headerNotifications, 1);
        expect(composerNotifications, 0);
        expect(pendingNotifications, 0);
        expect(expansionNotifications, 0);
        expect(historyNotifications, 0);
        expect(store.header.value.title, 'Renamed');
      },
    );

    test('publishes live binding, live mutation, and effect exactly once', () {
      timeline.startPendingLiveTurn();
      var bindingNotifications = 0;
      var liveNotifications = 0;
      var autoScrollEffects = 0;
      timeline.liveTurnListenable.addListener(() {
        bindingNotifications += 1;
        timeline.liveTurnState?.addListener(() => liveNotifications += 1);
      });
      final subscription = store.effects.listen((effect) {
        if (effect is AgentRequestAutoScroll) {
          autoScrollEffects += 1;
        }
      });
      addTearDown(subscription.cancel);

      store.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurnBinding,
            AgentUiRegion.liveTurn,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[
            AgentRequestAutoScroll(),
            AgentRequestAutoScroll(),
          ],
        ),
      );

      expect(bindingNotifications, 1);
      expect(liveNotifications, 1);
      expect(autoScrollEffects, 1);
      expect(store.diagnostics.publishCount, 1);
    });

    test('disposed owner rejects scheduler callbacks', () {
      disposed = true;
      header = agentHeaderStateFixture(title: 'Ignored');

      store.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );

      expect(store.header.value.title, 'Thread');
      expect(store.diagnostics.publishCount, 0);
    });
  });
}

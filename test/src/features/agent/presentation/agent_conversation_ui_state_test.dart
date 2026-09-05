import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
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

  group('SliceStore UI update ingress', () {
    late _FakeRegionSource regions;
    late AgentConversationSliceStore store;

    setUp(() {
      regions = _FakeRegionSource();
      store = AgentConversationSliceStore.connected(
        regions: regions,
        commands: const _UnusedCommandPort(),
      );
    });

    tearDown(() => store.dispose());

    test(
      'equal state does not notify and one region does not notify others',
      () {
        var notifications = 0;
        store.addListener(() => notifications += 1);

        regions.emit(
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
        expect(notifications, 0);

        regions.header = agentHeaderStateFixture(title: 'Renamed');
        regions.emit(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
            urgency: AgentUiUpdateUrgency.immediate,
          ),
        );

        expect(notifications, 1);
        expect(store.state.header.title, 'Renamed');
        expect(store.state.composer, regions.composer);
      },
    );

    test('live-only request does not mutate slice regions', () {
      var notifications = 0;
      store.addListener(() => notifications += 1);

      regions.emit(
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

      expect(notifications, 0);
      expect(store.diagnostics.publishCount, 0);
    });

    test('disposed store rejects later UI updates', () {
      store.dispose();
      regions.header = agentHeaderStateFixture(title: 'Ignored');
      regions.emit(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );

      expect(store.state.header.title, 'Thread');
      expect(store.diagnostics.publishCount, 0);
    });
  });
}

final class _FakeRegionSource implements AgentConversationRegionSource {
  final List<void Function(AgentUiUpdateRequest)> _listeners =
      <void Function(AgentUiUpdateRequest)>[];

  AgentHeaderState header = agentHeaderStateFixture();
  AgentComposerState composer = agentComposerStateFixture();
  AgentPendingInteractionState pending = agentPendingInteractionStateFixture();
  AgentExpansionState expansion = AgentExpansionState(
    toolCallIds: const <String>[],
    planMessageIds: const <String>[],
    activePlanTurnIds: const <String>[],
    commandGroupIds: const <String>[],
    fileEditItemIds: const <String>[],
  );
  AgentConversationHistoryState history =
      agentConversationHistoryStateFixture();

  @override
  AgentHeaderState get headerState => header;

  @override
  AgentComposerState get composerState => composer;

  @override
  AgentPendingInteractionState get pendingInteractionState => pending;

  @override
  AgentExpansionState get expansionState => expansion;

  @override
  AgentConversationHistoryState get historyState => history;

  @override
  void addUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  ) {
    _listeners.add(listener);
  }

  @override
  void removeUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  ) {
    _listeners.remove(listener);
  }

  @override
  AgentConversationCommandScope currentCommandScope() {
    return const AgentConversationCommandScope(
      bindingKey: AgentConversationBindingKey.thread(
        providerId: 'codex',
        threadId: 'thread-1',
      ),
      runtimeId: 'runtime-1',
      connectionEpoch: 1,
      listenerGeneration: 1,
      threadId: 'thread-1',
    );
  }

  void emit(AgentUiUpdateRequest request) {
    for (final listener in List<void Function(AgentUiUpdateRequest)>.of(
      _listeners,
    )) {
      listener(request);
    }
  }
}

final class _UnusedCommandPort implements AgentConversationCommandPort {
  const _UnusedCommandPort();

  static const AgentCommandOutcome _ignored = AgentCommandOutcome.ignored(
    AgentCommandIgnoreReason.emptyInput,
  );

  @override
  void toggleToolCall(String toolCallId) {}

  @override
  void togglePlanMessage(String messageId) {}

  @override
  void toggleActivePlan(String turnId) {}

  @override
  void toggleCommandGroup(String commandGroupId) {}

  @override
  void toggleFileEditItem(String fileEditItemId) {}

  @override
  void dismissPlanExecution(AgentPlanExecutionRequest request) {}

  @override
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const <String>[],
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  }) async => _ignored;

  @override
  Future<AgentCommandOutcome> cancelActiveTurn() async => _ignored;

  @override
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(
    String newText,
  ) async => _ignored;

  @override
  Future<AgentCommandOutcome> retryOpenThread() async => _ignored;

  @override
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) async => _ignored;

  @override
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) async => _ignored;

  @override
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  }) async => _ignored;

  @override
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  }) async => _ignored;

  @override
  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  ) async => _ignored;

  @override
  Future<AgentCommandOutcome> approveGuardianDeniedAction() async => _ignored;

  @override
  Future<AgentSession?> forkCurrentThread() async => null;

  @override
  Future<AgentCommandOutcome> renameCurrentThread(String name) async =>
      _ignored;

  @override
  Future<AgentCommandOutcome> archiveCurrentThread() async => _ignored;

  @override
  Future<AgentCommandOutcome> compactCurrentThread() async => _ignored;

  @override
  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false}) async =>
      _ignored;

  @override
  Future<AgentCommandOutcome> ensureSkillsCatalog() async => _ignored;

  @override
  Future<AgentCommandOutcome> retryConversationModes() async => _ignored;
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentConversationTimelineStore', () {
    test('pages historical turns into a visible window of 3', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            for (var index = 1; index <= 5; index += 1)
              AgentHistoryTurn(
                id: 'turn-$index',
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'user-$index',
                    role: AgentMessageRole.user,
                    text: 'Request $index',
                  ),
                ],
              ),
          ],
        ),
        _thread(),
      );

      expect(store.hasOlderTurns, isTrue);
      expect(
        store.visibleHistoryTurns.map((turn) => turn.id).toList(),
        <String>['turn-3', 'turn-4', 'turn-5'],
      );
      expect(store.conversationTurns.map((turn) => turn.id).toList(), <String>[
        'turn-3',
        'turn-4',
        'turn-5',
      ]);

      expect(store.loadOlderTurns(), isTrue);
      expect(store.hasOlderTurns, isFalse);
      expect(store.conversationTurns.map((turn) => turn.id).toList(), <String>[
        'turn-1',
        'turn-2',
        'turn-3',
        'turn-4',
        'turn-5',
      ]);
    });

    test('stores session total and per-turn token deltas', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-a',
                  role: AgentMessageRole.user,
                  text: 'Existing request',
                ),
              ],
              // 历史里的 total 是会话累计；首个 turn 的增量等于累计本身。
              tokenUsage: AgentTokenUsage(
                inputTokens: 2000,
                cachedInputTokens: 500,
                outputTokens: 330,
                totalTokens: 2250,
                lastInputTokens: 800,
                lastCachedInputTokens: 150,
                lastOutputTokens: 240,
                lastTotalTokens: 1040,
                modelContextWindow: 4000,
              ),
            ),
          ],
        ),
        _thread(),
      );

      expect(store.currentThreadTokenUsage, isNotNull);
      expect(store.currentThreadTokenUsage!.totalTokens, 2250);
      expect(store.conversationTurns.single.tokenUsage!.totalTokens, 2250);

      store.startPendingLiveTurn();
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'user-live',
          role: AgentMessageRole.user,
          text: 'hello',
        ),
      );
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-live', sessionId: 'thread-1'),
      );
      store.updateTurnTokenUsage(
        const AgentTokenUsageEvent(
          sessionId: 'thread-1',
          turnId: 'turn-live',
          // Codex 上报的是整个会话累计，不是本 turn 成本。
          tokenUsage: AgentTokenUsage(
            inputTokens: 3000,
            cachedInputTokens: 700,
            outputTokens: 680,
            totalTokens: 3550,
            lastInputTokens: 920,
            lastCachedInputTokens: 180,
            lastOutputTokens: 320,
            lastTotalTokens: 1240,
            modelContextWindow: 2000,
          ),
        ),
      );
      store.syncLiveTurnBinding();

      expect(store.liveTurnState, isNotNull);
      expect(store.currentTurnTokenUsage, isNotNull);
      expect(store.currentTurnTokenUsage!.inputTokens, 1000);
      expect(store.currentTurnTokenUsage!.cachedInputTokens, 200);
      expect(store.currentTurnTokenUsage!.outputTokens, 350);
      expect(store.currentTurnTokenUsage!.totalTokens, 1300);
      expect(store.currentThreadTokenUsage, isNotNull);
      expect(store.currentThreadTokenUsage!.inputTokens, 3000);
      expect(store.currentThreadTokenUsage!.cachedInputTokens, 700);
      expect(store.currentThreadTokenUsage!.outputTokens, 680);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadLastTokenUsage, isNotNull);
      expect(store.currentThreadLastTokenUsage!.inputTokens, 920);
      expect(store.currentThreadLastTokenUsage!.cachedInputTokens, 180);
      expect(store.currentThreadLastTokenUsage!.outputTokens, 320);
      expect(store.currentThreadLastTokenUsage!.totalTokens, 1240);
      expect(store.currentThreadLastTokenUsage!.modelContextWindow, 2000);

      store.completeLiveTurnGroup('turn-live');
      store.syncLiveTurnBinding();

      expect(store.liveTurnState, isNull);
      expect(store.currentTurnTokenUsage, isNull);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadLastTokenUsage!.totalTokens, 1240);
    });

    test('attaches model config from history and live pending turn', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-history',
              model: 'gpt-5.5',
              status: AgentHistoryTurnStatus.completed,
              duration: Duration(seconds: 12),
              raw: <String, Object?>{
                'turnContext': <String, Object?>{
                  'effort': 'medium',
                  'serviceTier': 'priority',
                },
              },
            ),
          ],
        ),
        _thread(),
      );

      final historyConfig = store.conversationTurns.single.modelConfig;
      expect(historyConfig, isNotNull);
      expect(historyConfig!.modelId, 'gpt-5.5');
      expect(historyConfig.reasoningEffort, 'medium');
      expect(historyConfig.fastEnabled, isTrue);

      store.startPendingLiveTurn(
        modelConfig: const AgentTurnModelConfig(
          modelId: 'GPT-5.5',
          reasoningEffort: 'high',
          fastEnabled: true,
        ),
      );
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-live', sessionId: 'thread-1'),
      );
      store.completeLiveTurnGroup('turn-live');
      store.syncLiveTurnBinding();

      final liveGroup = store.conversationTurns.firstWhere(
        (turn) => turn.id == 'turn-live',
      );
      expect(liveGroup.modelConfig?.modelId, 'GPT-5.5');
      expect(liveGroup.modelConfig?.reasoningEffort, 'high');
      expect(liveGroup.modelConfig?.fastEnabled, isTrue);
    });

    test('stamps tool startedAt, tracks activity phase, freezes duration', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      expect(store.currentActivity.phase, AgentTurnActivityPhase.starting);
      expect(store.currentTurnStartedAt, isNotNull);
      expect(store.takeActivityDirty(), isTrue);

      store.appendReasoningDelta(
        const AgentReasoningDeltaEvent(
          itemId: 'think-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'planning',
        ),
      );
      expect(store.currentActivity.phase, AgentTurnActivityPhase.thinking);
      final think = store.toolCalls.singleWhere((t) => t.id == 'think-1');
      expect(think.startedAt, isNotNull);
      expect(think.duration, isNull);
      expect(store.takeActivityDirty(), isTrue);

      store.upsertToolCall(
        const AgentToolCall(
          id: 'cmd-1',
          title: 'git status',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.inProgress,
        ),
      );
      expect(store.currentActivity.phase, AgentTurnActivityPhase.toolRunning);
      expect(store.currentActivity.label, 'git status');
      final cmd = store.toolCalls.singleWhere((t) => t.id == 'cmd-1');
      expect(cmd.startedAt, isNotNull);
      final cmdStartedAt = cmd.startedAt!;

      store.upsertToolCall(
        const AgentToolCall(
          id: 'cmd-1',
          title: 'git status',
          kind: AgentToolKind.execute,
          status: AgentToolStatus.completed,
          content: 'ok',
        ),
      );
      final completedCmd = store.toolCalls.singleWhere((t) => t.id == 'cmd-1');
      expect(completedCmd.startedAt, cmdStartedAt);
      expect(completedCmd.duration, isNotNull);
      expect(completedCmd.duration!.inMilliseconds, greaterThanOrEqualTo(0));

      final turnId = store.selectedRunningTurnId!;
      store.completeLiveTurnGroup(turnId);
      expect(store.currentActivity.phase, AgentTurnActivityPhase.idle);
      expect(store.isTurnRunning, isFalse);
      final frozenThink = store.toolCalls.singleWhere((t) => t.id == 'think-1');
      expect(frozenThink.duration, isNotNull);
    });

    test('converts cumulative history token usage into per-turn deltas', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-a',
                  role: AgentMessageRole.user,
                  text: 'First',
                ),
              ],
              tokenUsage: AgentTokenUsage(
                inputTokens: 2000,
                cachedInputTokens: 500,
                outputTokens: 330,
                totalTokens: 2250,
              ),
            ),
            AgentHistoryTurn(
              id: 'turn-b',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-b',
                  role: AgentMessageRole.user,
                  text: 'Second',
                ),
              ],
              tokenUsage: AgentTokenUsage(
                inputTokens: 3000,
                cachedInputTokens: 700,
                outputTokens: 680,
                totalTokens: 3550,
              ),
            ),
          ],
        ),
        _thread(),
      );

      final turns = store.conversationTurns;
      expect(turns, hasLength(2));
      expect(turns[0].tokenUsage!.totalTokens, 2250);
      expect(turns[0].tokenUsage!.inputTokens, 2000);
      expect(turns[1].tokenUsage!.totalTokens, 1300);
      expect(turns[1].tokenUsage!.inputTokens, 1000);
      expect(turns[1].tokenUsage!.cachedInputTokens, 200);
      expect(turns[1].tokenUsage!.outputTokens, 350);
      expect(store.currentThreadTokenUsage!.totalTokens, 3550);
      expect(store.currentThreadTokenUsage!.inputTokens, 3000);
    });

    test('keeps Grok per-turn absolute usage without cumulative delta', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-a',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-a',
                  role: AgentMessageRole.user,
                  text: 'First',
                ),
              ],
              duration: Duration(seconds: 12),
              tokenUsage: AgentTokenUsage(
                inputTokens: 500,
                outputTokens: 50,
                totalTokens: 550,
              ),
              tokenUsageIsSessionCumulative: false,
            ),
            AgentHistoryTurn(
              id: 'turn-b',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-b',
                  role: AgentMessageRole.user,
                  text: 'Second',
                ),
              ],
              duration: Duration(milliseconds: 4500),
              tokenUsage: AgentTokenUsage(
                inputTokens: 200,
                outputTokens: 30,
                totalTokens: 230,
              ),
              tokenUsageIsSessionCumulative: false,
            ),
          ],
        ),
        _thread(),
      );

      final turns = store.conversationTurns;
      expect(turns, hasLength(2));
      // 不得相对上一 turn 做差分（230 不能被 550 减成 0）。
      expect(turns[0].tokenUsage!.totalTokens, 550);
      expect(turns[1].tokenUsage!.totalTokens, 230);
      expect(turns[0].duration, const Duration(seconds: 12));
      expect(turns[1].duration, const Duration(milliseconds: 4500));
      expect(store.currentThreadTokenUsage!.totalTokens, 780);
    });

    test(
      'applies turn-absolute usage after complete without demoting history',
      () {
        final store = AgentConversationTimelineStore();
        addTearDown(store.dispose);

        store.startPendingLiveTurn();
        store.beginLiveTurnGroup(
          const AgentTurn(id: 'turn-live', sessionId: 'thread-1'),
        );
        store.addConversationMessage(
          const AgentConversationMessage(
            id: 'user-1',
            role: AgentMessageRole.user,
            text: 'hello',
          ),
        );
        store.completeLiveTurnGroup(
          'turn-live',
          duration: const Duration(seconds: 3),
        );
        store.syncLiveTurnBinding();
        expect(store.liveTurnState, isNull);
        expect(store.isHistoryTurnId('turn-live'), isTrue);

        store.updateTurnTokenUsage(
          const AgentTokenUsageEvent(
            sessionId: 'thread-1',
            turnId: 'turn-live',
            isSessionCumulative: false,
            tokenUsage: AgentTokenUsage(
              inputTokens: 80,
              outputTokens: 20,
              totalTokens: 100,
            ),
          ),
        );

        final completed = store.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-live',
        );
        expect(completed.tokenUsage!.totalTokens, 100);
        expect(completed.duration, const Duration(seconds: 3));
        expect(store.isHistoryTurnId('turn-live'), isTrue);
        expect(store.isLiveTurnId('turn-live'), isFalse);
        expect(store.currentThreadTokenUsage!.totalTokens, 100);
      },
    );

    test('removePermissionRequest drops pending card and timeline entry', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.addPermissionRequest(
        const AgentPermissionRequest(
          id: 'approval-1',
          title: 'Run command',
          kind: AgentPermissionKind.commandExecution,
          command: 'flutter test',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );

      expect(store.permissionRequests, hasLength(1));
      expect(
        store.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
        hasLength(1),
      );

      store.removePermissionRequest('approval-1');

      expect(store.permissionRequests, isEmpty);
      expect(
        store.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
        isEmpty,
      );
    });

    test('appends MCP tool progress onto existing tool card content', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP · docs · search',
          kind: AgentToolKind.search,
          status: AgentToolStatus.inProgress,
          content: 'query: zeta',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP tool',
          kind: AgentToolKind.other,
          status: AgentToolStatus.inProgress,
          content: 'Fetching resources…',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          raw: <String, Object?>{'_progressAppend': true},
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'mcp-1',
          title: 'MCP tool',
          kind: AgentToolKind.other,
          status: AgentToolStatus.inProgress,
          content: 'Parsing results…',
          sessionId: 'thread-1',
          turnId: 'turn-1',
          raw: <String, Object?>{'_progressAppend': true},
        ),
      );

      final tool = store.toolCalls.single;
      expect(tool.title, 'MCP · docs · search');
      expect(tool.kind, AgentToolKind.search);
      expect(
        tool.content,
        'query: zeta\nFetching resources…\nParsing results…',
      );
      expect(store.isToolCallExpanded('mcp-1'), isTrue);
    });

    test(
      'dismisses welcome message once real conversation content arrives',
      () {
        final store = AgentConversationTimelineStore();
        addTearDown(store.dispose);

        expect(
          store.messages.map((message) => message.id),
          contains(AgentConversationTimelineStore.welcomeMessage.id),
        );

        store.startPendingLiveTurn();
        store.addConversationMessage(
          const AgentConversationMessage(
            id: 'user-1',
            role: AgentMessageRole.user,
            text: 'hello',
          ),
        );
        store.syncLiveTurnBinding();

        expect(
          store.messages.map((message) => message.id),
          isNot(contains(AgentConversationTimelineStore.welcomeMessage.id)),
        );
        expect(
          store.conversationTurns.map((turn) => turn.id).toList(),
          isNot(contains(AgentConversationTimelineStore.standbyTurnId)),
        );
        expect(store.conversationTurns, hasLength(1));
        expect(store.conversationTurns.single.isStandby, isFalse);
      },
    );

    test('replaces same-id timeline entries instead of duplicating them', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'error-same',
          role: AgentMessageRole.system,
          text: 'first',
        ),
      );
      store.addConversationMessage(
        const AgentConversationMessage(
          id: 'error-same',
          role: AgentMessageRole.system,
          text: 'second',
        ),
      );
      store.syncLiveTurnBinding();

      final errorEntries = store.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .where((entry) => entry.message.id == 'error-same')
          .toList();
      expect(errorEntries, hasLength(1));
      expect(errorEntries.single.message.text, 'second');
      expect(store.liveTurnState!.entries, hasLength(1));
    });

    test('adds and removes independent plan approval entries', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);
      const request = AgentPlanApprovalRequest(
        id: 'plan-1',
        title: 'Review plan',
        markdown: '1. Inspect',
      );

      store.addPlanApprovalRequest(request);
      expect(store.planApprovalRequests, <AgentPlanApprovalRequest>[request]);
      expect(
        store.timelineEntries.whereType<AgentPlanApprovalTimelineEntry>(),
        hasLength(1),
      );

      store.removePlanApprovalRequest(request.id);
      expect(store.planApprovalRequests, isEmpty);
      expect(
        store.timelineEntries.whereType<AgentPlanApprovalTimelineEntry>(),
        isEmpty,
      );
    });

    test('keeps concrete Grok metadata on status-only updates', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'call-abc-0',
          title: 'sessionUpdate',
          kind: AgentToolKind.search,
          status: AgentToolStatus.inProgress,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          rawInput: <String, Object?>{'pattern': 'sessionUpdate'},
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'call-abc-0',
          title: '操作',
          kind: AgentToolKind.other,
          status: AgentToolStatus.completed,
          content: 'found 42 matches',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );

      final tool = store.toolCalls.single;
      expect(tool.title, 'sessionUpdate');
      expect(tool.kind, AgentToolKind.search);
      expect(tool.rawInput['pattern'], 'sessionUpdate');
      expect(tool.content, 'found 42 matches');
    });

    test('appends deltas only when normalized entryId is identical', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );

      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-a',
          sourceMessageId: 'provider-message-a',
          delta: 'A',
          role: AgentMessageRole.agent,
          phase: AgentMessagePhase.commentary,
          status: AgentMessageStatus.streaming,
          turnId: 'turn-1',
        ),
      );
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-a',
          sourceMessageId: 'provider-message-a',
          delta: 'B',
          role: AgentMessageRole.agent,
          phase: AgentMessagePhase.commentary,
          status: AgentMessageStatus.streaming,
          turnId: 'turn-1',
        ),
      );

      final entries = _liveTimelineEntries(store);
      expect(entries, hasLength(1));
      final message = (entries.single as AgentMessageTimelineEntry).message;
      expect(message.id, 'message-a');
      expect(message.sourceMessageId, 'provider-message-a');
      expect(message.text, 'AB');
      expect(message.kind, AgentMessageKind.regular);
      expect(message.phase, AgentMessagePhase.commentary);
      expect(message.status, AgentMessageStatus.streaming);
    });

    test('keeps Message Tool Message for different normalized entryIds', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );

      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-seg1',
          sourceMessageId: 'provider-message-a',
          delta: 'Before tool.',
          role: AgentMessageRole.agent,
          turnId: 'turn-1',
        ),
      );
      store.upsertToolCall(
        const AgentToolCall(
          id: 'tool-1',
          title: 'Read file',
          kind: AgentToolKind.read,
          status: AgentToolStatus.pending,
          turnId: 'turn-1',
        ),
      );
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-seg2',
          sourceMessageId: 'provider-message-a',
          delta: 'After tool.',
          role: AgentMessageRole.agent,
          turnId: 'turn-1',
        ),
      );

      final entries = _liveTimelineEntries(store);
      expect(entries, hasLength(3));
      expect(
        (entries[0] as AgentMessageTimelineEntry).message.id,
        'message-seg1',
      );
      expect(entries[1], isA<AgentToolTimelineEntry>());
      expect(
        (entries[2] as AgentMessageTimelineEntry).message.id,
        'message-seg2',
      );
      expect(
        store.messages
            .where((message) => message.sourceMessageId == 'provider-message-a')
            .map((message) => message.text),
        <String>['Before tool.', 'After tool.'],
      );
    });

    test('keeps reused sourceMessageId isolated across turns', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-1', sessionId: 'thread-1'),
      );
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'turn-1-message-a',
          sourceMessageId: 'provider-message-a',
          delta: 'Turn one',
          role: AgentMessageRole.agent,
          turnId: 'turn-1',
        ),
      );
      store.completeLiveTurnGroup('turn-1');

      store.startPendingLiveTurn();
      store.beginLiveTurnGroup(
        const AgentTurn(id: 'turn-2', sessionId: 'thread-1'),
      );
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'turn-2-message-a',
          sourceMessageId: 'provider-message-a',
          delta: 'Turn two',
          role: AgentMessageRole.agent,
          turnId: 'turn-2',
        ),
      );

      final messages = store.messages
          .where((message) => message.sourceMessageId == 'provider-message-a')
          .toList();
      expect(messages.map((message) => message.id), <String>[
        'turn-1-message-a',
        'turn-2-message-a',
      ]);
      expect(messages.map((message) => message.text), <String>[
        'Turn one',
        'Turn two',
      ]);
    });

    test('updates restored history by the same normalized entryId', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.applyHistorySnapshot(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'history-message-a',
                  sourceMessageId: 'provider-message-a',
                  role: AgentMessageRole.agent,
                  text: 'partial',
                  kind: AgentMessageKind.plan,
                  status: AgentMessageStatus.streaming,
                ),
              ],
            ),
          ],
        ),
        _thread(),
      );
      store.updateMessage(
        const AgentMessageUpdatedEvent(
          messageId: 'history-message-a',
          kind: AgentMessageKind.plan,
          text: 'complete',
          status: AgentMessageStatus.completed,
        ),
      );

      final message = store.messages.single;
      expect(message.id, 'history-message-a');
      expect(message.sourceMessageId, 'provider-message-a');
      expect(message.kind, AgentMessageKind.plan);
      expect(message.text, 'complete');
      expect(message.status, AgentMessageStatus.completed);
    });

    test('completed snapshot only updates the same normalized entryId', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'message-a',
          sourceMessageId: 'provider-message-a',
          delta: 'partial',
          role: AgentMessageRole.agent,
          kind: AgentMessageKind.plan,
          phase: AgentMessagePhase.commentary,
          status: AgentMessageStatus.streaming,
          duration: Duration(seconds: 1),
          raw: <String, Object?>{'type': 'not-a-plan'},
        ),
      );
      store.updateMessage(
        const AgentMessageUpdatedEvent(
          messageId: 'message-a',
          kind: AgentMessageKind.plan,
          text: 'complete',
          phase: AgentMessagePhase.response,
          status: AgentMessageStatus.completed,
          duration: Duration(seconds: 2),
        ),
      );
      store.updateMessage(
        const AgentMessageUpdatedEvent(
          messageId: 'unknown-message',
          text: 'must not create a duplicate',
          status: AgentMessageStatus.completed,
        ),
      );

      final message = store.messages.singleWhere(
        (message) => message.id == 'message-a',
      );
      expect(message.sourceMessageId, 'provider-message-a');
      expect(message.kind, AgentMessageKind.plan);
      expect(message.text, 'complete');
      expect(message.phase, AgentMessagePhase.response);
      expect(message.status, AgentMessageStatus.completed);
      expect(message.duration, const Duration(seconds: 2));
      expect(
        store.messages.where((message) => message.id == 'unknown-message'),
        isEmpty,
      );
    });

    test('raw payload cannot control message kind', () {
      final store = AgentConversationTimelineStore();
      addTearDown(store.dispose);

      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'regular-message',
          delta: 'regular',
          role: AgentMessageRole.agent,
          raw: <String, Object?>{'type': 'plan'},
        ),
      );
      store.appendMessageDelta(
        const AgentMessageDeltaEvent(
          messageId: 'plan-message',
          delta: 'plan',
          role: AgentMessageRole.agent,
          kind: AgentMessageKind.plan,
          raw: <String, Object?>{'type': 'agentMessage'},
        ),
      );

      expect(
        store.messages
            .singleWhere((message) => message.id == 'regular-message')
            .kind,
        AgentMessageKind.regular,
      );
      expect(
        store.messages
            .singleWhere((message) => message.id == 'plan-message')
            .kind,
        AgentMessageKind.plan,
      );
    });
  });
}

/// 当前 live turn 条目；必要时同步 binding。
List<AgentTimelineEntry> _liveTimelineEntries(
  AgentConversationTimelineStore store,
) {
  store.syncLiveTurnBinding();
  final live = store.liveTurnState;
  if (live != null) {
    return List<AgentTimelineEntry>.from(live.entries);
  }
  return store.timelineEntries
      .where(
        (entry) =>
            entry is! AgentMessageTimelineEntry ||
            entry.message.id !=
                AgentConversationTimelineStore.welcomeMessage.id,
      )
      .toList();
}

AgentThreadSummary _thread() {
  return AgentThreadSummary(
    id: 'thread-1',
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: 'Thread one',
    sessionPath: '/repo/thread-1.jsonl',
    preview: 'Thread one',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

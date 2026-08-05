import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:logging/logging.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_model_catalog_repository.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';

import '../../../testing/agent_provider_stub_base.dart';
import '../../../testing/fake_agent_frame_scheduler.dart';

final List<FakeAgentFrameScheduler> _uiFrameSchedulers =
    <FakeAgentFrameScheduler>[];

void main() {
  setUp(_uiFrameSchedulers.clear);

  group('AgentConversationViewModel', () {
    test('uses New thread as the default header title', () {
      final viewModel = _createViewModel(_FakeAgentProvider());
      addTearDown(viewModel.dispose);

      expect(
        viewModel.currentThreadTitle,
        AgentConversationViewModel.defaultThreadTitle,
      );
      expect(viewModel.currentTurnTokenUsage, isNull);
      expect(viewModel.currentThreadTokenUsage, isNull);
      expect(viewModel.currentThreadLastTokenUsage, isNull);
    });

    test('loads history for a selected thread without resuming', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': _historySnapshot(
            threadId: 'thread-1',
            userText: 'What changed?',
            agentText: 'The provider layer changed.',
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());

      expect(provider.calls, <String>['read:thread-1']);
      expect(provider.readSessionPaths, <String>['/repo/thread-1.jsonl']);
      expect(provider.readProjectPaths, <String>['/repo']);
      expect(viewModel.status.state, AgentProviderConnectionState.ready);
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
      expect(viewModel.isTurnRunning, isFalse);
      expect(viewModel.canSubmitMessage, isTrue);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>['What changed?', 'The provider layer changed.']),
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentToolTimelineEntry>()
            .single
            .toolCall
            .title,
        'Run tests',
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentHistoryEventTimelineEntry>()
            .single
            .event
            .title,
        'Tool search',
      );
      expect(viewModel.currentThreadTitle, 'Thread one');
    });

    test(
      'switchThread hydrates model list without a prior loadModels call',
      () async {
        final provider = _FakeAgentProvider(
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
              ),
            ],
          ),
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'What changed?',
              agentText: 'The provider layer changed.',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        expect(viewModel.models, isEmpty);

        await viewModel.switchThread(_thread());

        expect(viewModel.models.map((model) => model.id), <String>['gpt-5.5']);
        expect(viewModel.modelConfigUiState.models, isNotEmpty);
        expect(viewModel.modelConfigUiState.isRefreshing, isFalse);
      },
    );

    test(
      'switchThread does not wait for stale event subscription cancellation',
      () async {
        final cancellationGate = Completer<void>();
        final provider = _FakeAgentProvider(
          eventCancellationGate: cancellationGate.future,
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'History remains available',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(() {
          if (!cancellationGate.isCompleted) {
            cancellationGate.complete();
          }
          viewModel.dispose();
        });
        await viewModel.loadModels();

        await viewModel
            .switchThread(_thread())
            .timeout(const Duration(seconds: 1));

        expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
        expect(
          viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
            (entry) => entry.message.text,
          ),
          contains('History remains available'),
        );
        expect(cancellationGate.isCompleted, isFalse);
      },
    );

    test(
      'uses provider session title after resuming a selected thread',
      () async {
        final provider = _FakeAgentProvider(
          resumeSessionTitle: 'Resolved title',
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await viewModel.sendMessage('hello');

        expect(provider.calls, <String>[
          'read:thread-1',
          'resume:thread-1',
          'send:thread-1',
        ]);
        expect(viewModel.currentThreadTitle, 'Resolved title');
      },
    );

    test('uses provider session title after starting a new thread', () async {
      final provider = _FakeAgentProvider(startSessionTitle: 'Started title');
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');

      expect(viewModel.currentThreadTitle, 'Started title');
      expect(provider.calls, contains('start'));
    });

    test(
      'sends an immutable Plan snapshot without changing model preference',
      () async {
        final modeController = AgentConversationModeController();
        addTearDown(modeController.dispose);
        final provider = _ModeFakeAgentProvider(
          availableModels: _conversationModeModels,
          emitSessionStartedDuringSend: true,
        );
        final viewModel = _createViewModel(
          provider,
          conversationModeController: modeController,
        );
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        expect(viewModel.canSelectConversationMode, isTrue);
        expect(
          viewModel.conversationModeOptions.map((preset) => preset.id),
          <AgentConversationModeId>[
            AgentConversationModeId.defaultMode,
            AgentConversationModeId.plan,
          ],
        );
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );
        expect(viewModel.selectedReasoningEffort, 'high');

        viewModel.selectConversationMode(AgentConversationModeId.plan);
        await viewModel.sendMessage('plan this change');

        final selection = provider.turnConfigurations.single.conversationMode!;
        expect(selection.modeId, AgentConversationModeId.plan);
        expect(selection.effectiveModelId, 'gpt-5.6');
        expect(selection.effectiveReasoningEffort, 'medium');
        expect(provider.lastModelSelection?.reasoningEffort, 'high');
        expect(
          modeController.state.confirmedMode,
          AgentConversationModeId.plan,
        );
        expect(modeController.state.pendingTurnMode, isNull);
        expect(viewModel.conversationModeAppliesToNextTurn, isTrue);
      },
    );

    test('sends Default explicitly for a mode-capable new thread', () async {
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      await viewModel.sendMessage('continue normally');

      final selection = provider.turnConfigurations.single.conversationMode!;
      expect(selection.modeId, AgentConversationModeId.defaultMode);
      expect(selection.effectiveModelId, 'gpt-5.6');
      expect(selection.effectiveReasoningEffort, 'high');
    });

    test(
      'offers a local handoff after Plan completion and starts Default execution',
      () async {
        final attentions = <AgentAttentionSignal>[];
        final provider = _ModeFakeAgentProvider(
          availableModels: _conversationModeModels,
        );
        final viewModel = _createViewModel(
          provider,
          onAttention: attentions.add,
        );
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        viewModel.selectConversationMode(AgentConversationModeId.plan);
        await viewModel.sendMessage('plan this change');
        await _emitCompletedPlan(provider);

        final request = viewModel.planExecutionRequest;
        expect(request, isNotNull);
        expect(request!.sessionId, 'thread-1');
        expect(request.turnId, 'turn-1');
        expect(request.markdown, '# Final plan\n\n- Implement the change');
        expect(attentions, hasLength(1));
        expect(
          attentions.single.kind,
          AgentAttentionKind.planExecutionRequired,
        );
        expect(attentions.single.phase, AgentAttentionPhase.raised);

        await viewModel.startPlanExecution(request);

        expect(viewModel.planExecutionRequest, isNull);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );
        expect(provider.turnConfigurations, hasLength(2));
        expect(
          provider.turnConfigurations.last.conversationMode!.modeId,
          AgentConversationModeId.defaultMode,
        );
        expect(
          viewModel.messages.map((message) => message.text),
          contains(AgentConversationViewModel.planExecutionPrompt),
        );
        expect(attentions.last.kind, AgentAttentionKind.planExecutionRequired);
        expect(attentions.last.phase, AgentAttentionPhase.resolved);
      },
    );

    test('keeps Plan selected when revising the local handoff', () async {
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      viewModel.selectConversationMode(AgentConversationModeId.plan);
      await viewModel.sendMessage('plan this change');
      // 用户在 Plan 运行期间改了下一回合草稿；“继续规划”必须显式切回 Plan。
      viewModel.selectConversationMode(AgentConversationModeId.defaultMode);
      await _emitCompletedPlan(provider);
      final request = viewModel.planExecutionRequest!;

      await viewModel.revisePlanExecution(request);

      expect(viewModel.planExecutionRequest, isNull);
      expect(viewModel.selectedConversationMode, AgentConversationModeId.plan);
      expect(provider.turnConfigurations, hasLength(1));
    });

    test(
      'sends revision text as a Plan-mode turn when revising handoff',
      () async {
        final provider = _ModeFakeAgentProvider(
          availableModels: _conversationModeModels,
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        viewModel.selectConversationMode(AgentConversationModeId.plan);
        await viewModel.sendMessage('plan this change');
        await _emitCompletedPlan(provider);
        final request = viewModel.planExecutionRequest!;

        await viewModel.revisePlanExecution(
          request,
          revisionMessage: '请改为分三阶段实施，并补充回滚步骤',
        );

        expect(viewModel.planExecutionRequest, isNull);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
        expect(provider.turnConfigurations, hasLength(2));
        expect(
          provider.turnConfigurations.last.conversationMode!.modeId,
          AgentConversationModeId.plan,
        );
        expect(
          viewModel.messages.map((message) => message.text),
          contains('请改为分三阶段实施，并补充回滚步骤'),
        );
      },
    );

    test(
      'dismisses the local handoff without sending or changing mode',
      () async {
        final provider = _ModeFakeAgentProvider(
          availableModels: _conversationModeModels,
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        viewModel.selectConversationMode(AgentConversationModeId.plan);
        await viewModel.sendMessage('plan this change');
        await _emitCompletedPlan(provider);
        final request = viewModel.planExecutionRequest!;

        viewModel.dismissPlanExecution(request);

        expect(viewModel.planExecutionRequest, isNull);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
        expect(provider.turnConfigurations, hasLength(1));
      },
    );

    test('clears the local handoff when the workspace changes', () async {
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      viewModel.selectConversationMode(AgentConversationModeId.plan);
      await viewModel.sendMessage('plan this change');
      await _emitCompletedPlan(provider);
      expect(viewModel.planExecutionRequest, isNotNull);

      viewModel.updateWorkspace(
        projectPath: '/another-project',
        contextFilePath: null,
      );

      expect(viewModel.planExecutionRequest, isNull);
    });

    test('does not offer execution for an interrupted Plan turn', () async {
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      viewModel.selectConversationMode(AgentConversationModeId.plan);
      await viewModel.sendMessage('plan this change');
      await _emitCompletedPlan(
        provider,
        status: AgentHistoryTurnStatus.interrupted,
      );

      expect(viewModel.planExecutionRequest, isNull);
    });

    test('failed mode send preserves draft and clears pending state', () async {
      final modeController = AgentConversationModeController();
      addTearDown(modeController.dispose);
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
        sendError: StateError('send failed'),
      );
      final viewModel = _createViewModel(
        provider,
        conversationModeController: modeController,
      );
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      viewModel.selectConversationMode(AgentConversationModeId.plan);
      await viewModel.sendMessage('plan this change');

      expect(modeController.state.draftMode, AgentConversationModeId.plan);
      expect(
        modeController.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
      expect(modeController.state.pendingTurnMode, isNull);
      expect(viewModel.conversationModeAppliesToNextTurn, isFalse);
    });

    test(
      'applies server name update while staying on a newly started thread',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello from a new thread');
        // 新会话在 generated_title 到来前使用首条用户消息作临时标题。
        expect(viewModel.currentThreadTitle, 'hello from a new thread');
        expect(viewModel.sessionId, 'thread-1');

        provider.emit(
          const AgentThreadNameUpdatedEvent(
            threadId: 'thread-1',
            threadName: 'Auto named title',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentThreadTitle, 'Auto named title');
        expect(viewModel.currentSession?.title, 'Auto named title');
      },
    );

    test('syncThreadTitleIfCurrent updates only the active thread', () async {
      final viewModel = _createViewModel(_FakeAgentProvider());
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      expect(viewModel.currentThreadTitle, 'hello');

      viewModel.syncThreadTitleIfCurrent('other-thread', 'Ignored');
      expect(viewModel.currentThreadTitle, 'hello');

      viewModel.syncThreadTitleIfCurrent('thread-1', 'From list refresh');
      expect(viewModel.currentThreadTitle, 'From list refresh');
    });

    test('resets header title after project switch', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);
      viewModel.updateWorkspace(
        projectPath: '/other-repo',
        contextFilePath: null,
      );

      expect(
        viewModel.currentThreadTitle,
        AgentConversationViewModel.defaultThreadTitle,
      );
    });

    test('does not resume when history loading fails', () async {
      final provider = _FakeAgentProvider(failHistory: true);
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());

      expect(provider.calls, <String>['read:thread-1']);
      expect(viewModel.status.state, AgentProviderConnectionState.error);
      expect(viewModel.status.message, 'Could not load thread history');
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.openFailed);
      final texts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .toList();
      expect(
        texts.any((text) => text.contains('Could not load thread history')),
        isTrue,
      );
      expect(viewModel.canSubmitMessage, isFalse);
    });

    test('keeps loaded history when first resume fails', () async {
      final provider = _FakeAgentProvider(
        failResume: true,
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-1',
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'user-1',
                    role: AgentMessageRole.user,
                    text: 'Keep this history',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await viewModel.sendMessage('Resume this thread');

      expect(provider.calls, <String>['read:thread-1', 'resume:thread-1']);
      expect(viewModel.status.state, AgentProviderConnectionState.error);
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.openFailed);
      expect(viewModel.canSubmitMessage, isFalse);
      expect(provider.calls, isNot(contains('start')));
      final texts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .toList();
      expect(texts, contains('Keep this history'));
      expect(texts, contains('Resume this thread'));
    });

    test('switchThread allows switching away from a running thread', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-running',
                status: AgentHistoryTurnStatus.running,
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'history-a',
                    role: AgentMessageRole.user,
                    text: 'Thread one history',
                  ),
                ],
              ),
            ],
          ),
          'thread-2': _historySnapshot(
            threadId: 'thread-2',
            userText: 'Thread two history',
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread(id: 'thread-1'));
      // 历史里的 running 不升为 Zeta live 执行中。
      expect(viewModel.isTurnRunning, isFalse);

      await viewModel.switchThread(
        _thread(id: 'thread-2', title: 'Thread two'),
      );

      expect(viewModel.currentThreadTitle, 'Thread two');
      expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.idle);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        contains('Thread two history'),
      );
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        isNot(contains('Thread one history')),
      );
      expect(provider.calls, <String>[
        'read:thread-1',
        'unsubscribe:thread-1',
        'read:thread-2',
      ]);
      expect(provider.unsubscribedThreads, <String>['thread-1']);
    });

    test(
      'switchThread does not unsubscribe when selecting the same thread',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Same thread',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread(id: 'thread-1'));
        await viewModel.switchThread(_thread(id: 'thread-1'));

        expect(provider.unsubscribedThreads, isEmpty);
        expect(provider.calls, <String>['read:thread-1', 'read:thread-1']);
      },
    );

    test(
      'updateWorkspace unsubscribes previous thread on project change',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Leaving project',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        viewModel.updateWorkspace(
          projectPath: '/repo-a',
          contextFilePath: null,
        );
        await viewModel.switchThread(_thread(id: 'thread-1'));
        expect(provider.unsubscribedThreads, isEmpty);

        viewModel.updateWorkspace(
          projectPath: '/repo-b',
          contextFilePath: null,
        );
        await Future<void>.delayed(Duration.zero);

        expect(provider.unsubscribedThreads, <String>['thread-1']);
      },
    );

    test('updateWorkspace rejects restored thread without provider', () {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      viewModel.updateWorkspace(
        projectPath: '/repo',
        contextFilePath: null,
        restoredSessionId: 'orphan-thread',
      );

      expect(viewModel.sessionId, isNull);
    });

    test('updateWorkspace keeps restored thread with provider ownership', () {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      viewModel.updateWorkspace(
        projectPath: '/repo',
        contextFilePath: null,
        restoredSessionId: 'thread-1',
        restoredProviderId: defaultAgentProviderId,
      );

      expect(viewModel.sessionId, 'thread-1');
    });

    test(
      'history running turn stays non-live; first send resumes and starts a new turn',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-running',
                  status: AgentHistoryTurnStatus.running,
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'history-user-1',
                      role: AgentMessageRole.user,
                      text: 'Historical context',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        expect(viewModel.isTurnRunning, isFalse);
        expect(viewModel.canSubmitMessage, isTrue);
        expect(viewModel.showRunningIndicator, isFalse);

        await viewModel.sendMessage('hello after open');

        expect(provider.calls, <String>[
          'read:thread-1',
          'resume:thread-1',
          'send:thread-1',
        ]);
        expect(
          viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
            (entry) => entry.message.text,
          ),
          contains('hello after open'),
        );
      },
    );

    test(
      'switchThread ignores provider list active without live turn',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'past',
              agentText: 'reply',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(
          _thread(
            id: 'thread-1',
            status: AgentThreadRuntimeStatus.active,
            waitingOnApproval: true,
            waitingOnUserInput: true,
          ),
        );

        expect(viewModel.isTurnRunning, isFalse);
        expect(viewModel.threadRuntimeStatus, AgentThreadRuntimeStatus.idle);
        expect(viewModel.threadWaitingOnApproval, isFalse);
        expect(viewModel.threadWaitingOnUserInput, isFalse);
        expect(viewModel.showRunningIndicator, isFalse);
      },
    );

    test('running turn keeps mode changes for the next new turn', () async {
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-history',
                status: AgentHistoryTurnStatus.completed,
                collaborationMode: AgentConversationModeId.plan,
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      await viewModel.switchThread(_thread());
      expect(viewModel.selectedConversationMode, AgentConversationModeId.plan);

      await viewModel.sendMessage('start plan work');
      expect(viewModel.isTurnRunning, isTrue);

      viewModel.selectConversationMode(AgentConversationModeId.defaultMode);
      expect(viewModel.conversationModeAppliesToNextTurn, isTrue);

      // 完成当前 live turn（fake 默认 turn id 为 turn-1）。
      provider.emit(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.isTurnRunning, isFalse);
      expect(viewModel.conversationModeAppliesToNextTurn, isFalse);

      await viewModel.sendMessage('start the next turn');
      expect(
        provider.turnConfigurations.last.conversationMode!.modeId,
        AgentConversationModeId.defaultMode,
      );
    });

    test(
      'restores history mode and scopes settings updates to current thread',
      () async {
        final provider = _ModeFakeAgentProvider(
          availableModels: _conversationModeModels,
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-1',
                  collaborationMode: AgentConversationModeId.plan,
                ),
              ],
            ),
            'thread-2': const AgentThreadHistorySnapshot(
              threadId: 'thread-2',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-2',
                  collaborationMode: AgentConversationModeId.defaultMode,
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        await viewModel.switchThread(_thread(id: 'thread-1'));
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );

        await viewModel.switchThread(
          _thread(id: 'thread-2', title: 'Thread two'),
        );
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );

        provider.emit(
          AgentThreadSettingsUpdatedEvent(
            threadId: 'thread-1',
            collaborationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'gpt-5.6',
              effectiveReasoningEffort: 'medium',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.defaultMode,
        );

        provider.emit(
          AgentThreadSettingsUpdatedEvent(
            threadId: 'thread-2',
            collaborationMode: AgentConversationModeSelection(
              modeId: AgentConversationModeId.plan,
              effectiveModelId: 'gpt-5.6',
              effectiveReasoningEffort: 'medium',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          viewModel.selectedConversationMode,
          AgentConversationModeId.plan,
        );
      },
    );

    test('rapid thread switch discards a late history mode', () async {
      final threadAHistory = Completer<AgentThreadHistorySnapshot>();
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-2': const AgentThreadHistorySnapshot(
            threadId: 'thread-2',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-2',
                collaborationMode: AgentConversationModeId.defaultMode,
                entries: <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'thread-2-message',
                    role: AgentMessageRole.agent,
                    text: 'Current thread history',
                  ),
                ],
              ),
            ],
          ),
        },
        historyCompleters: <String, Completer<AgentThreadHistorySnapshot>>{
          'thread-1': threadAHistory,
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      final threadASwitch = viewModel.switchThread(_thread(id: 'thread-1'));
      while (!provider.calls.contains('read:thread-1')) {
        await Future<void>.delayed(Duration.zero);
      }

      await viewModel.switchThread(
        _thread(id: 'thread-2', title: 'Thread two'),
      );
      threadAHistory.complete(
        const AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              collaborationMode: AgentConversationModeId.plan,
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'thread-1-message',
                  role: AgentMessageRole.agent,
                  text: 'Stale thread history',
                ),
              ],
            ),
          ],
        ),
      );
      await threadASwitch;

      expect(viewModel.currentThreadTitle, 'Thread two');
      expect(
        viewModel.selectedConversationMode,
        AgentConversationModeId.defaultMode,
      );
      final messages = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text);
      expect(messages, contains('Current thread history'));
      expect(messages, isNot(contains('Stale thread history')));
    });

    test('thread switch rejects a late accepted mode snapshot', () async {
      final modeController = AgentConversationModeController();
      addTearDown(modeController.dispose);
      final sendResult = Completer<AgentTurn>();
      final provider = _ModeFakeAgentProvider(
        availableModels: _conversationModeModels,
        sendResult: sendResult,
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-2': const AgentThreadHistorySnapshot(
            threadId: 'thread-2',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-2',
                collaborationMode: AgentConversationModeId.defaultMode,
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(
        provider,
        conversationModeController: modeController,
      );
      addTearDown(viewModel.dispose);

      await viewModel.loadModels();
      viewModel.selectConversationMode(AgentConversationModeId.plan);
      final oldSend = viewModel.sendMessage('plan on thread one');
      while (provider.turnConfigurations.isEmpty) {
        await Future<void>.delayed(Duration.zero);
      }

      await viewModel.switchThread(
        _thread(id: 'thread-2', title: 'Thread two'),
      );
      sendResult.complete(const AgentTurn(id: 'turn-1', sessionId: 'thread-1'));
      await oldSend;

      expect(
        modeController.state.confirmedMode,
        AgentConversationModeId.defaultMode,
      );
      expect(
        modeController.state.draftMode,
        AgentConversationModeId.defaultMode,
      );
      expect(modeController.state.pendingTurnMode, isNull);
    });

    test(
      'sendMessage includes localImage inputs and timeline previews',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
        await viewModel.sendMessage(
          'look at this',
          localImagePaths: const <String>[r'D:\tmp\a.png', r'D:\tmp\b.png'],
        );

        expect(provider.calls, contains('send:thread-1'));
        expect(provider.calls, contains('image:D:\\tmp\\a.png'));
        expect(provider.calls, contains('image:D:\\tmp\\b.png'));
        final userMessage = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message)
            .firstWhere((message) => message.role == AgentMessageRole.user);
        expect(userMessage.text, 'look at this');
        expect(userMessage.localImagePaths, <String>[
          r'D:\tmp\a.png',
          r'D:\tmp\b.png',
        ]);
      },
    );

    test('sendMessage allows image-only payloads', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
      await viewModel.sendMessage(
        '   ',
        localImagePaths: const <String>[r'D:\tmp\only.png'],
      );

      expect(provider.calls, contains('image:D:\\tmp\\only.png'));
      final userMessage = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.role == AgentMessageRole.user);
      expect(userMessage.text, isEmpty);
      expect(userMessage.localImagePaths, <String>[r'D:\tmp\only.png']);
    });

    test(
      'cancel is a no-op when history only shows running without live turn',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-running',
                  status: AgentHistoryTurnStatus.running,
                  entries: <AgentHistoryEntry>[
                    AgentHistoryMessageEntry(
                      id: 'history-user-1',
                      role: AgentMessageRole.user,
                      text: 'Historical context',
                    ),
                  ],
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await viewModel.cancelActiveTurn();

        // 无 live turn 时不向 provider 发 cancel。
        expect(provider.calls, <String>['read:thread-1']);
      },
    );

    test(
      'ignores realtime events from a non-selected thread after switching',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Thread one history',
            ),
            'thread-2': _historySnapshot(
              threadId: 'thread-2',
              userText: 'Thread two history',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread(id: 'thread-1'));
        await viewModel.switchThread(
          _thread(id: 'thread-2', title: 'Thread two'),
        );
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'late-message',
            delta: 'Late update from thread one',
            role: AgentMessageRole.agent,
            sessionId: 'thread-1',
            turnId: 'thread-1-turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final texts = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, contains('Thread two history'));
        expect(texts, isNot(contains('Late update from thread one')));
      },
    );

    test(
      'drops a queued event from the previous listener generation',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'Thread one history',
            ),
            'thread-2': _historySnapshot(
              threadId: 'thread-2',
              userText: 'Thread two history',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread(id: 'thread-1'));
        // 不等待 broadcast stream 投递；switchThread 必须在首个 await 前废弃旧代次。
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'queued-old-message',
            delta: 'Queued update from old listener',
            role: AgentMessageRole.agent,
          ),
        );
        await viewModel.switchThread(
          _thread(id: 'thread-2', title: 'Thread two'),
        );
        await Future<void>.delayed(Duration.zero);

        final texts = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, contains('Thread two history'));
        expect(texts, isNot(contains('Queued update from old listener')));
      },
    );

    test('rejects events after the provider runtime epoch changes', () async {
      final provider = _RuntimeScopedFakeAgentProvider(
        runtimeScope: const AgentRuntimeScope(
          runtimeId: 'runtime-1',
          connectionEpoch: 1,
        ),
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': _historySnapshot(
            threadId: 'thread-1',
            userText: 'Thread one history',
          ),
          'thread-2': _historySnapshot(
            threadId: 'thread-2',
            userText: 'Thread two history',
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread(id: 'thread-1'));
      provider.runtimeScope = const AgentRuntimeScope(
        runtimeId: 'runtime-2',
        connectionEpoch: 2,
      );
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'old-runtime-message',
          delta: 'Event from mismatched runtime',
          role: AgentMessageRole.agent,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.messages.map((message) => message.text),
        isNot(contains('Event from mismatched runtime')),
      );

      // Thread 切换创建的新 generation 捕获 runtime-2，后续事件恢复正常。
      await viewModel.switchThread(
        _thread(id: 'thread-2', title: 'Thread two'),
      );
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'new-runtime-message',
          delta: 'Event from current runtime',
          role: AgentMessageRole.agent,
          sessionId: 'thread-2',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.messages.map((message) => message.text),
        contains('Event from current runtime'),
      );
    });

    test(
      'merges realtime agent message metadata into existing message',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming commentary',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          viewModel.timelineEntries
              .whereType<AgentMessageTimelineEntry>()
              .last
              .message
              .isCompletedCommentary,
          isFalse,
        );

        provider.emit(
          const AgentMessageUpdatedEvent(
            messageId: 'agent-1',
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.completed,
            duration: Duration(seconds: 5),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final message = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .last
            .message;
        expect(message.text, 'Streaming commentary');
        expect(message.isCompletedCommentary, isTrue);
        expect(message.duration, const Duration(seconds: 5));
      },
    );

    test('streams reasoning deltas into an expanded think card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.text,
          delta: 'raw-a',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.text,
          delta: 'raw-b',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await _drainTypedUiUpdate();

      var think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.kind, AgentToolKind.think);
      expect(think.title, '思考');
      expect(think.content, 'raw-araw-b');
      expect(think.status, AgentToolStatus.inProgress);
      expect(viewModel.isToolCallExpanded('reasoning-1'), isTrue);

      // 摘要到达后优先展示摘要，不再拼接原文。
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'sum-1',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryPart,
          summaryIndex: 1,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentReasoningDeltaEvent(
          itemId: 'reasoning-1',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'sum-2',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await _drainTypedUiUpdate();

      think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.content, 'sum-1\n\nsum-2');

      // completed 带完整正文时覆盖流式缓冲。
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'reasoning-1',
            title: '思考',
            kind: AgentToolKind.think,
            status: AgentToolStatus.completed,
            content: 'final summary',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      think = viewModel.timelineEntries
          .whereType<AgentToolTimelineEntry>()
          .single
          .toolCall;
      expect(think.status, AgentToolStatus.completed);
      expect(think.content, 'final summary');
    });

    test(
      'preserves normalized message tool and reasoning phase order',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider
          ..emit(
            const AgentMessageDeltaEvent(
              messageId: 'message-seg1',
              sourceMessageId: 'provider-message-a',
              delta: 'Before tool',
              role: AgentMessageRole.agent,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          )
          ..emit(
            const AgentToolCallEvent(
              AgentToolCall(
                id: 'tool-read',
                title: 'Read file',
                kind: AgentToolKind.read,
                status: AgentToolStatus.pending,
                sessionId: 'thread-1',
                turnId: 'turn-1',
              ),
            ),
          )
          ..emit(
            const AgentMessageDeltaEvent(
              messageId: 'message-seg2',
              sourceMessageId: 'provider-message-a',
              delta: 'After tool',
              role: AgentMessageRole.agent,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          )
          ..emit(
            const AgentReasoningDeltaEvent(
              itemId: 'reasoning-phase1',
              sourceItemId: 'provider-reasoning-a',
              kind: AgentReasoningDeltaKind.text,
              delta: 'Think before run',
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          )
          ..emit(
            const AgentToolCallEvent(
              AgentToolCall(
                id: 'tool-run',
                title: 'Run tests',
                kind: AgentToolKind.execute,
                status: AgentToolStatus.pending,
                sessionId: 'thread-1',
                turnId: 'turn-1',
              ),
            ),
          )
          ..emit(
            const AgentReasoningDeltaEvent(
              itemId: 'reasoning-phase2',
              sourceItemId: 'provider-reasoning-a',
              kind: AgentReasoningDeltaKind.text,
              delta: 'Think after run',
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          );
        await _drainTypedUiUpdate();

        final orderedIds = viewModel.liveTurnState!.entries
            .map(
              (entry) => switch (entry) {
                AgentMessageTimelineEntry(:final message) => message.id,
                AgentToolTimelineEntry(:final toolCall) => toolCall.id,
                _ => null,
              },
            )
            .whereType<String>()
            .where(
              (id) => const <String>{
                'message-seg1',
                'tool-read',
                'message-seg2',
                'reasoning-phase1',
                'tool-run',
                'reasoning-phase2',
              }.contains(id),
            );
        expect(orderedIds, <String>[
          'message-seg1',
          'tool-read',
          'message-seg2',
          'reasoning-phase1',
          'tool-run',
          'reasoning-phase2',
        ]);
      },
    );

    test('streams plan deltas into an expanded plan card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'plan-1',
          delta: '# Plan\n',
          role: AgentMessageRole.agent,
          kind: AgentMessageKind.plan,
          status: AgentMessageStatus.streaming,
          raw: <String, Object?>{'type': 'agentMessage'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentMessageDeltaEvent(
          messageId: 'plan-1',
          delta: '- Step one',
          role: AgentMessageRole.agent,
          kind: AgentMessageKind.plan,
          status: AgentMessageStatus.streaming,
          raw: <String, Object?>{'type': 'agentMessage'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await _drainTypedUiUpdate();

      final plan = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.id == 'plan-1');
      expect(plan.kind, AgentMessageKind.plan);
      expect(plan.text, '# Plan\n- Step one');
      expect(viewModel.isPlanMessageExpanded(plan.id), isTrue);

      // completed item 用权威全文覆盖拼接结果。
      provider.emit(
        const AgentMessageUpdatedEvent(
          messageId: 'plan-1',
          kind: AgentMessageKind.plan,
          text: '# Final Plan\n\n- Step one\n- Step two',
          role: AgentMessageRole.agent,
          status: AgentMessageStatus.completed,
          raw: <String, Object?>{'type': 'agentMessage'},
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final completed = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message)
          .firstWhere((message) => message.id == 'plan-1');
      expect(completed.text, '# Final Plan\n\n- Step one\n- Step two');
      expect(completed.status, AgentMessageStatus.completed);
      expect(completed.kind, AgentMessageKind.plan);
    });

    test('upserts turn-level aggregated diff into the live timeline', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff:
              'diff --git a/lib/a.dart b/lib/a.dart\n'
              '--- a/lib/a.dart\n'
              '+++ b/lib/a.dart\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+new\n'
              'diff --git a/lib/b.dart b/lib/b.dart\n'
              '--- a/lib/b.dart\n'
              '+++ b/lib/b.dart\n'
              '@@ -1 +1,2 @@\n'
              ' keep\n'
              '+added\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final entry = viewModel.timelineEntries
          .whereType<AgentTurnDiffTimelineEntry>()
          .single;
      expect(entry.turnId, 'turn-1');
      expect(entry.diff, contains('lib/a.dart'));
      expect(entry.diff, contains('lib/b.dart'));

      // 同一 turn 的后续通知覆盖全文，不追加第二条。
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff:
              'diff --git a/lib/a.dart b/lib/a.dart\n'
              '--- a/lib/a.dart\n'
              '+++ b/lib/a.dart\n'
              '@@ -1 +1 @@\n'
              '-old\n'
              '+newer\n',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.timelineEntries.whereType<AgentTurnDiffTimelineEntry>(),
        hasLength(1),
      );
      expect(
        viewModel.timelineEntries
            .whereType<AgentTurnDiffTimelineEntry>()
            .single
            .diff,
        contains('+newer'),
      );

      // 空 diff 移除条目。
      provider.emit(
        const AgentTurnDiffEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          diff: '',
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(
        viewModel.timelineEntries.whereType<AgentTurnDiffTimelineEntry>(),
        isEmpty,
      );
    });

    test('exposes waiting status capsule from thread/status/changed', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.threadWaitingOnApproval, isTrue);
      expect(viewModel.threadStatusCapsuleLabel, '等待审批');
      expect(viewModel.showRunningIndicator, isFalse);

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.active,
          waitingOnUserInput: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.threadStatusCapsuleLabel, '等待输入');

      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.threadWaitingOnApproval, isFalse);
      expect(viewModel.threadWaitingOnUserInput, isFalse);
      expect(viewModel.threadStatusCapsuleLabel, isNull);
    });

    test(
      'turn completed clears sticky active runtime status for list snapshot',
      () async {
        final provider = _FakeAgentProvider();
        var turnCompletedCount = 0;
        final viewModel = _createViewModel(
          provider,
          onTurnCompleted: () => turnCompletedCount += 1,
        );
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentThreadStatusChangedEvent(
            threadId: 'thread-1',
            status: AgentThreadRuntimeStatus.active,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.isTurnRunning, isTrue);
        expect(viewModel.threadRuntimeStatus, AgentThreadRuntimeStatus.active);
        expect(viewModel.threadSnapshot.isTurnRunning, isTrue);
        expect(
          viewModel.threadSnapshot.runtimeStatus,
          AgentThreadRuntimeStatus.active,
        );

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.isTurnRunning, isFalse);
        expect(viewModel.threadRuntimeStatus, AgentThreadRuntimeStatus.idle);
        expect(viewModel.threadSnapshot.isTurnRunning, isFalse);
        expect(
          viewModel.threadSnapshot.runtimeStatus,
          AgentThreadRuntimeStatus.idle,
        );
        expect(turnCompletedCount, 1);
      },
    );

    test(
      'defers event thread snapshot notifications received during build phase',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        await _drainTypedUiUpdate();
        final scheduler = _uiFrameSchedulers.single;
        final snapshotBeforeEvent = viewModel.threadSnapshot;
        var snapshotNotificationCount = 0;
        void handleSnapshot() => snapshotNotificationCount += 1;
        viewModel.threadSnapshotListenable.addListener(handleSnapshot);
        addTearDown(
          () =>
              viewModel.threadSnapshotListenable.removeListener(handleSnapshot),
        );

        await scheduler.runInBuildPhaseAsync(() async {
          provider.emit(
            const AgentThreadStatusChangedEvent(
              threadId: 'thread-1',
              status: AgentThreadRuntimeStatus.active,
              waitingOnApproval: true,
            ),
          );
          await _drainTypedUiScheduling();

          expect(
            viewModel.threadRuntimeStatus,
            AgentThreadRuntimeStatus.active,
          );
          expect(viewModel.threadWaitingOnApproval, isTrue);
          expect(viewModel.threadSnapshot, snapshotBeforeEvent);
          expect(snapshotNotificationCount, 0);
          expect(scheduler.pendingCallbackCount, greaterThan(0));
        });

        scheduler.pumpFrame();

        expect(snapshotNotificationCount, 1);
        expect(
          viewModel.threadSnapshot.runtimeStatus,
          AgentThreadRuntimeStatus.active,
        );
        expect(viewModel.threadSnapshot.waitingOnApproval, isTrue);
      },
    );

    test('provider event stream closing interrupts the active turn', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentThreadStatusChangedEvent(
          threadId: 'thread-1',
          status: AgentThreadRuntimeStatus.active,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.isTurnRunning, isTrue);
      expect(viewModel.threadRuntimeStatus, AgentThreadRuntimeStatus.active);

      await provider.dispose();
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.isTurnRunning, isFalse);
      expect(viewModel.threadRuntimeStatus, isNull);
      expect(viewModel.threadSnapshot.isTurnRunning, isFalse);
      final interruptedTurn = viewModel.conversationTurns.singleWhere(
        (turn) => turn.id == 'turn-1',
      );
      expect(interruptedTurn.status, AgentHistoryTurnStatus.interrupted);
    });

    test(
      'dismisses approval card when serverRequest/resolved arrives',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);
        var autoScrollEffects = 0;
        final effectSubscription = viewModel.uiEffects.listen((effect) {
          if (effect is AgentRequestAutoScroll) {
            autoScrollEffects += 1;
          }
        });
        addTearDown(effectSubscription.cancel);
        final pendingState = viewModel.pendingInteractionState;
        provider.emit(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'approval-1',
              title: 'Run command',
              kind: AgentPermissionKind.commandExecution,
              command: 'flutter test',
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.permissionRequests.map((item) => item.id), <String>[
          'approval-1',
        ]);
        expect(
          viewModel.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
          hasLength(1),
        );
        expect(viewModel.pendingInteractionState, isNot(pendingState));
        expect(autoScrollEffects, 0);

        final requestedPendingState = viewModel.pendingInteractionState;
        provider.emit(
          const AgentPermissionResolvedEvent(
            requestId: 'approval-1',
            threadId: 'thread-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.permissionRequests, isEmpty);
        expect(
          viewModel.timelineEntries.whereType<AgentPermissionTimelineEntry>(),
          isEmpty,
        );
        expect(viewModel.pendingInteractionState, isNot(requestedPendingState));
        expect(autoScrollEffects, 0);
      },
    );

    test(
      'keeps user questions independent and dismisses them when resolved',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        await Future<void>.delayed(Duration.zero);
        provider.emit(
          const AgentQuestionRequestedEvent(
            AgentQuestionRequest(
              id: 'question-1',
              title: 'Choose scope',
              sessionId: 'thread-1',
              turnId: 'turn-1',
              questions: <AgentUserInputQaPair>[
                AgentUserInputQaPair(
                  questionId: 'scope',
                  question: 'Select a scope',
                ),
              ],
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.permissionRequests, isEmpty);
        expect(viewModel.questionRequests.map((item) => item.id), <String>[
          'question-1',
        ]);
        expect(
          viewModel.timelineEntries.whereType<AgentQuestionTimelineEntry>(),
          hasLength(1),
        );

        provider.emit(
          const AgentQuestionResolvedEvent(
            requestId: 'question-1',
            threadId: 'thread-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.questionRequests, isEmpty);
        expect(
          viewModel.timelineEntries.whereType<AgentQuestionTimelineEntry>(),
          isEmpty,
        );
      },
    );

    test('appends MCP tool progress onto the matching tool card', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'mcp-1',
            title: 'MCP · docs · search',
            kind: AgentToolKind.search,
            status: AgentToolStatus.inProgress,
            content: 'query: zeta',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        ),
      );
      provider.emit(
        const AgentToolCallEvent(
          AgentToolCall(
            id: 'mcp-1',
            title: 'MCP tool',
            kind: AgentToolKind.other,
            status: AgentToolStatus.inProgress,
            content: 'Fetching resources…',
            sessionId: 'thread-1',
            turnId: 'turn-1',
            raw: <String, Object?>{'_progressAppend': true},
          ),
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 80));

      final tool = viewModel.toolCalls.single;
      expect(tool.title, 'MCP · docs · search');
      expect(tool.kind, AgentToolKind.search);
      expect(tool.content, 'query: zeta\nFetching resources…');
      expect(viewModel.isToolCallExpanded('mcp-1'), isTrue);
    });

    test('shows model reroute system event and header notice', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentModelReroutedEvent(
          threadId: 'thread-1',
          turnId: 'turn-1',
          fromModel: 'gpt-5.4',
          toModel: 'gpt-5.5',
          reason: 'highRiskCyberActivity',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.systemNoticeLabel, '已改道至 gpt-5.5');
      final event = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .single
          .event;
      expect(event.kind, AgentHistoryEventKind.system);
      expect(event.title, '模型已改道');
      expect(event.description, 'gpt-5.4 → gpt-5.5');
      expect(event.content, '原因：高风险网络活动策略');

      provider.emit(
        const AgentTurnCompletedEvent(sessionId: 'thread-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.systemNoticeLabel, isNull);
    });

    test('shows deprecation notice once per summary', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      const notice = AgentDeprecationNoticeEvent(
        summary: 'turn/tokenCount is deprecated',
        details: 'Use thread/tokenUsage/updated instead.',
      );
      provider.emit(notice);
      provider.emit(notice);
      await Future<void>.delayed(Duration.zero);

      final events = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .map((entry) => entry.event)
          .toList();
      expect(events, hasLength(1));
      expect(events.single.kind, AgentHistoryEventKind.warning);
      expect(events.single.title, '适配层弃用提示');
      expect(events.single.description, 'turn/tokenCount is deprecated');
      expect(
        events.single.content,
        contains('Use thread/tokenUsage/updated instead.'),
      );
      expect(events.single.content, contains('请升级 Codex 适配层'));
    });

    test('renders system ThreadItem events on the timeline', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentSystemItemEvent(
          entry: AgentHistoryEventEntry(
            id: 'compact-1',
            kind: AgentHistoryEventKind.system,
            title: '上下文已压缩',
            description: '会话上下文已压缩以腾出窗口空间。',
          ),
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final event = viewModel.timelineEntries
          .whereType<AgentHistoryEventTimelineEntry>()
          .single
          .event;
      expect(event.id, 'compact-1');
      expect(event.title, '上下文已压缩');
    });

    test(
      'stores structured plans on the live turn without timeline messages',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Inspect timeline', status: 'completed'),
              AgentPlanEntry(content: 'Render panel', status: 'inProgress'),
              AgentPlanEntry(content: 'Run tests', status: 'pending'),
            ],
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(
          viewModel.activePlanEntries.map((entry) => entry.content),
          <String>['Inspect timeline', 'Render panel', 'Run tests'],
        );
        expect(viewModel.shouldShowActivePlan, isTrue);
        expect(
          viewModel.timelineEntries
              .whereType<AgentMessageTimelineEntry>()
              .where((entry) => entry.message.id == 'turn-1-plan'),
          isEmpty,
        );

        final historyState = viewModel.historyState;
        final expansionState = viewModel.expansionState;
        expect(viewModel.isActivePlanExpanded('turn-1'), isFalse);
        viewModel.toggleActivePlan('turn-1');
        expect(viewModel.historyState, historyState);
        expect(viewModel.expansionState, isNot(expansionState));
        expect(viewModel.isActivePlanExpanded('turn-1'), isTrue);

        provider.emit(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Wrong turn', status: 'inProgress'),
              AgentPlanEntry(content: 'Must be ignored', status: 'pending'),
            ],
            sessionId: 'thread-1',
            turnId: 'turn-stale',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.activePlanEntries, hasLength(3));

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.activePlanEntries, isEmpty);
        expect(viewModel.shouldShowActivePlan, isFalse);
      },
    );

    test('groups history entries by turn in conversationTurns', () async {
      final startedAt = DateTime.parse('2026-07-04T06:00:00.000Z');
      final completedAt = DateTime.parse('2026-07-04T06:00:03.000Z');
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-a',
                entries: <AgentHistoryEntry>[
                  const AgentHistoryMessageEntry(
                    id: 'user-a',
                    role: AgentMessageRole.user,
                    text: 'First request',
                  ),
                  const AgentHistoryMessageEntry(
                    id: 'agent-a',
                    role: AgentMessageRole.agent,
                    text: 'First response',
                  ),
                ],
                status: AgentHistoryTurnStatus.completed,
                startedAt: startedAt,
                completedAt: completedAt,
                duration: const Duration(seconds: 3),
                tokenUsage: const AgentTokenUsage(
                  inputTokens: 41910,
                  cachedInputTokens: 19712,
                  outputTokens: 2332,
                  totalTokens: 43462,
                ),
              ),
              AgentHistoryTurn(
                id: 'turn-b',
                entries: <AgentHistoryEntry>[
                  const AgentHistoryMessageEntry(
                    id: 'user-b',
                    role: AgentMessageRole.user,
                    text: 'Second request',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);

      final turns = viewModel.conversationTurns;
      // 加载历史后 welcome 消息被清空，只剩两个历史回合。
      expect(turns, hasLength(2));
      expect(turns.first.id, 'turn-a');
      expect(turns.first.isStandby, isFalse);
      expect(turns.first.status, AgentHistoryTurnStatus.completed);
      expect(turns.first.startedAt, startedAt);
      expect(turns.first.duration, const Duration(seconds: 3));
      expect(turns.first.tokenUsage, isNotNull);
      expect(turns.first.tokenUsage!.totalTokens, 43462);
      expect(turns.first.tokenUsage!.inputTokens, 41910);
      expect(turns.first.tokenUsage!.outputTokens, 2332);
      expect(turns[1].tokenUsage, isNull);
      expect(viewModel.currentThreadTokenUsage, isNotNull);
      expect(viewModel.currentThreadTokenUsage!.totalTokens, 43462);
      expect(viewModel.currentThreadTokenUsage!.inputTokens, 41910);
      expect(
        turns.first.entries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        <String>['First request', 'First response'],
      );
      expect(turns[1].id, 'turn-b');
      expect(
        (turns[1].entries.single as AgentMessageTimelineEntry).message.text,
        'Second request',
      );
      // 展平后的 timelineEntries 仍包含全部历史消息。
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>['First request', 'Second request']),
      );
    });

    test('exposes all historical turns after loading a long thread', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': AgentThreadHistorySnapshot(
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
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);

      expect(
        viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
        <String>['turn-1', 'turn-2', 'turn-3', 'turn-4', 'turn-5'],
      );
      expect(
        viewModel.conversationTurns.map((turn) => turn.id).toList(),
        <String>['turn-1', 'turn-2', 'turn-3', 'turn-4', 'turn-5'],
      );
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        containsAll(<String>[
          'Request 1',
          'Request 2',
          'Request 3',
          'Request 4',
          'Request 5',
        ]),
      );
    });

    test(
      'keeps history state stable while refreshing header and composer token state',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');

        final liveTurn = viewModel.liveTurnState;
        expect(liveTurn, isNotNull);

        var historyNotifications = 0;
        var headerNotifications = 0;
        var composerNotifications = 0;
        var liveNotifications = 0;
        viewModel.historyStateListenable.addListener(() {
          historyNotifications += 1;
        });
        viewModel.headerStateListenable.addListener(() {
          headerNotifications += 1;
        });
        viewModel.composerStateListenable.addListener(() {
          composerNotifications += 1;
        });
        liveTurn!.addListener(() {
          liveNotifications += 1;
        });

        final historyState = viewModel.historyState;
        final headerState = viewModel.headerState;
        final composerState = viewModel.composerState;

        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming reply',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 1000,
              outputTokens: 300,
              totalTokens: 1300,
              lastTotalTokens: 1200,
              modelContextWindow: 2000,
            ),
          ),
        );
        await _drainTypedUiUpdate();

        // history 保持稳定；header（会话 token）与 composer（上下文进度环）需同步刷新。
        expect(viewModel.historyState, historyState);
        expect(viewModel.headerState, isNot(headerState));
        expect(viewModel.composerState, isNot(composerState));
        expect(viewModel.currentThreadLastTokenUsage?.totalTokens, 1200);
        expect(historyNotifications, 0);
        expect(headerNotifications, 1);
        expect(composerNotifications, 1);
        expect(liveNotifications, 1);
      },
    );

    test(
      'throttles high-frequency tool output updates into a single live flush',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');

        final liveTurn = viewModel.liveTurnState;
        expect(liveTurn, isNotNull);

        var historyNotifications = 0;
        var headerNotifications = 0;
        var composerNotifications = 0;
        var liveNotifications = 0;
        var autoScrollNotifications = 0;
        viewModel.historyStateListenable.addListener(() {
          historyNotifications += 1;
        });
        viewModel.headerStateListenable.addListener(() {
          headerNotifications += 1;
        });
        viewModel.composerStateListenable.addListener(() {
          composerNotifications += 1;
        });
        final effectSubscription = viewModel.uiEffects.listen((effect) {
          if (effect is AgentRequestAutoScroll) {
            autoScrollNotifications += 1;
          }
        });
        addTearDown(effectSubscription.cancel);
        liveTurn!.addListener(() {
          liveNotifications += 1;
        });

        final historyState = viewModel.historyState;
        final headerState = viewModel.headerState;
        final composerState = viewModel.composerState;

        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Command output',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'line 1',
            ),
          ),
        );
        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-1',
              title: 'Command output',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              content: 'line 2',
            ),
          ),
        );
        await _drainTypedUiUpdate();

        // 核心契约：高频 tool progress 经 EventBuffer 合并后，Store 只保留最新内容；
        // history/composer 不因 progress 抖动。UI 分区 notify 次数受帧调度影响，
        // 不在此做硬性 1 次断言（见 plan/agent_stream_perf_grok_alignment_plan.md）。
        expect(viewModel.historyState, historyState);
        expect(viewModel.composerState, composerState);
        expect(historyNotifications, 0);
        expect(composerNotifications, 0);
        expect(
          viewModel.headerState == headerState || headerNotifications == 1,
          isTrue,
        );
        expect(headerNotifications, lessThanOrEqualTo(1));
        expect(liveNotifications, lessThanOrEqualTo(2));
        expect(autoScrollNotifications, lessThanOrEqualTo(2));
        expect(
          viewModel.timelineEntries
              .whereType<AgentToolTimelineEntry>()
              .single
              .toolCall
              .content,
          'line 2',
        );
      },
    );

    test(
      'moves a completed live turn into historical order after all prior turns',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                for (var index = 1; index <= 5; index += 1)
                  AgentHistoryTurn(
                    id: 'history-$index',
                    entries: <AgentHistoryEntry>[
                      AgentHistoryMessageEntry(
                        id: 'history-user-$index',
                        role: AgentMessageRole.user,
                        text: 'Request $index',
                      ),
                    ],
                  ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await Future<void>.delayed(Duration.zero);
        await viewModel.sendMessage('hello');

        expect(
          viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
          <String>[
            'history-1',
            'history-2',
            'history-3',
            'history-4',
            'history-5',
          ],
        );
        expect(viewModel.liveTurnState, isNotNull);

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.liveTurnState, isNull);
        expect(
          viewModel.visibleHistoryTurns.map((turn) => turn.id).toList(),
          <String>[
            'history-1',
            'history-2',
            'history-3',
            'history-4',
            'history-5',
            'turn-1',
          ],
        );
      },
    );

    test(
      'groups live user message and agent reply into the same turn',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentMessageDeltaEvent(
            messageId: 'agent-1',
            delta: 'Streaming reply',
            role: AgentMessageRole.agent,
            phase: AgentMessagePhase.commentary,
            status: AgentMessageStatus.streaming,
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final turns = viewModel.conversationTurns;
        // 发送后 Ready 占位已移除，只剩一个 live 回合。
        expect(turns, hasLength(1));
        final liveTurn = turns.single;
        expect(liveTurn.isStandby, isFalse);
        expect(liveTurn.status, AgentHistoryTurnStatus.running);
        final texts = liveTurn.entries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .toList();
        expect(texts, containsAll(<String>['hello', 'Streaming reply']));
        expect(
          viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
            (entry) => entry.message.id,
          ),
          isNot(contains('welcome')),
        );
      },
    );

    test('attaches live token usage to the active turn group', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTokenUsageEvent(
          tokenUsage: AgentTokenUsage(
            inputTokens: 1000,
            cachedInputTokens: 200,
            outputTokens: 350,
            totalTokens: 1300,
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final liveTurn = viewModel.conversationTurns.last;
      expect(liveTurn.tokenUsage, isNotNull);
      expect(liveTurn.tokenUsage!.totalTokens, 1300);
      expect(liveTurn.tokenUsage!.inputTokens, 1000);
      expect(liveTurn.tokenUsage!.cachedInputTokens, 200);
      expect(liveTurn.tokenUsage!.outputTokens, 350);
    });

    test(
      'tracks activity segment and freezes tool elapsed on complete',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        expect(
          viewModel.currentActivity.phase,
          AgentTurnActivityPhase.starting,
        );
        expect(viewModel.currentTurnStartedAt, isNotNull);
        expect(viewModel.runningActivityLabel, '启动中');

        provider.emit(
          const AgentReasoningDeltaEvent(
            itemId: 'think-1',
            kind: AgentReasoningDeltaKind.summaryText,
            delta: 'step one',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          viewModel.currentActivity.phase,
          AgentTurnActivityPhase.thinking,
        );
        expect(viewModel.runningActivityLabel, '思考中');

        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'cmd-1',
              title: 'npm test',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          viewModel.currentActivity.phase,
          AgentTurnActivityPhase.toolRunning,
        );
        expect(viewModel.runningActivityLabel, contains('npm test'));

        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'cmd-1',
              title: 'npm test',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.completed,
              content: 'ok',
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);
        final cmd = viewModel.timelineEntries
            .whereType<AgentToolTimelineEntry>()
            .map((entry) => entry.toolCall)
            .firstWhere((tool) => tool.id == 'cmd-1');
        expect(cmd.duration, isNotNull);

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(viewModel.currentActivity.phase, AgentTurnActivityPhase.idle);
        expect(viewModel.isTurnRunning, isFalse);
      },
    );

    test(
      'marks failed turns and shows the failure reason inside the turn',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.failed,
            errorMessage: 'Model provider rejected the request',
            duration: Duration(seconds: 5),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final turn = viewModel.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-1',
        );
        expect(turn.status, AgentHistoryTurnStatus.failed);
        expect(turn.duration, const Duration(seconds: 5));
        final failureTexts = turn.entries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .where((text) => text.contains('Turn failed'))
            .toList();
        expect(failureTexts, <String>[
          'Turn failed: Model provider rejected the request',
        ]);
      },
    );

    test(
      'does not repeat a failure reason already shown by an error event',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentErrorEvent(
            message: 'Context window exceeded',
            code: 'contextWindowExceeded',
            willRetry: false,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            status: AgentHistoryTurnStatus.failed,
            errorMessage: 'Context window exceeded',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        final errorTexts = viewModel.timelineEntries
            .whereType<AgentMessageTimelineEntry>()
            .map((entry) => entry.message.text)
            .where((text) => text.contains('Context window exceeded'))
            .toList();
        expect(errorTexts, hasLength(1));
        expect(errorTexts.single, isNot(contains('Turn failed')));
        expect(errorTexts.single, contains('压缩上下文'));

        final turn = viewModel.conversationTurns.singleWhere(
          (turn) => turn.id == 'turn-1',
        );
        expect(turn.status, AgentHistoryTurnStatus.failed);
      },
    );

    test('shows capacity guidance for serverOverloaded live errors', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentErrorEvent(
          message:
              'Selected model is at capacity. Please try a different model.',
          code: 'serverOverloaded',
          willRetry: false,
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentTurnCompletedEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.failed,
          errorMessage:
              'Selected model is at capacity. Please try a different model.',
          errorCode: 'serverOverloaded',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final errorTexts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .where((text) => text.contains('at capacity'))
          .toList();
      expect(errorTexts, hasLength(1));
      expect(errorTexts.single, contains('当前模型容量已满'));
      expect(errorTexts.single, isNot(contains('Turn failed')));
    });

    test('logs normalized error events for every provider', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('private user prompt');
      provider.emit(
        const AgentErrorEvent(
          message: 'Provider rejected the request',
          code: 'rateLimited',
          willRetry: false,
          sessionId: 'thread-1',
          turnId: 'turn-1',
          raw: <String, Object?>{
            'jsonRpcError': <String, Object?>{
              'code': -32003,
              'accessToken': 'event-secret',
            },
          },
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final record = records.singleWhere(
        (record) => record.message.startsWith('Agent provider error event: '),
      );
      final context = _structuredLogContext(
        record,
        prefix: 'Agent provider error event: ',
      );
      expect(context['providerId'], defaultAgentProviderId);
      expect(context['operation'], 'provider/event');
      expect(context['sessionId'], 'thread-1');
      expect(context['turnId'], 'turn-1');
      expect(context['code'], 'rateLimited');
      final diagnostic = context['diagnostic']! as Map<String, Object?>;
      final rpc = diagnostic['jsonRpcError']! as Map<String, Object?>;
      expect(rpc['code'], -32003);
      expect(rpc['accessToken'], '••••••');
      expect(record.message, isNot(contains('event-secret')));
      expect(record.message, isNot(contains('private user prompt')));
    });

    test('logs exceptions thrown by any provider conversation call', () async {
      final records = <LogRecord>[];
      final subscription = Logger.root.onRecord.listen(records.add);
      addTearDown(subscription.cancel);
      final error = StateError('request failed token=operation-secret');
      final provider = _FakeAgentProvider(sendError: error);
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('private user prompt');

      final record = records.singleWhere(
        (record) =>
            record.message.startsWith('Agent provider operation failed: '),
      );
      final context = _structuredLogContext(
        record,
        prefix: 'Agent provider operation failed: ',
      );
      expect(record.error, same(error));
      expect(record.stackTrace, isNotNull);
      expect(context['providerId'], defaultAgentProviderId);
      expect(context['operation'], 'conversation/sendMessage');
      expect(context['sessionId'], 'thread-1');
      expect(context['category'], 'request');
      final exception = context['exception']! as Map<String, Object?>;
      expect(exception['type'], 'StateError');
      expect(exception['message'], isNot(contains('operation-secret')));
      expect(record.message, isNot(contains('private user prompt')));
    });

    test('keeps unique ids for consecutive error events', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentErrorEvent(
          message: 'Codex stderr',
          details: 'first',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      provider.emit(
        const AgentErrorEvent(
          message: 'Codex stderr',
          details: 'second',
          sessionId: 'thread-1',
          turnId: 'turn-1',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final errorEntries = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .where((entry) => entry.message.id.startsWith('error-'))
          .toList();
      expect(errorEntries, hasLength(2));
      expect(errorEntries[0].message.id, isNot(errorEntries[1].message.id));
      expect(errorEntries.map((entry) => entry.id).toSet(), hasLength(2));

      final blocks = buildAgentTimelineRenderBlocks(
        turnId: 'turn-1',
        entries: viewModel.conversationTurns
            .singleWhere((turn) => turn.id == 'turn-1')
            .entries,
      );
      expect(blocks.map((block) => block.id).toSet(), hasLength(blocks.length));
    });

    test('marks interrupted turns without adding extra messages', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTurnCompletedEvent(
          sessionId: 'thread-1',
          turnId: 'turn-1',
          status: AgentHistoryTurnStatus.interrupted,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      final turn = viewModel.conversationTurns.singleWhere(
        (turn) => turn.id == 'turn-1',
      );
      expect(turn.status, AgentHistoryTurnStatus.interrupted);
      final systemTexts = viewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text)
          .where((text) => text.contains('Turn failed'))
          .toList();
      expect(systemTexts, isEmpty);
    });

    test(
      'exposes header token usage only while the active turn is running',
      () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 1000,
              cachedInputTokens: 200,
              outputTokens: 350,
              totalTokens: 1300,
              lastInputTokens: 920,
              lastCachedInputTokens: 180,
              lastOutputTokens: 320,
              lastTotalTokens: 1240,
              modelContextWindow: 2000,
            ),
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentTurnTokenUsage, isNotNull);
        expect(viewModel.currentTurnTokenUsage!.totalTokens, 1300);
        expect(viewModel.currentThreadLastTokenUsage, isNotNull);
        expect(viewModel.currentThreadLastTokenUsage!.totalTokens, 1240);

        provider.emit(
          const AgentTurnCompletedEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.currentTurnTokenUsage, isNull);
        expect(viewModel.currentThreadTokenUsage, isNotNull);
        expect(viewModel.currentThreadTokenUsage!.totalTokens, 1300);
        expect(viewModel.currentThreadLastTokenUsage!.totalTokens, 1240);
      },
    );

    test('keeps session token total and derives live turn deltas', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': const AgentThreadHistorySnapshot(
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
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(_thread());
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.currentThreadTokenUsage!.totalTokens, 2250);

      await viewModel.sendMessage('hello');
      provider.emit(
        const AgentTokenUsageEvent(
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
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.currentTurnTokenUsage, isNotNull);
      expect(viewModel.currentTurnTokenUsage!.totalTokens, 1300);
      expect(viewModel.currentTurnTokenUsage!.inputTokens, 1000);
      expect(viewModel.currentThreadTokenUsage, isNotNull);
      expect(viewModel.currentThreadTokenUsage!.inputTokens, 3000);
      expect(viewModel.currentThreadTokenUsage!.cachedInputTokens, 700);
      expect(viewModel.currentThreadTokenUsage!.outputTokens, 680);
      expect(viewModel.currentThreadTokenUsage!.totalTokens, 3550);
      expect(viewModel.currentThreadLastTokenUsage, isNotNull);
      expect(viewModel.currentThreadLastTokenUsage!.inputTokens, 920);
      expect(viewModel.currentThreadLastTokenUsage!.cachedInputTokens, 180);
      expect(viewModel.currentThreadLastTokenUsage!.outputTokens, 320);
      expect(viewModel.currentThreadLastTokenUsage!.totalTokens, 1240);
      expect(viewModel.currentThreadLastTokenUsage!.modelContextWindow, 2000);
    });

    test('offers compact when context window usage is high', () async {
      final provider = _FakeAgentProvider(
        historySnapshot: AgentThreadHistorySnapshot(
          threadId: 'thread-1',
          turns: <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'turn-1',
              status: AgentHistoryTurnStatus.completed,
              tokenUsage: const AgentTokenUsage(
                totalTokens: 4000,
                lastTotalTokens: 900,
                modelContextWindow: 1000,
              ),
              entries: const <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'user-1',
                  role: AgentMessageRole.user,
                  text: 'hello',
                ),
              ],
            ),
          ],
        ),
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: 'hello',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );

      expect(viewModel.currentThreadLastTokenUsage, isNotNull);
      expect(viewModel.currentThreadLastTokenUsage!.totalTokens, 900);
      expect(viewModel.contextWindowUsageRatio, closeTo(0.9, 0.001));
      expect(viewModel.shouldOfferContextCompact, isTrue);
      // 首回合前没有稳定的 lastTurnId 包含式边界，不能伪造分支能力。
      expect(viewModel.canEditLastUserMessage, isFalse);

      await viewModel.compactCurrentThread();
      expect(provider.calls, contains('compact:thread-1'));
      expect(viewModel.isCompacting, isTrue);

      provider.emit(
        const AgentThreadCompactedEvent(threadId: 'thread-1', turnId: 'turn-1'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(viewModel.isCompacting, isFalse);
    });

    test('renames the current thread and applies name updated event', () async {
      final provider = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': AgentThreadHistorySnapshot(
            threadId: 'thread-1',
            turns: <AgentHistoryTurn>[
              AgentHistoryTurn(
                id: 'turn-1',
                tokenUsage: const AgentTokenUsage(
                  totalTokens: 90000,
                  modelContextWindow: 100000,
                ),
                entries: const <AgentHistoryEntry>[
                  AgentHistoryMessageEntry(
                    id: 'user-1',
                    role: AgentMessageRole.user,
                    text: 'hello',
                  ),
                ],
              ),
            ],
          ),
        },
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          title: 'Original',
          preview: 'hello',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      expect(viewModel.currentThreadTitle, 'Original');

      await viewModel.renameCurrentThread('Renamed title');
      expect(provider.calls, contains('rename:thread-1:Renamed title'));
      expect(viewModel.currentThreadTitle, 'Renamed title');

      await Future<void>.delayed(Duration.zero);
      expect(viewModel.currentThreadTitle, 'Renamed title');
    });

    test('edit last user message creates branch then resends', () async {
      final provider =
          _FakeAgentProvider(
              historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
                'thread-1': const AgentThreadHistorySnapshot(
                  threadId: 'thread-1',
                  turns: <AgentHistoryTurn>[
                    AgentHistoryTurn(
                      id: 'turn-1',
                      status: AgentHistoryTurnStatus.completed,
                      entries: <AgentHistoryEntry>[
                        AgentHistoryMessageEntry(
                          id: 'user-1',
                          role: AgentMessageRole.user,
                          text: 'first prompt',
                        ),
                      ],
                    ),
                    AgentHistoryTurn(
                      id: 'turn-2',
                      status: AgentHistoryTurnStatus.completed,
                      entries: <AgentHistoryEntry>[
                        AgentHistoryMessageEntry(
                          id: 'user-2',
                          role: AgentMessageRole.user,
                          text: 'old prompt',
                        ),
                      ],
                    ),
                  ],
                ),
                'forked-thread-1': const AgentThreadHistorySnapshot(
                  threadId: 'forked-thread-1',
                  turns: <AgentHistoryTurn>[],
                ),
              },
            )
            ..forkResult = const AgentSession(
              id: 'forked-thread-1',
              providerId: defaultAgentProviderId,
            );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'thread-1',
          providerId: defaultAgentProviderId,
          projectPath: '/repo',
          preview: 'old prompt',
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );
      await viewModel.editLastUserMessageAndRetry('new prompt');

      expect(provider.calls, contains('fork:thread-1:through:turn-1'));
      expect(provider.calls, contains('send:forked-thread-1'));
    });

    test('handles model list event and reconciles default selection', () async {
      final provider = _FakeAgentProvider();
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      // loadModels 会建立事件订阅；fake 的 listModels 返回空列表，
      // 随后手动 emit 真实模型列表来验证事件处理。
      await viewModel.loadModels();
      provider.emit(
        const AgentModelListEvent(
          AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                  AgentModelReasoningEffort(effort: 'medium'),
                  AgentModelReasoningEffort(effort: 'high'),
                ],
                defaultReasoningEffort: 'medium',
                serviceTiers: <AgentModelServiceTier>[
                  AgentModelServiceTier(id: 'priority', name: 'Fast'),
                ],
              ),
              AgentModelInfo(
                id: 'gpt-5.4-mini',
                model: 'gpt-5.4-mini',
                displayName: 'GPT-5.4-Mini',
              ),
            ],
          ),
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(viewModel.models, hasLength(2));
      expect(viewModel.selectedModelId, 'gpt-5.5');
      expect(viewModel.selectedReasoningEffort, 'medium');
      expect(viewModel.selectedServiceTierId, isNull);
      expect(viewModel.showReasoningEffort, isTrue);
      expect(viewModel.showServiceTier, isTrue);
    });

    test('lets the shared catalog own provider refresh decisions', () async {
      // Arrange
      final provider = _FakeAgentProvider(
        availableModels: const AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'fresh-model',
              model: 'fresh-model',
              displayName: 'Fresh model',
            ),
          ],
        ),
      );
      final viewModel = _createViewModel(provider);
      addTearDown(viewModel.dispose);

      // Act
      await viewModel.loadModels();
      await viewModel.loadModels();

      // Assert
      expect(provider.refreshModelsCalls, 1);
      expect(provider.listModelsCalls, 0);
      expect(viewModel.models.single.id, 'fresh-model');
    });

    test(
      'persists a model response only once when an event is also emitted',
      () async {
        // Arrange
        final store = _ConversationModelCatalogStore();
        final repository = AgentModelCatalogRepository(store: store);
        final provider = _FakeAgentProvider(
          emitModelEventOnRefresh: true,
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'event-model',
                model: 'event-model',
                displayName: 'Event model',
              ),
            ],
          ),
        );
        final viewModel = _createViewModel(
          provider,
          modelCatalogRepository: repository,
        );
        addTearDown(viewModel.dispose);

        // Act
        await viewModel.loadModels();
        await Future<void>.delayed(Duration.zero);

        // Assert
        expect(store.saveCalls, 1);
      },
    );

    test(
      'switchThread prefers current session selection and falls back to the latest turn model',
      () async {
        final provider = _FakeAgentProvider(
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                  AgentModelReasoningEffort(effort: 'high'),
                ],
                defaultReasoningEffort: 'low',
                serviceTiers: <AgentModelServiceTier>[
                  AgentModelServiceTier(id: 'priority', name: 'Fast'),
                ],
              ),
            ],
          ),
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-1',
                  model: 'gpt-5.5',
                  raw: <String, Object?>{
                    'turnContext': <String, Object?>{
                      'model': 'gpt-5.5',
                      'effort': 'low',
                      'serviceTier': 'priority',
                    },
                  },
                ),
                AgentHistoryTurn(id: 'turn-2'),
              ],
              currentTurn: AgentHistoryTurn(
                id: 'turn-2',
                raw: <String, Object?>{
                  'turnContext': <String, Object?>{'effort': 'high'},
                },
              ),
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        // 不预先 loadModels：打开 thread 时应自行 hydrate 后再回填 history 选择。
        await viewModel.switchThread(_thread());

        expect(viewModel.models, isNotEmpty);
        expect(viewModel.selectedModelId, 'gpt-5.5');
        expect(viewModel.selectedReasoningEffort, 'high');
        expect(viewModel.selectedServiceTierId, 'priority');
      },
    );

    test(
      'session config update keeps last turn model when current session omits model',
      () async {
        final provider = _FakeAgentProvider(
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
                supportedReasoningEfforts: <AgentModelReasoningEffort>[
                  AgentModelReasoningEffort(effort: 'low'),
                  AgentModelReasoningEffort(effort: 'high'),
                ],
                defaultReasoningEffort: 'low',
                serviceTiers: <AgentModelServiceTier>[
                  AgentModelServiceTier(id: 'priority', name: 'Fast'),
                ],
              ),
            ],
          ),
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': const AgentThreadHistorySnapshot(
              threadId: 'thread-1',
              turns: <AgentHistoryTurn>[
                AgentHistoryTurn(
                  id: 'turn-1',
                  model: 'gpt-5.5',
                  raw: <String, Object?>{
                    'turnContext': <String, Object?>{
                      'model': 'gpt-5.5',
                      'effort': 'low',
                    },
                  },
                ),
              ],
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.loadModels();
        await viewModel.switchThread(_thread());
        provider.emit(
          const AgentSessionConfigUpdatedEvent(
            sessionId: 'thread-1',
            options: <AgentSessionConfigOption>[
              AgentSessionConfigOption(
                id: 'thought',
                name: 'Thought level',
                category: 'thought_level',
                kind: AgentSessionConfigOptionKind.select,
                currentValue: 'high',
                values: <AgentSessionConfigValue>[
                  AgentSessionConfigValue(id: 'high', label: 'High'),
                ],
              ),
              AgentSessionConfigOption(
                id: 'fast',
                name: 'Fast',
                category: 'model_config',
                kind: AgentSessionConfigOptionKind.boolean,
                currentValue: true,
              ),
            ],
          ),
        );
        await Future<void>.delayed(Duration.zero);

        expect(viewModel.selectedModelId, 'gpt-5.5');
        expect(viewModel.selectedReasoningEffort, 'high');
        expect(viewModel.selectedServiceTierId, 'priority');
      },
    );

    test(
      'switchActiveProvider rejects retired Cursor before initialization',
      () async {
        // Arrange
        final cursorConfig = AgentProviderConfig.defaultCursor.copyWith(
          enabled: true,
        );
        final codex = _FakeAgentProvider();
        final cursor = _FakeAgentProvider(
          providerConfig: cursorConfig,
          declaredCapabilities: AgentProviderCapabilities.unsupported,
        );
        final factory = _MultiFakeAgentProviderFactory(<String, AgentProvider>{
          defaultAgentProviderId: codex,
          cursorAgentProviderId: cursor,
        });
        final controller = ActiveAgentProviderController(
          providerFactory: factory,
          configStore: MemoryAgentProviderConfigStore(
            AgentProviderSettings(
              providers: <AgentProviderConfig>[
                AgentProviderConfig.defaultCodex,
                cursorConfig,
              ],
            ),
          ),
        );
        addTearDown(controller.dispose);
        final viewModel = AgentConversationViewModel(
          providerController: controller,
          uiFrameScheduler: _createUiFrameScheduler(),
        );
        addTearDown(viewModel.dispose);
        viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

        // Act
        await viewModel.loadModels();
        final switchFuture = viewModel.switchActiveProvider(
          cursorAgentProviderId,
        );

        // Assert
        await expectLater(switchFuture, throwsUnsupportedError);
        expect(codex.initializeCalls, 1);
        expect(cursor.initializeCalls, 0);
        expect(viewModel.activeProviderId, defaultAgentProviderId);
        expect(factory.createdProviderIds, <String>[defaultAgentProviderId]);
      },
    );

    test(
      'legacy Cursor selection shows unavailable reason while using fallback',
      () async {
        // Arrange
        final codex = _FakeAgentProvider();
        final cursorConfig = AgentProviderConfig.defaultCursor.copyWith(
          enabled: true,
        );
        final factory = _MultiFakeAgentProviderFactory(<String, AgentProvider>{
          defaultAgentProviderId: codex,
        });
        final controller = ActiveAgentProviderController(
          providerFactory: factory,
          configStore: MemoryAgentProviderConfigStore(
            AgentProviderSettings(
              providers: <AgentProviderConfig>[
                AgentProviderConfig.defaultCodex,
                cursorConfig,
              ],
              activeProviderId: cursorAgentProviderId,
            ),
          ),
        );
        addTearDown(controller.dispose);
        final viewModel = AgentConversationViewModel(
          providerController: controller,
          uiFrameScheduler: _createUiFrameScheduler(),
        );
        addTearDown(viewModel.dispose);

        // Act
        await viewModel.loadModels();

        // Assert
        expect(
          viewModel.status.state,
          AgentProviderConnectionState.unavailable,
        );
        expect(viewModel.status.message, 'Cursor Agent unavailable');
        expect(viewModel.status.details, contains('已临时回退'));
        expect(viewModel.activeProviderId, defaultAgentProviderId);
        expect(factory.createdProviderIds, <String>[defaultAgentProviderId]);
      },
    );

    test('Cursor deep link is fail-closed before provider creation', () async {
      // Arrange
      final codex = _FakeAgentProvider();
      final cursor = _FakeAgentProvider(
        providerConfig: AgentProviderConfig.defaultCursor.copyWith(
          enabled: true,
        ),
        declaredCapabilities: AgentProviderCapabilities.unsupported,
      );
      final factory = _MultiFakeAgentProviderFactory(<String, AgentProvider>{
        defaultAgentProviderId: codex,
        cursorAgentProviderId: cursor,
      });
      final controller = ActiveAgentProviderController(
        providerFactory: factory,
        configStore: MemoryAgentProviderConfigStore(
          AgentProviderSettings(
            providers: <AgentProviderConfig>[
              AgentProviderConfig.defaultCodex,
              cursor.config,
            ],
          ),
        ),
      );
      addTearDown(controller.dispose);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
        uiFrameScheduler: _createUiFrameScheduler(),
      );
      addTearDown(viewModel.dispose);

      // Act：switchThread 是 deep link / 历史入口共享的语义入口。
      await viewModel.switchThread(
        AgentThreadSummary(
          id: 'cursor-deep-link',
          providerId: cursorAgentProviderId,
          projectPath: '/repo',
          title: 'Legacy Cursor thread',
          preview: 'legacy',
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
          status: AgentThreadRuntimeStatus.idle,
        ),
      );

      // Assert
      expect(viewModel.status.state, AgentProviderConnectionState.unavailable);
      expect(viewModel.status.details, contains('已退役'));
      expect(factory.createdProviderIds, isEmpty);
      expect(cursor.calls, isEmpty);
      expect(cursor.initializeCalls, 0);
    });

    test('selectModel updates selection and persists to config', () async {
      final provider = _FakeAgentProvider(
        availableModels: const AgentModelList(
          models: <AgentModelInfo>[
            AgentModelInfo(
              id: 'gpt-5.5',
              model: 'gpt-5.5',
              displayName: 'GPT-5.5',
              isDefault: true,
              supportedReasoningEfforts: <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'low'),
                AgentModelReasoningEffort(effort: 'medium'),
              ],
              defaultReasoningEffort: 'medium',
            ),
            AgentModelInfo(
              id: 'gpt-5.4-mini',
              model: 'gpt-5.4-mini',
              displayName: 'GPT-5.4-Mini',
              supportedReasoningEfforts: <AgentModelReasoningEffort>[
                AgentModelReasoningEffort(effort: 'low'),
              ],
              defaultReasoningEffort: 'low',
            ),
          ],
        ),
      );
      final controller = ActiveAgentProviderController(
        providerFactory: _FakeAgentProviderFactory(provider),
        configStore: MemoryAgentProviderConfigStore(),
      );
      addTearDown(controller.dispose);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
        uiFrameScheduler: _createUiFrameScheduler(),
      );
      addTearDown(viewModel.dispose);
      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

      await viewModel.loadModels();
      expect(provider.initializeCalls, 1);
      expect(
        viewModel.models.map((model) => model.id),
        contains('gpt-5.4-mini'),
      );

      await viewModel.selectModel('gpt-5.4-mini');

      expect(viewModel.selectedModelId, 'gpt-5.4-mini');
      // 切换模型时回退到该模型的默认推理档位。
      expect(viewModel.selectedReasoningEffort, 'low');
      // 持久化到 provider 配置。
      expect(controller.activeProviderConfig.selectedModel, 'gpt-5.4-mini');
      expect(controller.activeProviderConfig.selectedReasoningEffort, 'low');
    });

    test(
      'switchActiveProvider reloads models and selection for the target',
      () async {
        // Arrange
        final codexConfig = AgentProviderConfig.defaultCodex.copyWith(
          selectedModel: 'gpt-5.5',
        );
        final grokConfig = AgentProviderConfig.defaultGrok.copyWith(
          selectedModel: 'grok-4.5',
        );
        final codex = _FakeAgentProvider(
          providerConfig: codexConfig,
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'gpt-5.5',
                model: 'gpt-5.5',
                displayName: 'GPT-5.5',
                isDefault: true,
              ),
            ],
          ),
        );
        final grok = _FakeAgentProvider(
          providerConfig: grokConfig,
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'grok-4.5',
                model: 'grok-4.5',
                displayName: 'Grok 4.5',
                isDefault: true,
              ),
            ],
          ),
        );
        final controller = ActiveAgentProviderController(
          providerFactory: _MultiFakeAgentProviderFactory(
            <String, AgentProvider>{
              defaultAgentProviderId: codex,
              grokAgentProviderId: grok,
            },
          ),
          configStore: MemoryAgentProviderConfigStore(
            AgentProviderSettings(
              providers: <AgentProviderConfig>[codexConfig, grokConfig],
            ),
          ),
        );
        addTearDown(controller.dispose);
        final viewModel = AgentConversationViewModel(
          providerController: controller,
          uiFrameScheduler: _createUiFrameScheduler(),
        );
        addTearDown(viewModel.dispose);
        viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
        await viewModel.loadModels();
        expect(viewModel.selectedModelId, 'gpt-5.5');

        // Act
        await viewModel.switchActiveProvider(grokAgentProviderId);

        // Assert
        expect(viewModel.models.map((model) => model.id), <String>['grok-4.5']);
        expect(viewModel.selectedModelId, 'grok-4.5');
        expect(grok.lastModelSelection?.modelId, 'grok-4.5');
        expect(
          codex.disposed,
          isFalse,
          reason: '切换 active Provider 只释放租约，应用级运行时继续保温',
        );
      },
    );

    test(
      'opening a Grok thread resumes and sends via Grok, not Codex',
      () async {
        // Arrange：默认 active 为 Codex，打开 Grok 历史 thread 后应切换并 resume。
        final codex = _FakeAgentProvider(
          providerConfig: AgentProviderConfig.defaultCodex,
        );
        final grok = _FakeAgentProvider(
          providerConfig: AgentProviderConfig.defaultGrok,
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'grok-sess-1': _historySnapshot(
              threadId: 'grok-sess-1',
              userText: 'previous question',
              agentText: 'previous answer',
            ),
          },
        );
        final controller = ActiveAgentProviderController(
          providerFactory: _MultiFakeAgentProviderFactory(
            <String, AgentProvider>{
              defaultAgentProviderId: codex,
              grokAgentProviderId: grok,
            },
          ),
          configStore: MemoryAgentProviderConfigStore(
            const AgentProviderSettings(
              providers: <AgentProviderConfig>[
                AgentProviderConfig.defaultCodex,
                AgentProviderConfig.defaultGrok,
              ],
            ),
          ),
        );
        addTearDown(controller.dispose);
        final viewModel = AgentConversationViewModel(
          providerController: controller,
          uiFrameScheduler: _createUiFrameScheduler(),
        );
        addTearDown(viewModel.dispose);
        viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

        // Act
        await viewModel.switchThread(
          AgentThreadSummary(
            id: 'grok-sess-1',
            providerId: grokAgentProviderId,
            projectPath: '/repo',
            title: 'Grok history',
            sessionPath: '/home/.grok/sessions/grok-sess-1',
            preview: 'previous question',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1),
            updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
            status: AgentThreadRuntimeStatus.idle,
          ),
        );
        // 选文件只更新上下文，不应清掉「必须 resume」约束。
        viewModel.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: '/repo/lib/main.dart',
          restoredSessionId: 'grok-sess-1',
          restoredProviderId: grokAgentProviderId,
        );
        await viewModel.sendMessage('continue this Grok session');

        // Assert
        expect(viewModel.activeProviderId, grokAgentProviderId);
        expect(viewModel.canSubmitMessage, isTrue);
        expect(viewModel.requiresResumedSelectedThread, isFalse);
        expect(viewModel.sessionId, 'grok-sess-1');
        expect(codex.calls, isEmpty);
        expect(
          grok.calls,
          containsAllInOrder(<String>[
            'read:grok-sess-1',
            'resume:grok-sess-1',
            'send:grok-sess-1',
          ]),
        );
        expect(grok.calls, isNot(contains('start')));
      },
    );

    test('waits for provider settings before opening a Codex thread', () async {
      // Arrange：模拟应用启动时配置仍在读取，持久化 active provider 为 Grok。
      final settingsCompleter = Completer<AgentProviderSettings>();
      final configStore = _DelayedAgentProviderConfigStore(settingsCompleter);
      final codex = _FakeAgentProvider(
        historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
          'thread-1': _historySnapshot(
            threadId: 'thread-1',
            userText: 'Codex history',
          ),
        },
      );
      final grok = _FakeAgentProvider(
        providerConfig: AgentProviderConfig.defaultGrok,
      );
      final factory = _MultiFakeAgentProviderFactory(<String, AgentProvider>{
        defaultAgentProviderId: codex,
        grokAgentProviderId: grok,
      });
      final controller = ActiveAgentProviderController(
        providerFactory: factory,
        configStore: configStore,
      );
      addTearDown(controller.dispose);
      final viewModel = AgentConversationViewModel(
        providerController: controller,
        uiFrameScheduler: _createUiFrameScheduler(),
      );
      addTearDown(viewModel.dispose);
      viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);

      // Act：workspace 创建会先异步加载配置，session restore 紧接着打开 thread。
      final settingsFuture = viewModel.loadSettings();
      final switchFuture = viewModel.switchThread(_thread());
      settingsCompleter.complete(
        const AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultGrok,
          ],
          activeProviderId: grokAgentProviderId,
        ),
      );
      await Future.wait(<Future<void>>[settingsFuture, switchFuture]);

      // Assert：Codex thread 不得落到稍后加载完成的 Grok provider。
      expect(viewModel.activeProviderId, defaultAgentProviderId);
      expect(factory.createdProviderIds, <String>[defaultAgentProviderId]);
      expect(codex.calls, <String>['read:thread-1']);
      expect(grok.calls, isEmpty);
      expect(
        viewModel.timelineEntries.whereType<AgentMessageTimelineEntry>().map(
          (entry) => entry.message.text,
        ),
        contains('Codex history'),
      );
    });

    test(
      'context-only workspace update keeps requiresResumed for open thread',
      () async {
        final provider = _FakeAgentProvider(
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'hello',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        expect(viewModel.requiresResumedSelectedThread, isTrue);

        viewModel.updateWorkspace(
          projectPath: '/repo',
          contextFilePath: '/repo/a.dart',
          restoredSessionId: 'thread-1',
          restoredProviderId: defaultAgentProviderId,
        );

        expect(viewModel.requiresResumedSelectedThread, isTrue);
        expect(viewModel.sessionId, 'thread-1');
      },
    );

    test(
      'failed resume ends pending live turn so composer can recover',
      () async {
        final provider = _FakeAgentProvider(
          failResume: true,
          historySnapshotsByThread: <String, AgentThreadHistorySnapshot>{
            'thread-1': _historySnapshot(
              threadId: 'thread-1',
              userText: 'history',
            ),
          },
        );
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.switchThread(_thread());
        await viewModel.sendMessage('try continue');

        expect(viewModel.threadOpenPhase, AgentThreadOpenPhase.openFailed);
        expect(viewModel.isTurnRunning, isFalse);
        expect(viewModel.canSubmitMessage, isFalse);
      },
    );

    group('typed UI update mapping', () {
      test('maps lifecycle and thread updates to typed regions', () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.history,
            AgentUiRegion.liveTurnBinding,
            AgentUiRegion.header,
            AgentUiRegion.composer,
            AgentUiRegion.pendingInteraction,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        );

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentThreadStatusChangedEvent(
            threadId: 'thread-1',
            status: AgentThreadRuntimeStatus.active,
          ),
        );
        await _drainTypedUiUpdate();

        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        );
      });

      test(
        'maps turn completion to immediate regions and auto-scroll',
        () async {
          final provider = _FakeAgentProvider();
          final viewModel = _createViewModel(provider);
          addTearDown(viewModel.dispose);

          await viewModel.sendMessage('hello');
          provider.emit(
            const AgentTurnCompletedEvent(
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          );
          await _drainTypedUiUpdate();

          _expectLastUiUpdate(
            viewModel,
            regions: const <AgentUiRegion>{
              AgentUiRegion.history,
              AgentUiRegion.liveTurnBinding,
              AgentUiRegion.header,
              AgentUiRegion.composer,
            },
            urgency: AgentUiUpdateUrgency.immediate,
            effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
          );
        },
      );

      test(
        'maps message and reasoning deltas to next-frame requests',
        () async {
          final provider = _FakeAgentProvider();
          final viewModel = _createViewModel(provider);
          addTearDown(viewModel.dispose);

          await viewModel.sendMessage('hello');
          provider.emit(
            const AgentMessageDeltaEvent(
              messageId: 'message-typed',
              delta: 'stream',
              role: AgentMessageRole.agent,
              phase: AgentMessagePhase.response,
              status: AgentMessageStatus.streaming,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          );
          await _drainTypedUiUpdate();

          var request = viewModel.debugLastUiUpdateRequest;
          expect(request, isNotNull);
          expect(request!.urgency, AgentUiUpdateUrgency.nextFrame);
          expect(
            request.regions,
            containsAll(const <AgentUiRegion>{AgentUiRegion.liveTurn}),
          );
          expect(
            request.regions.difference(const <AgentUiRegion>{
              AgentUiRegion.liveTurn,
              AgentUiRegion.header,
            }),
            isEmpty,
          );
          expect(request.regions, isNot(contains(AgentUiRegion.expansion)));
          expect(request.effects, const <AgentUiEffect>[
            AgentRequestAutoScroll(),
          ]);

          provider.emit(
            const AgentReasoningDeltaEvent(
              itemId: 'reasoning-typed',
              kind: AgentReasoningDeltaKind.summaryText,
              delta: 'thinking',
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          );
          await _drainTypedUiUpdate();

          request = viewModel.debugLastUiUpdateRequest;
          expect(request, isNotNull);
          expect(request!.urgency, AgentUiUpdateUrgency.nextFrame);
          expect(
            request.regions,
            containsAll(const <AgentUiRegion>{
              AgentUiRegion.liveTurn,
              AgentUiRegion.expansion,
            }),
          );
          expect(
            request.regions.difference(const <AgentUiRegion>{
              AgentUiRegion.liveTurn,
              AgentUiRegion.header,
              AgentUiRegion.expansion,
            }),
            isEmpty,
          );
          expect(request.effects, const <AgentUiEffect>[
            AgentRequestAutoScroll(),
          ]);
        },
      );

      test('maps token and context usage without conflating cadence', () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentTokenUsageEvent(
            tokenUsage: AgentTokenUsage(
              inputTokens: 10,
              outputTokens: 5,
              totalTokens: 15,
            ),
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _drainTypedUiUpdate();

        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.composer,
            AgentUiRegion.liveTurn,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        );

        provider.emit(
          const AgentContextWindowUsageEvent(
            usedTokens: 12,
            modelContextWindow: 100,
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _drainTypedUiScheduling();

        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.nextFrame,
        );
      });

      test('maps tool, diff, and plan event families', () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentPlanUpdatedEvent(
            entries: <AgentPlanEntry>[
              AgentPlanEntry(content: 'Inspect', status: 'inProgress'),
            ],
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _drainTypedUiUpdate();
        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
          urgency: AgentUiUpdateUrgency.immediate,
        );

        provider.emit(
          const AgentTurnDiffEvent(
            sessionId: 'thread-1',
            turnId: 'turn-1',
            diff: 'diff --git a/a.dart b/a.dart\n+typed',
          ),
        );
        await _drainTypedUiUpdate();
        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        );

        provider.emit(
          const AgentToolCallEvent(
            AgentToolCall(
              id: 'tool-typed',
              title: 'Run typed check',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.inProgress,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        );
        await _drainTypedUiUpdate();

        final request = viewModel.debugLastUiUpdateRequest;
        expect(request, isNotNull);
        expect(request!.urgency, AgentUiUpdateUrgency.nextFrame);
        expect(
          request.regions,
          containsAll(const <AgentUiRegion>{AgentUiRegion.liveTurn}),
        );
        expect(
          request.regions.difference(const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
          }),
          isEmpty,
        );
        expect(request.effects, const <AgentUiEffect>[
          AgentRequestAutoScroll(),
        ]);
      });

      test('maps pending interactions without auto-scroll effects', () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentPermissionRequestedEvent(
            AgentPermissionRequest(
              id: 'permission-typed',
              title: 'Run command',
              kind: AgentPermissionKind.commandExecution,
              sessionId: 'thread-1',
              turnId: 'turn-1',
            ),
          ),
        );
        await _drainTypedUiUpdate();

        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.pendingInteraction,
          },
          urgency: AgentUiUpdateUrgency.immediate,
        );
      });

      test('maps model, system, and error events independently', () async {
        final provider = _FakeAgentProvider();
        final viewModel = _createViewModel(provider);
        addTearDown(viewModel.dispose);

        await viewModel.sendMessage('hello');
        provider.emit(
          const AgentModelReroutedEvent(
            threadId: 'thread-1',
            turnId: 'turn-1',
            fromModel: 'model-a',
            toModel: 'model-b',
            reason: 'policy',
          ),
        );
        await _drainTypedUiUpdate();
        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        );

        provider.emit(
          const AgentSystemItemEvent(
            entry: AgentHistoryEventEntry(
              id: 'system-typed',
              kind: AgentHistoryEventKind.system,
              title: 'Typed system item',
            ),
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _drainTypedUiUpdate();
        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        );

        provider.emit(
          const AgentErrorEvent(
            message: 'Typed provider error',
            sessionId: 'thread-1',
            turnId: 'turn-1',
          ),
        );
        await _drainTypedUiUpdate();
        _expectLastUiUpdate(
          viewModel,
          regions: const <AgentUiRegion>{
            AgentUiRegion.history,
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        );
      });
    });
  });
}

Future<void> _drainTypedUiUpdate() async {
  await _drainTypedUiScheduling();
  for (final scheduler in _uiFrameSchedulers) {
    scheduler.drainFrames();
  }
  await _drainTypedUiScheduling();
}

Future<void> _drainTypedUiScheduling() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void _expectLastUiUpdate(
  AgentConversationViewModel viewModel, {
  required Set<AgentUiRegion> regions,
  required AgentUiUpdateUrgency urgency,
  List<AgentUiEffect> effects = const <AgentUiEffect>[],
}) {
  expect(
    viewModel.debugLastUiUpdateRequest,
    AgentUiUpdateRequest(regions: regions, urgency: urgency, effects: effects),
  );
}

AgentConversationViewModel _createViewModel(
  _FakeAgentProvider provider, {
  AgentModelCatalogRepository? modelCatalogRepository,
  AgentConversationModeController? conversationModeController,
  void Function()? onTurnCompleted,
  void Function(AgentAttentionSignal signal)? onAttention,
}) {
  final controller = ActiveAgentProviderController(
    providerFactory: _FakeAgentProviderFactory(provider),
    configStore: MemoryAgentProviderConfigStore(),
    modelCatalogRepository: modelCatalogRepository,
  );
  addTearDown(controller.dispose);
  final viewModel = AgentConversationViewModel(
    providerController: controller,
    conversationModeController: conversationModeController,
    onTurnCompleted: onTurnCompleted,
    onAttention: onAttention,
    uiFrameScheduler: _createUiFrameScheduler(),
  );
  viewModel.updateWorkspace(projectPath: '/repo', contextFilePath: null);
  return viewModel;
}

FakeAgentFrameScheduler _createUiFrameScheduler() {
  final scheduler = FakeAgentFrameScheduler();
  _uiFrameSchedulers.add(scheduler);
  return scheduler;
}

AgentThreadSummary _thread({
  String id = 'thread-1',
  String title = 'Thread one',
  AgentThreadRuntimeStatus status = AgentThreadRuntimeStatus.idle,
  bool waitingOnApproval = false,
  bool waitingOnUserInput = false,
}) {
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: title,
    sessionPath: '/repo/$id.jsonl',
    preview: title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: status,
    waitingOnApproval: waitingOnApproval,
    waitingOnUserInput: waitingOnUserInput,
  );
}

AgentThreadHistorySnapshot _historySnapshot({
  required String threadId,
  required String userText,
  String agentText = 'Historical answer',
}) {
  return AgentThreadHistorySnapshot(
    threadId: threadId,
    turns: <AgentHistoryTurn>[
      AgentHistoryTurn(
        id: '$threadId-turn-1',
        entries: <AgentHistoryEntry>[
          AgentHistoryMessageEntry(
            id: '$threadId-user-1',
            role: AgentMessageRole.user,
            text: userText,
          ),
          AgentHistoryMessageEntry(
            id: '$threadId-agent-1',
            role: AgentMessageRole.agent,
            text: agentText,
          ),
          AgentHistoryToolEntry(
            toolCall: AgentToolCall(
              id: '$threadId-tool-1',
              title: 'Run tests',
              kind: AgentToolKind.execute,
              status: AgentToolStatus.completed,
              content: 'flutter test',
            ),
          ),
          const AgentHistoryEventEntry(
            id: 'event-1',
            kind: AgentHistoryEventKind.search,
            title: 'Tool search',
            description: 'read_package_uris',
          ),
        ],
      ),
    ],
  );
}

class _FakeAgentProviderFactory implements AgentProviderFactory {
  const _FakeAgentProviderFactory(this.provider);

  final _FakeAgentProvider provider;

  @override
  AgentProvider create(AgentProviderConfig config) => provider;
}

class _MultiFakeAgentProviderFactory implements AgentProviderFactory {
  _MultiFakeAgentProviderFactory(this.providers);

  final Map<String, AgentProvider> providers;
  final List<String> createdProviderIds = <String>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    createdProviderIds.add(config.id);
    return providers[config.id]!;
  }
}

class _DelayedAgentProviderConfigStore implements AgentProviderConfigStore {
  _DelayedAgentProviderConfigStore(this.settingsCompleter);

  final Completer<AgentProviderSettings> settingsCompleter;
  AgentProviderSettings? savedSettings;

  @override
  Future<AgentProviderSettings> load() async {
    return savedSettings ?? await settingsCompleter.future;
  }

  @override
  Future<void> save(AgentProviderSettings settings) async {
    savedSettings = settings;
  }
}

class _FakeAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider, AgentRefreshableModelCatalogProvider {
  _FakeAgentProvider({
    this.failHistory = false,
    this.failResume = false,
    this.sendError,
    this.startSessionTitle,
    this.resumeSessionTitle,
    this.emitSessionStartedDuringSend = false,
    this.sendResult,
    this.providerConfig = AgentProviderConfig.defaultCodex,
    this.availableModels = const AgentModelList(models: <AgentModelInfo>[]),
    this.emitModelEventOnRefresh = false,
    this.eventCancellationGate,
    AgentProviderCapabilities? declaredCapabilities,
    AgentThreadHistorySnapshot? historySnapshot,
    Map<String, AgentThreadHistorySnapshot> historySnapshotsByThread =
        const <String, AgentThreadHistorySnapshot>{},
    Map<String, Completer<AgentSession>> resumeCompleters =
        const <String, Completer<AgentSession>>{},
    Map<String, Completer<AgentThreadHistorySnapshot>> historyCompleters =
        const <String, Completer<AgentThreadHistorySnapshot>>{},
  }) : declaredCapabilities =
           declaredCapabilities ??
           AgentProviderCapabilities.codexAppServer.copyWith(
             canForkThreadAtTurn: true,
           ),
       _defaultHistorySnapshot =
           historySnapshot ??
           const AgentThreadHistorySnapshot(
             threadId: 'thread-1',
             turns: <AgentHistoryTurn>[],
           ),
       _historySnapshotsByThread = Map<String, AgentThreadHistorySnapshot>.from(
         historySnapshotsByThread,
       ),
       _resumeCompleters = Map<String, Completer<AgentSession>>.from(
         resumeCompleters,
       ),
       _historyCompleters =
           Map<String, Completer<AgentThreadHistorySnapshot>>.from(
             historyCompleters,
           );

  final bool failHistory;
  final bool failResume;
  final Object? sendError;
  final String? startSessionTitle;
  final String? resumeSessionTitle;
  final bool emitSessionStartedDuringSend;
  final Completer<AgentTurn>? sendResult;
  final AgentProviderConfig providerConfig;
  final AgentModelList availableModels;
  final bool emitModelEventOnRefresh;
  final Future<void>? eventCancellationGate;
  final AgentProviderCapabilities declaredCapabilities;
  final AgentThreadHistorySnapshot _defaultHistorySnapshot;
  final Map<String, AgentThreadHistorySnapshot> _historySnapshotsByThread;
  final Map<String, Completer<AgentSession>> _resumeCompleters;
  final Map<String, Completer<AgentThreadHistorySnapshot>> _historyCompleters;
  final List<String> calls = <String>[];
  final List<String?> readSessionPaths = <String?>[];
  final List<String?> readProjectPaths = <String?>[];
  final List<String> unsubscribedThreads = <String>[];
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  AgentModelSelection? lastModelSelection;
  bool disposed = false;
  int initializeCalls = 0;
  int listModelsCalls = 0;
  int refreshModelsCalls = 0;
  final List<AgentTurnConfiguration> turnConfigurations =
      <AgentTurnConfiguration>[];

  @override
  AgentProviderConfig get config => providerConfig;

  @override
  AgentProviderCapabilities get capabilities => declaredCapabilities;

  @override
  Stream<AgentEvent> get events {
    final gate = eventCancellationGate;
    return gate == null
        ? _events.stream
        : _DelayedCancelStream<AgentEvent>(_events.stream, gate);
  }

  @override
  Future<void> initialize() async {
    initializeCalls += 1;
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    listModelsCalls += 1;
    return availableModels;
  }

  @override
  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    refreshModelsCalls += 1;
    if (emitModelEventOnRefresh) {
      _events.add(AgentModelListEvent(availableModels));
    }
    return availableModels;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {
    lastModelSelection = selection;
  }

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {}

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    calls.add('read:$threadId');
    readSessionPaths.add(sessionPath);
    readProjectPaths.add(projectPath);
    if (failHistory) {
      throw StateError('history failed');
    }
    final completer = _historyCompleters[threadId];
    if (completer != null) {
      return completer.future;
    }
    return _historySnapshotsByThread[threadId] ?? _defaultHistorySnapshot;
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    calls.add('unsubscribe:$threadId');
    unsubscribedThreads.add(threadId);
  }

  @override
  Future<AgentSession> startSession({required AgentContext context, AgentPermissionSelection? permissionSelection}) async {
    calls.add('start');
    return AgentSession(
      id: 'thread-1',
      providerId: providerConfig.id,
      title: startSessionTitle,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionSelection? permissionSelection,
  }) async {
    calls.add('resume:$sessionId');
    if (failResume) {
      throw StateError('resume failed');
    }
    final completer = _resumeCompleters[sessionId];
    if (completer != null) {
      return completer.future;
    }
    return AgentSession(
      id: sessionId,
      providerId: providerConfig.id,
      title: resumeSessionTitle,
    );
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    turnConfigurations.add(configuration);
    if (emitSessionStartedDuringSend) {
      emit(AgentSessionStartedEvent(session));
      await Future<void>.delayed(Duration.zero);
    }
    final error = sendError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    final resolved =
        inputs ?? <AgentUserInput>[AgentUserInput.text(message ?? '')];
    calls.add('send:${session.id}');
    for (final input in resolved) {
      if (input is AgentLocalImageUserInput) {
        calls.add('image:${input.path}');
      }
    }
    final pendingResult = sendResult;
    if (pendingResult != null) {
      return pendingResult.future;
    }
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    calls.add('steer:${session.id}');
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    calls.add('cancel:${turn.sessionId}:${turn.id}');
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionSelection? permissionSelection,
  }) async {
    final boundaryLabel = switch (boundary) {
      AgentForkCurrentHead() => 'head',
      AgentForkThroughTurn(:final turnId) => 'through:$turnId',
    };
    calls.add('fork:$threadId:$boundaryLabel');
    return super.forkThread(
      threadId: threadId,
      context: context,
      boundary: boundary,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    calls.add('compact:$threadId');
    return super.compactThread(threadId);
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    calls.add('rename:$threadId:$name');
    await super.renameThread(threadId: threadId, name: name);
    _events.add(
      AgentThreadNameUpdatedEvent(threadId: threadId, threadName: name),
    );
  }

  @override
  Future<void> dispose() async {
    if (disposed) {
      return;
    }
    disposed = true;
    await _events.close();
  }

  void emit(AgentEvent event) {
    _events.add(event);
  }
}

class _ModeFakeAgentProvider extends _FakeAgentProvider
    implements AgentConversationModeCatalogProvider {
  _ModeFakeAgentProvider({
    super.sendError,
    super.availableModels,
    super.historySnapshotsByThread,
    super.historyCompleters,
    super.emitSessionStartedDuringSend,
    super.sendResult,
  });

  int listConversationModesCalls = 0;

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    listConversationModesCalls += 1;
    return AgentConversationModeCatalog(
      presets: const <AgentConversationModePreset>[
        AgentConversationModePreset(
          id: AgentConversationModeId.defaultMode,
          displayName: 'Default',
        ),
        AgentConversationModePreset(
          id: AgentConversationModeId.plan,
          displayName: 'Plan',
          suggestedReasoningEffort: 'medium',
        ),
      ],
    );
  }
}

Future<void> _emitCompletedPlan(
  _FakeAgentProvider provider, {
  AgentHistoryTurnStatus status = AgentHistoryTurnStatus.completed,
}) async {
  provider.emit(
    const AgentMessageDeltaEvent(
      messageId: 'plan-final',
      delta: '# Final plan\n\n- Implement the change',
      role: AgentMessageRole.agent,
      kind: AgentMessageKind.plan,
      status: AgentMessageStatus.completed,
      sessionId: 'thread-1',
      turnId: 'turn-1',
    ),
  );
  provider.emit(
    AgentTurnCompletedEvent(
      sessionId: 'thread-1',
      turnId: 'turn-1',
      status: status,
    ),
  );
  await _drainTypedUiUpdate();
}

const AgentModelList _conversationModeModels = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'gpt-5.6',
      model: 'gpt-5.6',
      displayName: 'GPT-5.6',
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'medium'),
        AgentModelReasoningEffort(effort: 'high'),
      ],
      defaultReasoningEffort: 'high',
      isDefault: true,
    ),
  ],
);

class _ConversationModelCatalogStore implements AgentModelCatalogCacheStore {
  List<AgentModelCatalogSnapshot> snapshots =
      const <AgentModelCatalogSnapshot>[];
  int saveCalls = 0;

  @override
  Future<List<AgentModelCatalogSnapshot>> load() async => snapshots;

  @override
  Future<void> save(List<AgentModelCatalogSnapshot> snapshots) async {
    saveCalls += 1;
    this.snapshots = List<AgentModelCatalogSnapshot>.from(snapshots);
  }
}

Map<String, Object?> _structuredLogContext(
  LogRecord record, {
  required String prefix,
}) {
  return jsonDecode(record.message.substring(prefix.length))
      as Map<String, Object?>;
}

class _RuntimeScopedFakeAgentProvider extends _FakeAgentProvider
    implements AgentRuntimeScopeProvider {
  _RuntimeScopedFakeAgentProvider({
    required this.runtimeScope,
    required super.historySnapshotsByThread,
  });

  @override
  AgentRuntimeScope? runtimeScope;
}

class _DelayedCancelStream<T> extends Stream<T> {
  const _DelayedCancelStream(this._delegate, this._cancellationGate);

  final Stream<T> _delegate;
  final Future<void> _cancellationGate;

  @override
  StreamSubscription<T> listen(
    void Function(T event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    return _DelayedCancelSubscription<T>(
      _delegate.listen(
        onData,
        onError: onError,
        onDone: onDone,
        cancelOnError: cancelOnError,
      ),
      _cancellationGate,
    );
  }
}

class _DelayedCancelSubscription<T> implements StreamSubscription<T> {
  _DelayedCancelSubscription(this._delegate, this._cancellationGate);

  final StreamSubscription<T> _delegate;
  final Future<void> _cancellationGate;
  Future<void>? _cancelFuture;

  @override
  Future<void> cancel() => _cancelFuture ??= _cancel();

  Future<void> _cancel() async {
    await _delegate.cancel();
    await _cancellationGate;
  }

  @override
  void onData(void Function(T data)? handleData) =>
      _delegate.onData(handleData);

  @override
  void onError(Function? handleError) => _delegate.onError(handleError);

  @override
  void onDone(void Function()? handleDone) => _delegate.onDone(handleDone);

  @override
  void pause([Future<void>? resumeSignal]) => _delegate.pause(resumeSignal);

  @override
  void resume() => _delegate.resume();

  @override
  bool get isPaused => _delegate.isPaused;

  @override
  Future<E> asFuture<E>([E? futureValue]) => _delegate.asFuture<E>(futureValue);
}

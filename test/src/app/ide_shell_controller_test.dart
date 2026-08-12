import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_terminal_signal.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/usage_statistics/application/query_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/query_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';

import '../testing/agent_event_storm_fixture.dart';
import '../testing/agent_provider_stub_base.dart';
import '../testing/fake_agent_frame_scheduler.dart';

final List<FakeAgentFrameScheduler> _uiFrameSchedulers =
    <FakeAgentFrameScheduler>[];

void main() {
  final tempDirectories = <Directory>[];

  setUp(_uiFrameSchedulers.clear);

  tearDown(() {
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  test('composes both usage controllers from the shared query service', () {
    final shell = IdeShellController(
      agentUiFrameSchedulerFactory: _createUiFrameScheduler,
      directoryPicker: () async => null,
      sessionStore: const CallbackIdeSessionStore(
        loadJson: _loadEmptySession,
        saveJson: _saveDiscardedSession,
      ),
      agentProviderFactory:
          _RecordingAgentProviderFactory(<String, _ProviderBackend>{
            defaultAgentProviderId: _ProviderBackend(
              config: AgentProviderConfig.defaultCodex,
              threadHistories: const <String, AgentThreadHistorySnapshot>{},
              threadPages: const <AgentThreadPage>[],
            ),
          }),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(
        const AgentProviderSettings(
          providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
          activeProviderId: defaultAgentProviderId,
        ),
      ),
    );
    addTearDown(shell.dispose);

    expect(
      shell.usageStatisticsController.repository,
      isA<QueryUsageStatisticsRepository>(),
    );
    expect(
      shell.agentUsagePanelController.repository,
      isA<QueryAgentUsagePanelRepository>(),
    );
  });

  test(
    'provider settings changes resync usage directory without loading siblings',
    () async {
      final usageRepository = _DirectoryTrackingUsageRepository();
      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => null,
        sessionStore: const CallbackIdeSessionStore(
          loadJson: _loadEmptySession,
          saveJson: _saveDiscardedSession,
        ),
        agentProviderFactory:
            _RecordingAgentProviderFactory(<String, _ProviderBackend>{
              defaultAgentProviderId: _ProviderBackend(
                config: AgentProviderConfig.defaultCodex,
                threadHistories: const <String, AgentThreadHistorySnapshot>{},
                threadPages: const <AgentThreadPage>[],
              ),
            }),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        usageStatistics: IdeShellUsageStatisticsDependencies(
          partitionStore: MemoryUsageStatisticsPartitionStore(),
          agentUsagePanelRepository: usageRepository,
        ),
      );
      addTearDown(shell.dispose);

      await shell.agentUsagePanelController.refresh(forceRefresh: false);
      expect(usageRepository.loadedProviderIds, <String>['codex']);

      usageRepository.directory = const <AgentUsagePanelProvider>[
        AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
        AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
        AgentUsagePanelProvider(
          providerId: 'claude_code',
          providerName: 'Claude',
        ),
      ];
      await shell.agentProviderController.updateProviderConfig(
        AgentProviderConfig.defaultClaudeCode,
      );
      await _flushAsync();

      expect(
        shell.agentUsagePanelController.providers.map(
          (state) => state.provider.providerId,
        ),
        <String>['codex', 'grok', 'claude_code'],
      );
      expect(usageRepository.loadedProviderIds, <String>['codex']);
    },
  );

  test(
    'keeps a running thread alive when switching to another thread',
    () async {
      final directory = Directory.systemTemp.createTempSync('zeta_shell_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello');

      final codexBackend = _ProviderBackend(
        config: AgentProviderConfig.defaultCodex,
        threadHistories: const <String, AgentThreadHistorySnapshot>{},
        completeTurns: false,
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              _thread(
                id: 'thread-a',
                providerId: defaultAgentProviderId,
                projectPath: directory.path,
              ),
              _thread(
                id: 'thread-b',
                providerId: defaultAgentProviderId,
                projectPath: directory.path,
                updatedAt: DateTime.utc(2026, 7, 15, 12),
              ),
            ],
            nextCursor: null,
          ),
        ],
      );

      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => directory.path,
        sessionStore: const CallbackIdeSessionStore(
          loadJson: _loadEmptySession,
          saveJson: _saveDiscardedSession,
        ),
        agentProviderFactory: _RecordingAgentProviderFactory(
          <String, _ProviderBackend>{defaultAgentProviderId: codexBackend},
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
            activeProviderId: defaultAgentProviderId,
          ),
        ),
      );
      addTearDown(shell.dispose);

      await shell.openProject();
      await _flushAsync();

      final state = shell.projectThreadStateFor(directory.path);
      final threadA = state.threads.firstWhere(
        (thread) => thread.id == 'thread-a',
      );
      final threadB = state.threads.firstWhere(
        (thread) => thread.id == 'thread-b',
      );

      await shell.selectProjectThread(directory.path, threadA);
      await shell.selectedAgentViewModel.sendMessage('keep running');
      await _flushAsync();

      expect(
        shell.projectThreadStateFor(directory.path).runningThreadIds,
        contains('thread-a'),
      );

      await shell.selectProjectThread(directory.path, threadB);
      await _flushAsync();

      final nextState = shell.projectThreadStateFor(directory.path);
      expect(nextState.selectedThreadId, 'thread-b');
      expect(nextState.runningThreadIds, contains('thread-a'));
      expect(codexBackend.anyUnsubscribed('thread-a'), isFalse);
      expect(
        codexBackend.instances,
        hasLength(2),
        reason:
            '同一 shell 下不同 thread 各自独立一个 session scope 实例（S4 翻开关后），不再复用同一个运行时',
      );
    },
  );

  test(
    'activates the provider thread targeted by a system notification',
    () async {
      final directory = Directory.systemTemp.createTempSync('zeta_shell_');
      tempDirectories.add(directory);
      final harness = await _openShellWithSelectedThread(
        directory: directory,
        threadIds: const <String>['thread-a', 'thread-b'],
        selectedThreadId: 'thread-a',
      );
      addTearDown(harness.shell.dispose);

      final activated = await harness.shell.activateAgentThread(
        providerId: defaultAgentProviderId,
        threadId: 'thread-b',
      );
      final missing = await harness.shell.activateAgentThread(
        providerId: defaultAgentProviderId,
        threadId: 'missing-thread',
      );

      expect(activated, isTrue);
      expect(missing, isFalse);
      expect(harness.shell.activeProjectPath, directory.path);
      expect(harness.shell.selectedAgentViewModel.sessionId, 'thread-b');
    },
  );

  test('fork 将 Provider 新建的 thread 登记并选中，后续操作只作用于新 thread', () async {
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final harness = await _openShellWithSelectedThread(
      directory: directory,
      threadIds: const <String>['thread-a'],
      selectedThreadId: 'thread-a',
    );
    final shell = harness.shell;
    final backend = harness.backend;
    addTearDown(shell.dispose);
    final sourceEntry = shell.agentWorkspaceController.selectedEntry!;

    final session = await sourceEntry.viewModel.forkCurrentThread();
    await _flushAsync();

    expect(session?.id, 'forked-thread-a');
    expect(
      shell.projectThreadStateFor(directory.path).selectedThreadId,
      'forked-thread-a',
    );
    final selectedEntry = shell.agentWorkspaceController.selectedEntry!;
    expect(selectedEntry, isNot(same(sourceEntry)));
    expect(selectedEntry.binding.threadId, 'forked-thread-a');
    expect(sourceEntry.binding.threadId, 'thread-a');
    expect(backend.instances, hasLength(1));
    expect(sourceEntry.binding.hasRuntime, isFalse);

    await selectedEntry.viewModel.renameCurrentThread('Fork renamed');
    expect(
      backend.instances.single.renamedThreads,
      contains((threadId: 'forked-thread-a', name: 'Fork renamed')),
    );

    await selectedEntry.viewModel.sendMessage('continue on fork');
    await _flushAsync();
    expect(backend.instances, hasLength(2));
    expect(
      backend.instances.last.sentMessages,
      contains((sessionId: 'forked-thread-a', message: 'continue on fork')),
    );
    expect(sourceEntry.binding.hasRuntime, isFalse);
  });

  test('编辑后重试登记并选中 fork thread，再由新 Binding 发送', () async {
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final harness = await _openShellWithSelectedThread(
      directory: directory,
      threadIds: const <String>['thread-a'],
      selectedThreadId: 'thread-a',
      completeTurns: true,
      canForkThreadAtTurn: true,
      threadHistories: const <String, AgentThreadHistorySnapshot>{
        'thread-a': AgentThreadHistorySnapshot(
          threadId: 'thread-a',
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
        'forked-thread-a': AgentThreadHistorySnapshot(
          threadId: 'forked-thread-a',
          turns: <AgentHistoryTurn>[],
        ),
      },
    );
    final shell = harness.shell;
    final backend = harness.backend;
    addTearDown(shell.dispose);
    final sourceEntry = shell.agentWorkspaceController.selectedEntry!;
    expect(sourceEntry.viewModel.canEditLastUserMessage, isTrue);

    await sourceEntry.viewModel.editLastUserMessageAndRetry('new prompt');
    await _flushAsync();

    final selectedEntry = shell.agentWorkspaceController.selectedEntry!;
    expect(selectedEntry, isNot(same(sourceEntry)));
    expect(selectedEntry.binding.threadId, 'forked-thread-a');
    expect(sourceEntry.binding.threadId, 'thread-a');
    expect(
      (backend.instances.first.forkBoundaries.single as AgentForkThroughTurn)
          .turnId,
      'turn-1',
    );
    expect(backend.instances, hasLength(2));
    expect(
      backend.instances.last.sentMessages,
      <({String sessionId, String? message})>[
        (sessionId: 'forked-thread-a', message: 'new prompt'),
      ],
    );
    final forkedThread = shell
        .projectThreadStateFor(directory.path)
        .threads
        .firstWhere((thread) => thread.id == 'forked-thread-a');
    expect(forkedThread.preview, 'new prompt');
  });

  test(
    'forwards typed terminal identity from the selected Agent turn',
    () async {
      // Arrange
      final terminalSignals = <AgentTurnTerminalSignal>[];
      final attentions = <AgentWorkspaceAttention>[];
      final backend = _ProviderBackend(
        config: AgentProviderConfig.defaultCodex,
        threadHistories: const <String, AgentThreadHistorySnapshot>{},
        completeTurns: true,
        threadPages: <AgentThreadPage>[],
      );
      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => null,
        sessionStore: const CallbackIdeSessionStore(
          loadJson: _loadEmptySession,
          saveJson: _saveDiscardedSession,
        ),
        agentProviderFactory: _RecordingAgentProviderFactory(
          <String, _ProviderBackend>{defaultAgentProviderId: backend},
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
            activeProviderId: defaultAgentProviderId,
          ),
        ),
        onAgentTurnTerminal: terminalSignals.add,
        onAgentAttention: attentions.add,
      );
      addTearDown(shell.dispose);
      await _flushAsync();

      // Act
      await shell.selectedAgentViewModel.sendMessage('run once');
      await _flushAsync();

      // Assert
      expect(terminalSignals, hasLength(1));
      expect(terminalSignals.single.providerId, defaultAgentProviderId);
      expect(terminalSignals.single.threadId, isNotEmpty);
      expect(terminalSignals.single.turnId, isNotEmpty);
      expect(attentions, hasLength(1));
      expect(attentions.single.signal.kind, AgentAttentionKind.turnCompleted);
      expect(attentions.single.signal.phase, AgentAttentionPhase.raised);
      expect(attentions.single.providerId, defaultAgentProviderId);
      expect(attentions.single.threadId, isNotEmpty);
    },
  );

  test(
    'streaming content updates locally without notifying or saving Shell',
    () async {
      // Arrange
      final directory = Directory.systemTemp.createTempSync('zeta_shell_');
      tempDirectories.add(directory);
      final harness = await _openShellWithSelectedThread(
        directory: directory,
        threadIds: const <String>['thread-a'],
        selectedThreadId: 'thread-a',
        startSessionRuntime: true,
      );
      final shell = harness.shell;
      final provider = harness.provider;
      final viewModel = shell.selectedAgentViewModel;
      addTearDown(shell.dispose);

      provider.emit(
        const AgentTurnStartedEvent(
          AgentTurn(id: 'turn-a', sessionId: 'thread-a'),
        ),
      );
      await _flushAsync();
      await shell.saveNow();
      harness.sessionSaves.reset();

      var shellNotifications = 0;
      void handleShellChanged() {
        shellNotifications += 1;
      }

      shell.addListener(handleShellChanged);
      addTearDown(() => shell.removeListener(handleShellChanged));

      // Act
      provider.emitAll(const <AgentEvent>[
        AgentMessageDeltaEvent(
          messageId: 'message-stream',
          delta: 'A',
          role: AgentMessageRole.agent,
          sessionId: 'thread-a',
          turnId: 'turn-a',
        ),
        AgentMessageDeltaEvent(
          messageId: 'message-stream',
          delta: 'B',
          role: AgentMessageRole.agent,
          sessionId: 'thread-a',
          turnId: 'turn-a',
        ),
        AgentMessageDeltaEvent(
          messageId: 'message-stream',
          delta: 'C',
          role: AgentMessageRole.agent,
          sessionId: 'thread-a',
          turnId: 'turn-a',
        ),
        AgentReasoningDeltaEvent(
          itemId: 'reasoning-stream',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'think ',
          sessionId: 'thread-a',
          turnId: 'turn-a',
        ),
        AgentReasoningDeltaEvent(
          itemId: 'reasoning-stream',
          kind: AgentReasoningDeltaKind.summaryText,
          delta: 'more',
          sessionId: 'thread-a',
          turnId: 'turn-a',
        ),
        AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-stream',
            title: 'Inspect',
            status: AgentToolStatus.inProgress,
            content: 'step 1',
            sessionId: 'thread-a',
            turnId: 'turn-a',
          ),
        ),
        AgentToolCallEvent(
          AgentToolCall(
            id: 'tool-stream',
            title: 'Inspect',
            status: AgentToolStatus.inProgress,
            content: 'step 2',
            sessionId: 'thread-a',
            turnId: 'turn-a',
          ),
        ),
      ]);
      await _flushAsync();
      await Future<void>.delayed(const Duration(milliseconds: 350));
      await _flushAsync();

      // Assert
      expect(
        viewModel.messages
            .singleWhere((message) => message.id == 'message-stream')
            .text,
        'ABC',
      );
      expect(
        viewModel.toolCalls
            .singleWhere((tool) => tool.id == 'reasoning-stream')
            .content,
        'think more',
      );
      final tool = viewModel.toolCalls.singleWhere(
        (tool) => tool.id == 'tool-stream',
      );
      expect(tool.status, AgentToolStatus.inProgress);
      expect(tool.content, 'step 2');
      expect(shellNotifications, 0);
      expect(harness.sessionSaves.saveCount, 0);
    },
  );

  test('fixed storm only notifies Shell for thread snapshot changes', () async {
    // Arrange
    final fixture = AgentEventStormFixture();
    final directory = Directory.systemTemp.createTempSync('zeta_shell_storm_');
    tempDirectories.add(directory);
    final harness = await _openShellWithSelectedThread(
      directory: directory,
      threadIds: <String>[fixture.sessionId],
      selectedThreadId: fixture.sessionId,
      startSessionRuntime: true,
    );
    final shell = harness.shell;
    final provider = harness.provider;
    final viewModel = shell.selectedAgentViewModel;
    addTearDown(shell.dispose);
    await shell.saveNow();
    harness.sessionSaves.reset();

    var shellNotifications = 0;
    void handleShellChanged() {
      shellNotifications += 1;
    }

    shell.addListener(handleShellChanged);
    addTearDown(() => shell.removeListener(handleShellChanged));
    final beforeBuffer = viewModel.eventCoalescingBufferDiagnostics!;
    final beforeUi = viewModel.uiStateDiagnostics;

    // Act
    provider.emitAll(fixture.events);
    var drained = false;
    for (var attempt = 0; attempt < 200; attempt += 1) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
      await _flushAsync();
      final buffer = viewModel.eventCoalescingBufferDiagnostics;
      final scheduler = viewModel.eventDispatcherDiagnostics;
      if (buffer != null &&
          buffer.receivedEvents - beforeBuffer.receivedEvents ==
              fixture.expectedInputEventCount &&
          buffer.currentPendingKeys == 0 &&
          scheduler?.currentQueueDepth == 0 &&
          !viewModel.isTurnRunning) {
        drained = true;
        break;
      }
    }
    expect(drained, isTrue, reason: 'Agent event storm did not drain');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    await _flushAsync();

    // Assert
    final afterUi = viewModel.uiStateDiagnostics;
    final uiStatePublishes = afterUi.publishCount - beforeUi.publishCount;
    final messageCharacters = viewModel.timelineEntries
        .whereType<AgentMessageTimelineEntry>()
        .where((entry) => entry.message.role == AgentMessageRole.agent)
        .fold<int>(0, (sum, entry) => sum + entry.message.text.length);
    final reasoningCharacters = viewModel.timelineEntries
        .whereType<AgentToolTimelineEntry>()
        .where((entry) => entry.toolCall.kind == AgentToolKind.think)
        .fold<int>(
          0,
          (sum, entry) => sum + (entry.toolCall.content?.length ?? 0),
        );

    expect(messageCharacters, fixture.expectedMessageCharacters);
    expect(reasoningCharacters, fixture.expectedReasoningCharacters);
    expect(viewModel.permissionRequests, isEmpty);
    expect(viewModel.isTurnRunning, isFalse);
    expect(
      viewModel.visibleHistoryTurns.map((turn) => turn.id),
      contains(fixture.turnId),
    );
    expect(shellNotifications, greaterThan(0));
    expect(shellNotifications, lessThan(uiStatePublishes));

    debugPrint(
      'agent-event-shell-phase1 '
      'uiStatePublish=$uiStatePublishes '
      'shellNotify=$shellNotifications',
    );
  });

  test('thread snapshot summary changes still notify Shell', () async {
    // Arrange
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final harness = await _openShellWithSelectedThread(
      directory: directory,
      threadIds: const <String>['thread-a'],
      selectedThreadId: 'thread-a',
      startSessionRuntime: true,
    );
    final shell = harness.shell;
    final provider = harness.provider;
    addTearDown(shell.dispose);
    await shell.saveNow();

    var shellNotifications = 0;
    void handleShellChanged() {
      shellNotifications += 1;
    }

    shell.addListener(handleShellChanged);
    addTearDown(() => shell.removeListener(handleShellChanged));

    // Act + Assert: title
    provider.emit(
      const AgentThreadNameUpdatedEvent(
        threadId: 'thread-a',
        threadName: 'Renamed thread',
      ),
    );
    await _flushAsync();
    expect(
      shell.selectedAgentViewModel.threadSnapshot.threadTitle,
      'Renamed thread',
    );
    expect(shellNotifications, greaterThan(0));

    // Act + Assert: turn running
    shellNotifications = 0;
    provider.emit(
      const AgentTurnStartedEvent(
        AgentTurn(id: 'turn-a', sessionId: 'thread-a'),
      ),
    );
    await _flushAsync();
    expect(shell.selectedAgentViewModel.threadSnapshot.isTurnRunning, isTrue);
    expect(shellNotifications, greaterThan(0));

    // Act + Assert: turn idle
    shellNotifications = 0;
    provider.emit(
      const AgentTurnCompletedEvent(sessionId: 'thread-a', turnId: 'turn-a'),
    );
    await _flushAsync();
    expect(shell.selectedAgentViewModel.threadSnapshot.isTurnRunning, isFalse);
    expect(shellNotifications, greaterThan(0));

    // Act + Assert: waiting on approval
    shellNotifications = 0;
    provider.emit(
      const AgentThreadStatusChangedEvent(
        threadId: 'thread-a',
        status: AgentThreadRuntimeStatus.active,
        waitingOnApproval: true,
      ),
    );
    await _flushAsync();
    expect(
      shell.selectedAgentViewModel.threadSnapshot.waitingOnApproval,
      isTrue,
    );
    expect(
      shell.selectedAgentViewModel.threadSnapshot.waitingOnUserInput,
      isFalse,
    );
    expect(shellNotifications, greaterThan(0));

    // Act + Assert: waiting on user input
    shellNotifications = 0;
    provider.emit(
      const AgentThreadStatusChangedEvent(
        threadId: 'thread-a',
        status: AgentThreadRuntimeStatus.active,
        waitingOnUserInput: true,
      ),
    );
    await _flushAsync();
    expect(
      shell.selectedAgentViewModel.threadSnapshot.waitingOnApproval,
      isFalse,
    );
    expect(
      shell.selectedAgentViewModel.threadSnapshot.waitingOnUserInput,
      isTrue,
    );
    expect(shellNotifications, greaterThan(0));

    // Act + Assert: runtime idle clears both waiting flags
    shellNotifications = 0;
    provider.emit(
      const AgentThreadStatusChangedEvent(
        threadId: 'thread-a',
        status: AgentThreadRuntimeStatus.idle,
      ),
    );
    await _flushAsync();
    final idleSnapshot = shell.selectedAgentViewModel.threadSnapshot;
    expect(idleSnapshot.runtimeStatus, AgentThreadRuntimeStatus.idle);
    expect(idleSnapshot.waitingOnApproval, isFalse);
    expect(idleSnapshot.waitingOnUserInput, isFalse);
    expect(shellNotifications, greaterThan(0));
  });

  test('old ViewModel updates stay isolated after thread switch', () async {
    // Arrange
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final harness = await _openShellWithSelectedThread(
      directory: directory,
      threadIds: const <String>['thread-a', 'thread-b'],
      selectedThreadId: 'thread-a',
      startSessionRuntime: true,
    );
    final shell = harness.shell;
    final provider = harness.provider;
    final oldViewModel = shell.selectedAgentViewModel;
    final oldSnapshot = oldViewModel.threadSnapshot;
    addTearDown(shell.dispose);

    final threadB = shell
        .projectThreadStateFor(directory.path)
        .threads
        .singleWhere((thread) => thread.id == 'thread-b');
    await shell.selectProjectThread(directory.path, threadB);
    await _flushAsync();
    final currentViewModel = shell.selectedAgentViewModel;
    expect(currentViewModel.sessionId, 'thread-b');
    expect(currentViewModel, isNot(same(oldViewModel)));

    await shell.saveNow();
    harness.sessionSaves.reset();
    var shellNotifications = 0;
    void handleShellChanged() {
      shellNotifications += 1;
    }

    shell.addListener(handleShellChanged);
    addTearDown(() => shell.removeListener(handleShellChanged));

    // Act
    provider.emitAll(const <AgentEvent>[
      AgentMessageDeltaEvent(
        messageId: 'old-thread-message',
        delta: 'old',
        role: AgentMessageRole.agent,
        sessionId: 'thread-a',
        turnId: 'turn-a',
      ),
      AgentMessageDeltaEvent(
        messageId: 'old-thread-message',
        delta: ' thread',
        role: AgentMessageRole.agent,
        sessionId: 'thread-a',
        turnId: 'turn-a',
      ),
    ]);
    await _flushAsync();
    await Future<void>.delayed(const Duration(milliseconds: 350));
    await _flushAsync();

    // Assert
    expect(
      oldViewModel.messages
          .singleWhere((message) => message.id == 'old-thread-message')
          .text,
      'old thread',
    );
    expect(oldViewModel.threadSnapshot, oldSnapshot);
    expect(
      currentViewModel.messages.any(
        (message) => message.id == 'old-thread-message',
      ),
      isFalse,
    );
    expect(shell.selectedAgentViewModel, same(currentViewModel));
    expect(shellNotifications, 0);
    expect(harness.sessionSaves.saveCount, 0);

    // 旧条目的摘要仍可更新项目线程列表，但不能覆盖当前选中条目的快照。
    final currentSnapshot = currentViewModel.threadSnapshot;
    provider.emit(
      const AgentThreadNameUpdatedEvent(
        threadId: 'thread-a',
        threadName: 'Renamed old thread',
      ),
    );
    await _flushAsync();

    expect(oldViewModel.threadSnapshot.threadTitle, 'Renamed old thread');
    expect(currentViewModel.threadSnapshot, currentSnapshot);
    expect(shell.selectedAgentViewModel, same(currentViewModel));
  });

  test('allows cross-provider threads to run in parallel', () async {
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    File(
      '${directory.path}${Platform.pathSeparator}sample.txt',
    ).writeAsStringSync('hello');

    final codexBackend = _ProviderBackend(
      config: AgentProviderConfig.defaultCodex,
      threadHistories: const <String, AgentThreadHistorySnapshot>{},
      completeTurns: false,
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _thread(
              id: 'codex-thread',
              providerId: defaultAgentProviderId,
              projectPath: directory.path,
            ),
          ],
          nextCursor: null,
        ),
      ],
    );
    final grokBackend = _ProviderBackend(
      config: AgentProviderConfig.defaultGrok.copyWith(enabled: true),
      threadHistories: const <String, AgentThreadHistorySnapshot>{},
      completeTurns: false,
      threadPages: <AgentThreadPage>[
        AgentThreadPage(
          threads: <AgentThreadSummary>[
            _thread(
              id: 'grok-thread',
              providerId: grokAgentProviderId,
              projectPath: directory.path,
              updatedAt: DateTime.utc(2026, 7, 15, 12),
            ),
          ],
          nextCursor: null,
        ),
      ],
    );

    final shell = IdeShellController(
      agentUiFrameSchedulerFactory: _createUiFrameScheduler,
      directoryPicker: () async => directory.path,
      sessionStore: const CallbackIdeSessionStore(
        loadJson: _loadEmptySession,
        saveJson: _saveDiscardedSession,
      ),
      agentProviderFactory: _RecordingAgentProviderFactory(
        <String, _ProviderBackend>{
          defaultAgentProviderId: codexBackend,
          grokAgentProviderId: grokBackend,
        },
      ),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultGrok.copyWith(enabled: true),
          ],
          activeProviderId: defaultAgentProviderId,
        ),
      ),
    );
    addTearDown(shell.dispose);

    await shell.openProject();
    await _flushAsync();

    final threads = shell.projectThreadStateFor(directory.path).threads;
    final codexThread = threads.firstWhere(
      (thread) => thread.id == 'codex-thread',
    );
    final grokThread = threads.firstWhere(
      (thread) => thread.id == 'grok-thread',
    );

    await shell.selectProjectThread(directory.path, codexThread);
    await shell.selectedAgentViewModel.sendMessage('run codex');
    await _flushAsync();

    await shell.selectProjectThread(directory.path, grokThread);
    await shell.selectedAgentViewModel.sendMessage('run grok');
    await _flushAsync();

    expect(
      shell.projectThreadStateFor(directory.path).runningThreadIds,
      <String>{'codex-thread', 'grok-thread'},
    );
  });

  test(
    'workspace restore never reaches retired Cursor runtime paths',
    () async {
      // Arrange
      final directory = Directory.systemTemp.createTempSync('zeta_shell_');
      tempDirectories.add(directory);
      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello');
      final cursorThread = _thread(
        id: 'cursor-restored',
        providerId: cursorAgentProviderId,
        projectPath: directory.path,
      );
      final restoredSession = IdeSessionState(
        projectPaths: <String>[directory.path],
        activeProjectPath: directory.path,
        activeAgentProviderId: cursorAgentProviderId,
        agentThreadIdsByProject: <String, String>{
          directory.path: cursorThread.id,
        },
        projectThreadExpansionByProject: <String, bool>{directory.path: true},
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          directory.path: <AgentThreadSummary>[cursorThread],
        },
        selectedThreadIdsByProject: <String, String>{
          directory.path: cursorThread.id,
        },
      );
      final configStore = _RecordingAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultCursor.copyWith(enabled: true),
          ],
          activeProviderId: cursorAgentProviderId,
        ),
      );
      final configBefore = configStore.settings.toJson();
      final codexBackend = _ProviderBackend(
        config: AgentProviderConfig.defaultCodex,
        threadPages: const <AgentThreadPage>[],
      );
      final factory = _RecordingAgentProviderFactory(<String, _ProviderBackend>{
        defaultAgentProviderId: codexBackend,
      });

      // Act
      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => directory.path,
        sessionStore: CallbackIdeSessionStore(
          loadJson: () async => restoredSession.encode(),
          saveJson: _saveDiscardedSession,
        ),
        agentProviderFactory: factory,
        agentProviderConfigStore: configStore,
      );
      addTearDown(shell.dispose);
      await _flushAsync();
      await _flushAsync();

      // Assert
      expect(shell.activeProjectPath, directory.path);
      expect(
        shell.selectedAgentViewModel.status.state,
        AgentProviderConnectionState.unavailable,
      );
      expect(shell.selectedAgentViewModel.status.details, contains('已退役'));
      expect(
        factory.createdProviderIds,
        isNot(contains(cursorAgentProviderId)),
      );
      expect(factory.cursorProviderCreations, 0);
      expect(factory.cursorCliLocatorCalls, 0);
      expect(factory.cursorProcessStarts, 0);
      expect(factory.cursorSessionIndexWrites, 0);
      expect(configStore.saveCount, 0);
      expect(configStore.settings.toJson(), configBefore);
    },
  );

  test('restored thread starts on project home', () async {
    // Arrange
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final thread = _thread(
      id: 'codex-restored',
      providerId: defaultAgentProviderId,
      projectPath: directory.path,
    );
    final restoredSession = IdeSessionState(
      projectPaths: <String>[directory.path],
      activeProjectPath: directory.path,
      activeAgentProviderId: grokAgentProviderId,
      agentThreadIdsByProject: <String, String>{directory.path: thread.id},
      cachedThreadsByProject: <String, List<AgentThreadSummary>>{
        directory.path: <AgentThreadSummary>[thread],
      },
      selectedThreadIdsByProject: <String, String>{directory.path: thread.id},
    );
    final settingsCompleter = Completer<AgentProviderSettings>();
    final configStore = _DelayedAgentProviderConfigStore(settingsCompleter);
    final codexBackend = _ProviderBackend(
      config: AgentProviderConfig.defaultCodex,
      threadPages: const <AgentThreadPage>[],
      threadHistories: <String, AgentThreadHistorySnapshot>{
        thread.id: AgentThreadHistorySnapshot(
          threadId: thread.id,
          turns: const <AgentHistoryTurn>[
            AgentHistoryTurn(
              id: 'codex-turn',
              entries: <AgentHistoryEntry>[
                AgentHistoryMessageEntry(
                  id: 'codex-message',
                  role: AgentMessageRole.agent,
                  text: 'Restored Codex history',
                ),
              ],
            ),
          ],
        ),
      },
    );
    final grokBackend = _ProviderBackend(
      config: AgentProviderConfig.defaultGrok,
      threadPages: const <AgentThreadPage>[],
    );
    final shell = IdeShellController(
      agentUiFrameSchedulerFactory: _createUiFrameScheduler,
      directoryPicker: () async => directory.path,
      sessionStore: CallbackIdeSessionStore(
        loadJson: () async => restoredSession.encode(),
        saveJson: _saveDiscardedSession,
      ),
      agentProviderFactory: _RecordingAgentProviderFactory(
        <String, _ProviderBackend>{
          defaultAgentProviderId: codexBackend,
          grokAgentProviderId: grokBackend,
        },
      ),
      agentProviderConfigStore: configStore,
    );
    addTearDown(shell.dispose);

    // Act：恢复项目时不自动创建或选中旧 Thread workspace。
    for (
      var attempt = 0;
      attempt < 20 && !shell.initialRestoreCompleted;
      attempt += 1
    ) {
      await _flushAsync();
    }

    // Assert：启动落在项目首页，旧会话详情尚未加载。
    expect(shell.initialRestoreCompleted, isTrue);
    expect(shell.activeProjectPath, directory.path);
    expect(shell.isProjectHomeActive, isTrue);
    expect(shell.selectedAgentWorkspaceEntryId, isNull);
    expect(
      shell.projectThreadStateFor(directory.path).selectedThreadId,
      isNull,
    );
    expect(shell.agentWorkspaceEntries, hasLength(1));
    expect(codexBackend.readThreadIds, isEmpty);

    // Act：配置加载完成后，由用户显式打开缓存中的 Codex 会话。
    settingsCompleter.complete(
      const AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultGrok,
        ],
        activeProviderId: grokAgentProviderId,
      ),
    );
    for (
      var attempt = 0;
      attempt < 20 &&
          shell.agentProviderController.activeProviderId != grokAgentProviderId;
      attempt += 1
    ) {
      await _flushAsync();
    }
    await shell.selectProjectThread(directory.path, thread);
    await _flushAsync();

    // Assert：会话自身的 Provider 归属仍优先于当前全局 Provider。
    expect(shell.isProjectHomeActive, isFalse);
    expect(
      shell.selectedAgentViewModel.activeProviderId,
      defaultAgentProviderId,
    );
    expect(codexBackend.readThreadIds, <String>[thread.id]);
    expect(grokBackend.readThreadIds, isEmpty);
    expect(
      shell.selectedAgentViewModel.timelineEntries
          .whereType<AgentMessageTimelineEntry>()
          .map((entry) => entry.message.text),
      contains('Restored Codex history'),
    );
  });

  test(
    'project navigation enters home while current project tap keeps thread',
    () async {
      // Arrange
      final firstDirectory = Directory.systemTemp.createTempSync('zeta_shell_');
      final secondDirectory = Directory.systemTemp.createTempSync(
        'zeta_shell_',
      );
      tempDirectories.addAll(<Directory>[firstDirectory, secondDirectory]);
      final thread = _thread(
        id: 'thread-a',
        providerId: defaultAgentProviderId,
        projectPath: firstDirectory.path,
      );
      final backend = _ProviderBackend(
        config: AgentProviderConfig.defaultCodex,
        threadPages: <AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[thread],
            nextCursor: null,
          ),
          const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          ),
        ],
      );
      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => firstDirectory.path,
        sessionStore: const CallbackIdeSessionStore(
          loadJson: _loadEmptySession,
          saveJson: _saveDiscardedSession,
        ),
        agentProviderFactory: _RecordingAgentProviderFactory(
          <String, _ProviderBackend>{defaultAgentProviderId: backend},
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      );
      addTearDown(shell.dispose);

      // Act + Assert: opening a project lands on its home.
      await shell.openProject();
      await _flushAsync();
      expect(shell.isProjectHomeActive, isTrue);
      expect(shell.selectedAgentWorkspaceEntryId, isNull);
      expect(
        shell.projectThreadStateFor(firstDirectory.path).selectedThreadId,
        isNull,
      );

      await shell.selectProjectThread(firstDirectory.path, thread);
      expect(shell.isProjectHomeActive, isFalse);
      expect(
        shell.projectThreadStateFor(firstDirectory.path).selectedThreadId,
        thread.id,
      );

      // Clicking the active project only toggles expansion and keeps the thread.
      await shell.selectKnownProject(firstDirectory.path);
      expect(shell.isProjectHomeActive, isFalse);
      expect(
        shell.projectThreadStateFor(firstDirectory.path).selectedThreadId,
        thread.id,
      );

      // Switching projects enters the new project's home and clears highlights.
      await shell.selectKnownProject(secondDirectory.path);
      await _flushAsync();
      expect(shell.activeProjectPath, secondDirectory.path);
      expect(shell.isProjectHomeActive, isTrue);
      expect(shell.selectedAgentWorkspaceEntryId, isNull);
      expect(
        shell.projectThreadsViewModel.states.values.every(
          (state) => state.selectedThreadId == null,
        ),
        isTrue,
      );

      await shell.startNewThreadForProject(
        secondDirectory.path,
        providerId: defaultAgentProviderId,
      );
      expect(shell.isProjectHomeActive, isFalse);
      expect(shell.selectedAgentWorkspaceEntryId, isNotNull);
      expect(
        shell.projectThreadStateFor(secondDirectory.path).selectedThreadId,
        isNull,
      );
    },
  );

  test('restores and persists the explicit project home state', () async {
    final directory = Directory.systemTemp.createTempSync('zeta_shell_');
    tempDirectories.add(directory);
    final thread = _thread(
      id: 'remembered-thread',
      providerId: defaultAgentProviderId,
      projectPath: directory.path,
    );
    final restoredSession = IdeSessionState(
      projectPaths: <String>[directory.path],
      activeProjectPath: directory.path,
      agentThreadIdsByProject: <String, String>{directory.path: thread.id},
      cachedThreadsByProject: <String, List<AgentThreadSummary>>{
        directory.path: <AgentThreadSummary>[thread],
      },
      selectedThreadIdsByProject: <String, String>{directory.path: thread.id},
      projectHomeActive: true,
    );
    String? savedJson;
    final backend = _ProviderBackend(
      config: AgentProviderConfig.defaultCodex,
      threadPages: <AgentThreadPage>[
        const AgentThreadPage(
          threads: <AgentThreadSummary>[],
          nextCursor: null,
        ),
      ],
    );
    final shell = IdeShellController(
      agentUiFrameSchedulerFactory: _createUiFrameScheduler,
      directoryPicker: () async => directory.path,
      sessionStore: CallbackIdeSessionStore(
        loadJson: () async => restoredSession.encode(),
        saveJson: (value) async {
          savedJson = value;
        },
      ),
      agentProviderFactory: _RecordingAgentProviderFactory(
        <String, _ProviderBackend>{defaultAgentProviderId: backend},
      ),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(shell.dispose);

    await _flushAsync();
    await _flushAsync();

    expect(shell.activeProjectPath, directory.path);
    expect(shell.isProjectHomeActive, isTrue);
    expect(shell.selectedAgentWorkspaceEntryId, isNull);
    expect(
      shell.projectThreadStateFor(directory.path).selectedThreadId,
      isNull,
    );

    await shell.saveNow();
    final saved = IdeSessionState.tryDecode(savedJson);
    expect(saved?.projectHomeActive, isTrue);
    expect(saved?.selectedThreadIdsByProject, isEmpty);
  });

  test('restores, updates, and persists every workbench field', () async {
    const restoredWorkbench = IdeWorkbenchLayoutState(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: 305,
      agentUsageHeightFraction: 0.41,
      selectedAgentUsageProviderId: 'grok',
    );
    String? savedJson;
    final shell = IdeShellController(
      agentUiFrameSchedulerFactory: _createUiFrameScheduler,
      directoryPicker: () async => null,
      sessionStore: CallbackIdeSessionStore(
        loadJson: () async =>
            const IdeSessionState(workbenchLayout: restoredWorkbench).encode(),
        saveJson: (value) async {
          savedJson = value;
        },
      ),
      agentProviderFactory:
          _RecordingAgentProviderFactory(<String, _ProviderBackend>{
            defaultAgentProviderId: _ProviderBackend(
              config: AgentProviderConfig.defaultCodex,
              threadPages: const <AgentThreadPage>[],
            ),
          }),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
    );
    addTearDown(shell.dispose);

    await _flushAsync();
    await _flushAsync();

    expect(shell.initialRestoreCompleted, isTrue);
    expect(shell.workbenchLayout, restoredWorkbench);

    shell
      ..setLeftSidebarVisible(true)
      ..setAgentUsageExpanded(false)
      ..setLeftSidebarWidth(340)
      ..setAgentUsageHeightFraction(0.56)
      ..setSelectedAgentUsageProviderId('claude_code');
    expect(savedJson, isNull);

    await Future<void>.delayed(
      sessionSaveDelay + const Duration(milliseconds: 50),
    );

    const updatedWorkbench = IdeWorkbenchLayoutState(
      leftSidebarWidth: 340,
      agentUsageHeightFraction: 0.56,
      selectedAgentUsageProviderId: 'claude_code',
    );
    expect(shell.workbenchLayout, updatedWorkbench);
    expect(
      IdeSessionState.tryDecode(savedJson)?.workbenchLayout,
      updatedWorkbench,
    );

    savedJson = null;
    shell.setSelectedAgentUsageProviderId('codex');
    await shell.saveNow();

    expect(
      IdeSessionState.tryDecode(savedJson)?.workbenchLayout,
      updatedWorkbench.copyWith(selectedAgentUsageProviderId: 'codex'),
    );
  });

  test(
    'sorts recent projects and aggregates cached threads across projects',
    () async {
      final firstDirectory = Directory.systemTemp.createTempSync(
        'zeta_recent_',
      );
      final secondDirectory = Directory.systemTemp.createTempSync(
        'zeta_recent_',
      );
      tempDirectories.addAll(<Directory>[firstDirectory, secondDirectory]);
      final older = DateTime.utc(2026, 7, 20, 9);
      final newer = DateTime.utc(2026, 7, 21, 9);
      final openedNow = DateTime.utc(2026, 7, 21, 15);
      final duplicateOlder = _thread(
        id: 'shared-thread',
        providerId: defaultAgentProviderId,
        projectPath: firstDirectory.path,
        updatedAt: older,
      );
      final duplicateNewer = _thread(
        id: 'shared-thread',
        providerId: defaultAgentProviderId,
        projectPath: secondDirectory.path,
        updatedAt: newer,
      );
      final unique = _thread(
        id: 'unique-thread',
        providerId: grokAgentProviderId,
        projectPath: firstDirectory.path,
        updatedAt: newer.subtract(const Duration(hours: 1)),
      );
      final restoredSession = IdeSessionState(
        projectPaths: <String>[firstDirectory.path, secondDirectory.path],
        projectLastOpenedAtByPath: <String, DateTime>{
          firstDirectory.path: older,
          secondDirectory.path: newer,
        },
        projectThreadExpansionByProject: <String, bool>{
          firstDirectory.path: false,
          secondDirectory.path: false,
        },
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          firstDirectory.path: <AgentThreadSummary>[duplicateOlder, unique],
          secondDirectory.path: <AgentThreadSummary>[duplicateNewer],
        },
      );
      String? savedJson;
      final backend = _ProviderBackend(
        config: AgentProviderConfig.defaultCodex,
        threadPages: <AgentThreadPage>[
          const AgentThreadPage(
            threads: <AgentThreadSummary>[],
            nextCursor: null,
          ),
        ],
      );
      final shell = IdeShellController(
        agentUiFrameSchedulerFactory: _createUiFrameScheduler,
        directoryPicker: () async => firstDirectory.path,
        sessionStore: CallbackIdeSessionStore(
          loadJson: () async => restoredSession.encode(),
          saveJson: (value) async {
            savedJson = value;
          },
        ),
        agentProviderFactory: _RecordingAgentProviderFactory(
          <String, _ProviderBackend>{defaultAgentProviderId: backend},
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(
          const AgentProviderSettings(
            providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
          ),
        ),
        now: () => openedNow,
      );
      addTearDown(shell.dispose);

      await _flushAsync();
      await _flushAsync();

      expect(shell.initialRestoreCompleted, isTrue);
      expect(shell.recentProjects.map((project) => project.path), <String>[
        secondDirectory.path,
        firstDirectory.path,
      ]);
      expect(shell.recentThreads.map((thread) => thread.id), <String>[
        'shared-thread',
        'unique-thread',
      ]);
      expect(shell.recentThreads.first.projectPath, secondDirectory.path);

      await shell.openRecentProject(firstDirectory.path);
      expect(shell.activeProjectPath, firstDirectory.path);
      expect(shell.isProjectHomeActive, isTrue);
      expect(shell.recentProjects.first.path, firstDirectory.path);

      await shell.saveNow();
      final saved = IdeSessionState.tryDecode(savedJson);
      expect(saved?.projectLastOpenedAtByPath[firstDirectory.path], openedNow);
    },
  );
}

Future<String?> _loadEmptySession() async => null;

Future<void> _saveDiscardedSession(String value) async {}

Future<void> _flushAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  for (var turn = 0; turn < 3; turn += 1) {
    await Future<void>.delayed(Duration.zero);
    for (final scheduler in _uiFrameSchedulers) {
      scheduler.drainFrames();
    }
  }
}

FakeAgentFrameScheduler _createUiFrameScheduler() {
  final scheduler = FakeAgentFrameScheduler();
  _uiFrameSchedulers.add(scheduler);
  return scheduler;
}

Future<_SelectedThreadShellHarness> _openShellWithSelectedThread({
  required Directory directory,
  required List<String> threadIds,
  required String selectedThreadId,
  bool startSessionRuntime = false,
  bool completeTurns = false,
  bool canForkThreadAtTurn = false,
  Map<String, AgentThreadHistorySnapshot> threadHistories =
      const <String, AgentThreadHistorySnapshot>{},
}) async {
  final backend = _ProviderBackend(
    config: AgentProviderConfig.defaultCodex,
    threadHistories: threadHistories,
    completeTurns: startSessionRuntime || completeTurns,
    canForkThreadAtTurn: canForkThreadAtTurn,
    threadPages: <AgentThreadPage>[
      AgentThreadPage(
        threads: <AgentThreadSummary>[
          for (final threadId in threadIds)
            _thread(
              id: threadId,
              providerId: defaultAgentProviderId,
              projectPath: directory.path,
            ),
        ],
        nextCursor: null,
      ),
    ],
  );
  final sessionSaves = _SessionSaveRecorder();
  final shell = IdeShellController(
    agentUiFrameSchedulerFactory: _createUiFrameScheduler,
    directoryPicker: () async => directory.path,
    sessionStore: CallbackIdeSessionStore(
      loadJson: _loadEmptySession,
      saveJson: sessionSaves.save,
    ),
    agentProviderFactory: _RecordingAgentProviderFactory(
      <String, _ProviderBackend>{defaultAgentProviderId: backend},
    ),
    agentProviderConfigStore: MemoryAgentProviderConfigStore(
      const AgentProviderSettings(
        providers: <AgentProviderConfig>[AgentProviderConfig.defaultCodex],
        activeProviderId: defaultAgentProviderId,
      ),
    ),
  );

  await shell.openProject();
  await _flushAsync();
  final thread = shell
      .projectThreadStateFor(directory.path)
      .threads
      .singleWhere((thread) => thread.id == selectedThreadId);
  await shell.selectProjectThread(directory.path, thread);
  await _flushAsync();
  if (startSessionRuntime) {
    await shell.selectedAgentViewModel.sendMessage('bind test runtime');
    await _flushAsync();
  }

  return _SelectedThreadShellHarness(
    shell: shell,
    backend: backend,
    sessionSaves: sessionSaves,
  );
}

AgentThreadSummary _thread({
  required String id,
  required String providerId,
  required String projectPath,
  DateTime? updatedAt,
}) {
  final activeAt = updatedAt ?? DateTime.utc(2026, 7, 15);
  return AgentThreadSummary(
    id: id,
    providerId: providerId,
    projectPath: projectPath,
    title: id,
    sessionPath: '$projectPath/$id.jsonl',
    preview: id,
    createdAt: activeAt.subtract(const Duration(hours: 1)),
    updatedAt: activeAt,
    recencyAt: activeAt,
    status: AgentThreadRuntimeStatus.idle,
  );
}

class _SelectedThreadShellHarness {
  const _SelectedThreadShellHarness({
    required this.shell,
    required this.backend,
    required this.sessionSaves,
  });

  final IdeShellController shell;
  final _ProviderBackend backend;
  final _SessionSaveRecorder sessionSaves;

  _ShellTestAgentProvider get provider => backend.instances.last;
}

class _SessionSaveRecorder {
  int saveCount = 0;

  Future<void> save(String value) async {
    saveCount += 1;
  }

  void reset() {
    saveCount = 0;
  }
}

final class _DirectoryTrackingUsageRepository
    implements AgentUsagePanelRepository {
  List<AgentUsagePanelProvider> directory = const <AgentUsagePanelProvider>[
    AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
    AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
  ];
  final List<String> loadedProviderIds = <String>[];

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async => directory;

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    loadedProviderIds.add(providerId);
    final provider = directory.firstWhere(
      (candidate) => candidate.providerId == providerId,
    );
    return AgentUsagePanelProviderResult(
      entry: AgentUsagePanelEntry(
        providerId: provider.providerId,
        providerName: provider.providerName,
      ),
      refreshedAt: DateTime(2026, 8, 12),
    );
  }
}

class _RecordingAgentProviderFactory implements AgentProviderFactory {
  _RecordingAgentProviderFactory(this.backendsById);

  final Map<String, _ProviderBackend> backendsById;
  final List<String> createdProviderIds = <String>[];
  int cursorProviderCreations = 0;
  int cursorCliLocatorCalls = 0;
  int cursorProcessStarts = 0;
  int cursorSessionIndexWrites = 0;

  @override
  AgentProvider create(AgentProviderConfig config) {
    createdProviderIds.add(config.id);
    if (CursorRetirementPolicy.isRetiredProvider(config)) {
      cursorProviderCreations += 1;
      cursorCliLocatorCalls += 1;
      cursorProcessStarts += 1;
      cursorSessionIndexWrites += 1;
      throw StateError('Cursor runtime path must remain unreachable');
    }
    final backend = backendsById[config.id];
    if (backend == null) {
      throw StateError('No backend configured for ${config.id}');
    }
    final provider = _ShellTestAgentProvider(backend: backend);
    backend.instances.add(provider);
    return provider;
  }
}

class _RecordingAgentProviderConfigStore implements AgentProviderConfigStore {
  _RecordingAgentProviderConfigStore(this.settings);

  AgentProviderSettings settings;
  int saveCount = 0;

  @override
  Future<AgentProviderSettings> load() async => settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    saveCount += 1;
    this.settings = settings;
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

class _ProviderBackend {
  _ProviderBackend({
    required this.config,
    required this.threadPages,
    this.threadHistories = const <String, AgentThreadHistorySnapshot>{},
    this.completeTurns = true,
    this.canForkThreadAtTurn = false,
  });

  final AgentProviderConfig config;
  final List<AgentThreadPage> threadPages;
  final Map<String, AgentThreadHistorySnapshot> threadHistories;
  final bool completeTurns;
  final bool canForkThreadAtTurn;
  final List<_ShellTestAgentProvider> instances = <_ShellTestAgentProvider>[];
  final List<String> readThreadIds = <String>[];

  bool anyUnsubscribed(String threadId) {
    return instances.any(
      (provider) => provider.unsubscribedThreads.contains(threadId),
    );
  }
}

class _ShellTestAgentProvider
    with AgentProviderThreadLifecycleStub
    implements AgentProvider {
  _ShellTestAgentProvider({required this.backend});

  final _ProviderBackend backend;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<String> unsubscribedThreads = <String>[];
  final List<({String sessionId, String? message})> sentMessages =
      <({String sessionId, String? message})>[];

  @override
  AgentProviderConfig get config => backend.config;

  @override
  AgentProviderCapabilities get capabilities => AgentProviderCapabilities
      .codexAppServer
      .copyWith(canForkThreadAtTurn: backend.canForkThreadAtTurn);

  @override
  Stream<AgentEvent> get events => _events.stream;

  void emit(AgentEvent event) {
    _events.add(event);
  }

  void emitAll(Iterable<AgentEvent> events) {
    for (final event in events) {
      emit(event);
    }
  }

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return AgentSession(
      id: 'draft-${DateTime.now().microsecondsSinceEpoch}',
      providerId: config.id,
      title: 'New thread',
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return AgentSession(id: sessionId, providerId: config.id, title: sessionId);
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    if (backend.threadPages.isEmpty) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    return backend.threadPages.removeAt(0);
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    return const AgentModelList(models: <AgentModelInfo>[]);
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

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
    backend.readThreadIds.add(threadId);
    return backend.threadHistories[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    unsubscribedThreads.add(threadId);
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
    final resolvedMessage =
        message ??
        inputs
            ?.whereType<AgentTextUserInput>()
            .map((input) => input.text)
            .join('\n');
    sentMessages.add((sessionId: session.id, message: resolvedMessage));
    final turn = AgentTurn(id: 'turn-${session.id}', sessionId: session.id);
    _events.add(AgentTurnStartedEvent(turn));
    if (backend.completeTurns) {
      _events.add(
        AgentTurnCompletedEvent(sessionId: session.id, turnId: turn.id),
      );
    }
    return turn;
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {}

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

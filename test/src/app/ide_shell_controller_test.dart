import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';

import '../testing/agent_provider_stub_base.dart';

void main() {
  final tempDirectories = <Directory>[];

  tearDown(() {
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

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
    },
  );

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
}

Future<String?> _loadEmptySession() async => null;

Future<void> _saveDiscardedSession(String value) async {}

Future<void> _flushAsync() async {
  await Future<void>.delayed(const Duration(milliseconds: 20));
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
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

class _RecordingAgentProviderFactory implements AgentProviderFactory {
  const _RecordingAgentProviderFactory(this.backendsById);

  final Map<String, _ProviderBackend> backendsById;

  @override
  AgentProvider create(AgentProviderConfig config) {
    final backend = backendsById[config.id];
    if (backend == null) {
      throw StateError('No backend configured for ${config.id}');
    }
    final provider = _ShellTestAgentProvider(backend: backend);
    backend.instances.add(provider);
    return provider;
  }
}

class _ProviderBackend {
  _ProviderBackend({
    required this.config,
    required this.threadPages,
    this.threadHistories = const <String, AgentThreadHistorySnapshot>{},
    this.completeTurns = true,
  });

  final AgentProviderConfig config;
  final List<AgentThreadPage> threadPages;
  final Map<String, AgentThreadHistorySnapshot> threadHistories;
  final bool completeTurns;
  final List<_ShellTestAgentProvider> instances = <_ShellTestAgentProvider>[];

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

  @override
  AgentProviderConfig get config => backend.config;

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.codexAppServer;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({required AgentContext context}) async {
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
  void updatePermissionSelection(AgentPermissionSelection selection) {}

  @override
  Future<List<AgentPermissionProfileSummary>> listPermissionProfiles() async {
    return const <AgentPermissionProfileSummary>[];
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
  }) async {
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

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/shell/ide_shell_controller.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';

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

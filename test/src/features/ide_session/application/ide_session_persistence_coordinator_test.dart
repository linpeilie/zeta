import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_persistence_coordinator.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_restore_result.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_state_builder.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

void main() {
  final tempDirectories = <Directory>[];
  final coordinators = <IdeSessionPersistenceCoordinator>[];

  tearDown(() {
    for (final coordinator in coordinators) {
      coordinator.dispose();
    }
    coordinators.clear();
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  test(
    'buildIdeSessionState writes current session id back to project maps',
    () {
      final snapshot = buildIdeSessionState(
        projectPaths: const <String>['/repo'],
        activeProjectPath: '/repo',
        currentFilePath: '/repo/lib/main.dart',
        expandedDirectoryPaths: const <String>{'/repo'},
        selectedTreeKey: '/repo/lib/main.dart',
        activeAgentProviderId: defaultAgentProviderId,
        agentThreadIdsByProject: const <String, String>{},
        projectThreadsSessionSnapshot: const ProjectThreadsSessionSnapshot(),
        currentProjectPath: '/repo',
        currentSessionId: 'thread-1',
        projectHomeActive: false,
      );

      expect(snapshot.agentThreadIdsByProject['/repo'], 'thread-1');
      expect(snapshot.selectedThreadIdsByProject['/repo'], 'thread-1');
    },
  );

  test('project home does not persist a hidden current thread', () {
    final snapshot = buildIdeSessionState(
      projectPaths: const <String>['/repo'],
      activeProjectPath: '/repo',
      currentFilePath: null,
      expandedDirectoryPaths: const <String>{},
      selectedTreeKey: null,
      activeAgentProviderId: defaultAgentProviderId,
      agentThreadIdsByProject: const <String, String>{'/repo': 'thread-1'},
      projectThreadsSessionSnapshot: const ProjectThreadsSessionSnapshot(),
      currentProjectPath: '/repo',
      currentSessionId: 'hidden-thread',
      projectHomeActive: true,
    );

    expect(snapshot.projectHomeActive, isTrue);
    expect(snapshot.agentThreadIdsByProject['/repo'], 'thread-1');
    expect(snapshot.selectedThreadIdsByProject, isEmpty);
  });

  test('restore sanitizes invalid paths and merges selected thread ids', () async {
    final projectDirectory = Directory.systemTemp.createTempSync(
      'zeta_ide_session_',
    );
    tempDirectories.add(projectDirectory);
    final currentFile = File(
      '${projectDirectory.path}${Platform.pathSeparator}main.dart',
    )..writeAsStringSync('void main() {}');
    final missingProjectPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}zeta_missing_project';
    final missingDirectoryPath =
        '${Directory.systemTemp.path}${Platform.pathSeparator}zeta_missing_dir';

    final store = _FakeIdeSessionStore(
      initialSnapshot: IdeSessionState(
        projectPaths: <String>[projectDirectory.path, missingProjectPath],
        activeProjectPath: projectDirectory.path,
        currentFilePath: currentFile.path,
        expandedDirectoryPaths: <String>{
          projectDirectory.path,
          missingDirectoryPath,
        },
        agentThreadIdsByProject: <String, String>{
          projectDirectory.path: 'thread-1',
          missingProjectPath: 'thread-x',
        },
        projectThreadExpansionByProject: <String, bool>{
          projectDirectory.path: true,
          missingProjectPath: true,
        },
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          projectDirectory.path: <AgentThreadSummary>[
            _threadSummary(projectDirectory.path, 'thread-1'),
          ],
          missingProjectPath: <AgentThreadSummary>[
            _threadSummary(missingProjectPath, 'thread-x'),
          ],
        },
        selectedThreadIdsByProject: const <String, String>{},
      ),
    );
    final coordinator = IdeSessionPersistenceCoordinator(
      store: store,
      saveDelay: const Duration(milliseconds: 1),
    );
    coordinators.add(coordinator);

    final result = await coordinator.restore();

    expect(result.status, IdeSessionRestoreStatus.restored);
    expect(result.shouldRequestSave, isTrue);
    expect(result.snapshot?.projectPaths, <String>[projectDirectory.path]);
    expect(result.snapshot?.activeProjectPath, projectDirectory.path);
    expect(result.snapshot?.currentFilePath, currentFile.path);
    expect(result.snapshot?.expandedDirectoryPaths, <String>{
      projectDirectory.path,
    });
    expect(result.snapshot?.agentThreadIdsByProject, <String, String>{
      projectDirectory.path: 'thread-1',
    });
    expect(result.snapshot?.selectedThreadIdsByProject, <String, String>{
      projectDirectory.path: 'thread-1',
    });
    expect(result.snapshot?.cachedThreadsByProject.keys, <String>[
      projectDirectory.path,
    ]);
  });

  test(
    'requestSave waits for restore to finish and keeps the latest snapshot',
    () async {
      final restoreCompleter = Completer<IdeSessionState?>();
      final store = _FakeIdeSessionStore(loadFuture: restoreCompleter.future);
      final coordinator = IdeSessionPersistenceCoordinator(
        store: store,
        saveDelay: const Duration(milliseconds: 5),
      );
      coordinators.add(coordinator);

      final restoreFuture = coordinator.restore();
      coordinator.requestSave(
        const IdeSessionState(projectPaths: <String>['/older']),
      );
      coordinator.requestSave(
        const IdeSessionState(projectPaths: <String>['/newer']),
      );

      expect(store.savedSnapshots, isEmpty);

      restoreCompleter.complete(null);
      await restoreFuture;
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(store.savedSnapshots, hasLength(1));
      expect(store.savedSnapshots.single.projectPaths, <String>['/newer']);
    },
  );

  test('cancelPendingRestore invalidates stale restore results', () async {
    final restoreCompleter = Completer<IdeSessionState?>();
    final store = _FakeIdeSessionStore(loadFuture: restoreCompleter.future);
    final coordinator = IdeSessionPersistenceCoordinator(
      store: store,
      saveDelay: const Duration(milliseconds: 1),
    );
    coordinators.add(coordinator);

    final restoreFuture = coordinator.restore();
    coordinator.cancelPendingRestore();
    restoreCompleter.complete(
      const IdeSessionState(projectPaths: <String>['/repo']),
    );

    final result = await restoreFuture;

    expect(result.status, IdeSessionRestoreStatus.cancelled);
  });
}

class _FakeIdeSessionStore implements IdeSessionStore {
  _FakeIdeSessionStore({this.initialSnapshot, this.loadFuture});

  final IdeSessionState? initialSnapshot;
  final Future<IdeSessionState?>? loadFuture;
  final List<IdeSessionState> savedSnapshots = <IdeSessionState>[];

  @override
  Future<IdeSessionState?> load() async {
    if (loadFuture != null) {
      return loadFuture;
    }
    return initialSnapshot;
  }

  @override
  Future<void> save(IdeSessionState state) async {
    savedSnapshots.add(state);
  }
}

AgentThreadSummary _threadSummary(String projectPath, String id) {
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: projectPath,
    preview: 'Preview',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

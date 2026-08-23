import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

WorkspaceNode _directory(String path) => WorkspaceNode(
  path: path,
  name: path.split('/').last,
  type: WorkspaceNodeType.directory,
);

WorkspaceNode _file(String path) => WorkspaceNode(
  path: path,
  name: path.split('/').last,
  type: WorkspaceNodeType.file,
);

void main() {
  test(
    'project load uses typed effect and commits the matching result',
    () async {
      final runner = _RecordingRunner();
      final store = WorkspaceSliceStore(
        initialState: WorkspaceSliceState(),
        effectRunner: runner,
      );
      addTearDown(store.dispose);

      final load = store.loadProject('/repo');
      expect(store.state.isLoadingProject, isTrue);
      final effect = runner.effects.single as ReadWorkspaceProjectEffect;

      store.projectLoadSucceeded(
        operationId: effect.operationId,
        path: effect.path,
        tree: <WorkspaceNode>[_file('/repo/main.dart')],
        openedAt: DateTime(2026, 8, 23),
      );

      expect(await load, isTrue);
      expect(store.state.projects, <String>['/repo']);
      expect(store.state.activeProjectPath, '/repo');
      expect(store.state.tree.single.path, '/repo/main.dart');
      expect(store.state.isLoadingProject, isFalse);
      expect(runner.effects.last, isA<IndexWorkspaceFilesEffect>());
      expect(() => store.state.projects.add('/other'), throwsUnsupportedError);
    },
  );

  test(
    'new project load rejects the late result without overwriting state',
    () async {
      final runner = _RecordingRunner();
      final store = WorkspaceSliceStore(
        initialState: WorkspaceSliceState(),
        effectRunner: runner,
      );
      addTearDown(store.dispose);

      final first = store.loadProject('/first');
      final firstEffect = runner.effects.last as ReadWorkspaceProjectEffect;
      final second = store.loadProject('/second');
      final secondEffect = runner.effects.last as ReadWorkspaceProjectEffect;

      expect(await first, isFalse);
      store.projectLoadSucceeded(
        operationId: firstEffect.operationId,
        path: firstEffect.path,
        tree: <WorkspaceNode>[_file('/first/a.dart')],
        openedAt: DateTime(2026, 8, 23),
      );
      expect(store.state.activeProjectPath, isNull);

      store.projectLoadSucceeded(
        operationId: secondEffect.operationId,
        path: secondEffect.path,
        tree: <WorkspaceNode>[_file('/second/b.dart')],
        openedAt: DateTime(2026, 8, 23),
      );
      expect(await second, isTrue);
      expect(store.state.activeProjectPath, '/second');
      expect(store.staleResultCount, 1);
    },
  );

  test('directory expansion reads one layer and keeps collapsed children', () {
    final runner = _RecordingRunner();
    final store = WorkspaceSliceStore(
      initialState: WorkspaceSliceState(
        activeProjectPath: '/repo',
        tree: <WorkspaceNode>[_directory('/repo/lib')],
      ),
      effectRunner: runner,
    );
    addTearDown(store.dispose);

    store.setDirectoryExpanded('/repo/lib', true);
    expect(store.state.expandedDirectoryPaths, contains('/repo/lib'));
    final effect = runner.effects.single as ReadWorkspaceDirectoryEffect;
    expect(effect.path, '/repo/lib');

    store.directoryLoaded('/repo/lib', <WorkspaceNode>[
      _file('/repo/lib/main.dart'),
    ]);
    final loaded = store.state.tree.single;
    expect(loaded.childrenLoaded, isTrue);
    expect(loaded.children.single.path, '/repo/lib/main.dart');

    store.setDirectoryExpanded('/repo/lib', false);
    expect(store.state.expandedDirectoryPaths, isEmpty);
    expect(store.state.tree.single.children, hasLength(1));
  });

  test('file selection and project removal update only workspace facts', () {
    final runner = _RecordingRunner();
    final store = WorkspaceSliceStore(
      initialState: WorkspaceSliceState(
        projects: const <String>['/repo', '/other'],
        activeProjectPath: '/repo',
        tree: <WorkspaceNode>[_file('/repo/main.dart')],
        projectLastOpenedAtByPath: <String, DateTime>{
          '/repo': DateTime(2026, 8, 23),
          '/other': DateTime(2026, 8, 22),
        },
      ),
      effectRunner: runner,
    );
    addTearDown(store.dispose);

    final selected = store.selectTreeNode('/repo/main.dart');
    expect(selected?.path, '/repo/main.dart');
    expect(store.state.selectedTreePath, '/repo/main.dart');
    expect(store.state.currentFilePath, '/repo/main.dart');

    expect(store.removeProject('/other'), isTrue);
    expect(store.state.projects, <String>['/repo']);
    expect(store.state.projectLastOpenedAtByPath, isNot(contains('/other')));
  });

  test(
    'restore result normalizes tree selection and indexes active root',
    () async {
      final runner = _RecordingRunner();
      final store = WorkspaceSliceStore(
        initialState: WorkspaceSliceState(),
        effectRunner: runner,
      );
      addTearDown(store.dispose);
      final snapshot = WorkspaceRestoreSnapshot(
        projects: const <String>['/repo'],
        activeProjectPath: '/repo',
        currentFilePath: '/repo/main.dart',
        expandedDirectoryPaths: const <String>{'/repo/lib'},
        selectedTreePath: '/repo/missing.dart',
        projectLastOpenedAtByPath: <String, DateTime>{
          '/repo': DateTime(2026, 8, 23),
        },
      );

      final restore = store.restore(snapshot);
      final effect = runner.effects.single as RestoreWorkspaceEffect;
      store.restoreSucceeded(
        operationId: effect.operationId,
        snapshot: snapshot,
        tree: <WorkspaceNode>[_file('/repo/main.dart')],
        selectedTreePath: null,
      );

      expect(await restore, isTrue);
      expect(store.state.currentFilePath, '/repo/main.dart');
      expect(store.state.selectedTreePath, isNull);
      expect(runner.effects.last, isA<IndexWorkspaceFilesEffect>());
    },
  );

  test(
    'dispose settles pending operations and ignores later ingress',
    () async {
      final runner = _RecordingRunner();
      final store = WorkspaceSliceStore(
        initialState: WorkspaceSliceState(),
        effectRunner: runner,
      );
      final pending = store.loadProject('/repo');
      final effect = runner.effects.single as ReadWorkspaceProjectEffect;

      store.dispose();
      expect(await pending, isFalse);
      expect(runner.closed, isTrue);

      store.projectLoadSucceeded(
        operationId: effect.operationId,
        path: effect.path,
        tree: <WorkspaceNode>[_file('/repo/main.dart')],
        openedAt: DateTime(2026, 8, 23),
      );
      expect(store.state.activeProjectPath, isNull);
    },
  );
}

final class _RecordingRunner implements WorkspaceSliceEffectRunner {
  final List<WorkspaceSliceEffect> effects = <WorkspaceSliceEffect>[];
  bool closed = false;

  @override
  void run(WorkspaceSliceEffect effect) => effects.add(effect);

  @override
  void close() => closed = true;
}

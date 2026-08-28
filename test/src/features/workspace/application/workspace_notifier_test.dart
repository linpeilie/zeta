import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/workspace/application/workspace_restore_snapshot.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

import '../../../testing/workspace_test_bindings.dart';
import '../../../testing/fake_workspace_directory_picker.dart';

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
    'openOrActivate commits the matching tree and indexes the root',
    () async {
      final catalog = MemoryWorkspaceDirectoryCatalog(
        existingPaths: const <String>{'/repo'},
        childrenByPath: <String, List<WorkspaceNode>>{
          '/repo': <WorkspaceNode>[_file('/repo/main.dart')],
        },
      );
      final bindings = WorkspaceTestBindings(
        catalog: catalog,
        now: () => DateTime(2026, 8, 23),
      );
      addTearDown(bindings.dispose);

      expect(await bindings.notifier.openOrActivate('/repo'), isTrue);
      expect(bindings.notifier.state.projectPaths, <String>['/repo']);
      expect(bindings.notifier.state.activeProjectPath, '/repo');
      expect(bindings.notifier.state.activeProject?.name, 'repo');
      expect(
        bindings.notifier.activeFileTree.tree.single.path,
        '/repo/main.dart',
      );
      expect(bindings.notifier.activeFileTree.isLoading, isFalse);
      expect(
        () => bindings.notifier.state.openProjects.add(
          WorkspaceProject.fromPath('/other'),
        ),
        throwsUnsupportedError,
      );
    },
  );

  test('later openOrActivate becomes the active project', () async {
    final catalog = MemoryWorkspaceDirectoryCatalog(
      existingPaths: const <String>{'/first', '/second'},
      childrenByPath: <String, List<WorkspaceNode>>{
        '/first': <WorkspaceNode>[_file('/first/a.dart')],
        '/second': <WorkspaceNode>[_file('/second/b.dart')],
      },
    );
    final bindings = WorkspaceTestBindings(catalog: catalog);
    addTearDown(bindings.dispose);

    expect(await bindings.notifier.openOrActivate('/first'), isTrue);
    expect(await bindings.notifier.openOrActivate('/second'), isTrue);
    expect(bindings.notifier.state.activeProjectPath, '/second');
    expect(bindings.notifier.state.projectPaths, contains('/first'));
    expect(bindings.notifier.state.projectPaths, contains('/second'));
    expect(bindings.notifier.activeFileTree.tree.single.path, '/second/b.dart');
    expect(bindings.notifier.treeStateFor('/first').hasLoaded, isTrue);
  });

  test(
    'directory expansion reads one layer and keeps collapsed children',
    () async {
      final catalog = MemoryWorkspaceDirectoryCatalog(
        existingPaths: const <String>{'/repo'},
        childrenByPath: <String, List<WorkspaceNode>>{
          '/repo': <WorkspaceNode>[_directory('/repo/lib')],
          '/repo/lib': <WorkspaceNode>[_file('/repo/lib/main.dart')],
        },
      );
      final bindings = WorkspaceTestBindings(catalog: catalog);
      addTearDown(bindings.dispose);
      await bindings.notifier.openOrActivate('/repo');

      bindings.notifier.setDirectoryExpanded('/repo/lib', true);
      expect(
        bindings.notifier.activeFileTree.expandedDirectoryPaths,
        contains('/repo/lib'),
      );
      final loaded = bindings.notifier.activeFileTree.tree.single;
      expect(loaded.childrenLoaded, isTrue);
      expect(loaded.children.single.path, '/repo/lib/main.dart');

      bindings.notifier.setDirectoryExpanded('/repo/lib', false);
      expect(bindings.notifier.activeFileTree.expandedDirectoryPaths, isEmpty);
      expect(
        bindings.notifier.activeFileTree.tree.single.children,
        hasLength(1),
      );
    },
  );

  test(
    'file selection and project removal update only workspace facts',
    () async {
      final catalog = MemoryWorkspaceDirectoryCatalog(
        existingPaths: const <String>{'/repo', '/other'},
        childrenByPath: <String, List<WorkspaceNode>>{
          '/repo': <WorkspaceNode>[_file('/repo/main.dart')],
          '/other': <WorkspaceNode>[_file('/other/a.dart')],
        },
      );
      final bindings = WorkspaceTestBindings(catalog: catalog);
      addTearDown(bindings.dispose);
      await bindings.notifier.openOrActivate('/other');
      await bindings.notifier.openOrActivate('/repo');

      final selected = bindings.notifier.selectTreeNode('/repo/main.dart');
      expect(selected?.path, '/repo/main.dart');
      expect(
        bindings.notifier.activeFileTree.selectedTreePath,
        '/repo/main.dart',
      );
      expect(
        bindings.notifier.activeFileTree.currentFilePath,
        '/repo/main.dart',
      );

      expect(bindings.notifier.removeProject('/other'), isTrue);
      expect(bindings.notifier.state.projectPaths, <String>['/repo']);
      expect(
        bindings.notifier.state.projectLastOpenedAtByPath,
        isNot(contains('/other')),
      );
    },
  );

  test('switching projects keeps the previous tree loaded', () async {
    final catalog = MemoryWorkspaceDirectoryCatalog(
      existingPaths: const <String>{'/a', '/b'},
      childrenByPath: <String, List<WorkspaceNode>>{
        '/a': <WorkspaceNode>[_file('/a/one.dart')],
        '/b': <WorkspaceNode>[_file('/b/two.dart')],
      },
    );
    final bindings = WorkspaceTestBindings(catalog: catalog);
    addTearDown(bindings.dispose);
    await bindings.notifier.openOrActivate('/a');
    bindings.notifier.selectTreeNode('/a/one.dart');
    await bindings.notifier.openOrActivate('/b');
    expect(bindings.notifier.activeFileTree.tree.single.path, '/b/two.dart');
    expect(
      bindings.notifier.treeStateFor('/a').selectedTreePath,
      '/a/one.dart',
    );
    expect(bindings.notifier.treeStateFor('/a').hasLoaded, isTrue);
  });

  test('restore only loads the active project tree', () async {
    final catalog = MemoryWorkspaceDirectoryCatalog(
      existingPaths: const <String>{'/repo', '/other'},
      childrenByPath: <String, List<WorkspaceNode>>{
        '/repo': <WorkspaceNode>[_file('/repo/main.dart')],
        '/other': <WorkspaceNode>[_file('/other/a.dart')],
      },
    );
    final bindings = WorkspaceTestBindings(catalog: catalog);
    addTearDown(bindings.dispose);
    final snapshot = WorkspaceRestoreSnapshot(
      projects: const <String>['/repo', '/other'],
      activeProjectPath: '/repo',
      currentFilePath: '/repo/main.dart',
      expandedDirectoryPaths: const <String>{},
      selectedTreePath: '/repo/missing.dart',
      projectLastOpenedAtByPath: <String, DateTime>{
        '/repo': DateTime(2026, 8, 23),
      },
    );

    expect(await bindings.notifier.restore(snapshot), isTrue);
    expect(bindings.notifier.state.projectPaths, <String>['/repo', '/other']);
    expect(bindings.notifier.activeFileTree.currentFilePath, '/repo/main.dart');
    expect(bindings.notifier.activeFileTree.selectedTreePath, isNull);
    expect(bindings.notifier.treeStateFor('/other').hasLoaded, isFalse);
  });

  test('picker cancel leaves the workspace empty', () async {
    final bindings = WorkspaceTestBindings(
      directoryPicker: FakeWorkspaceDirectoryPicker.cancelled(),
    );
    addTearDown(bindings.dispose);
    expect(await bindings.notifier.openProject(), isNull);
    expect(bindings.notifier.state.openProjects, isEmpty);
  });

  test('missing directory is not inserted', () async {
    final catalog = MemoryWorkspaceDirectoryCatalog();
    final bindings = WorkspaceTestBindings(catalog: catalog);
    addTearDown(bindings.dispose);
    expect(await bindings.notifier.openOrActivate('/missing'), isFalse);
    expect(bindings.notifier.state.activeProjectPath, isNull);
    expect(bindings.notifier.state.openProjects, isEmpty);
  });

  test('name is derived from the last path segment', () {
    expect(WorkspaceProject.fromPath('/Users/me/zeta/').name, 'zeta');
    expect(WorkspaceProject.fromPath('/Users/me/zeta').path, '/Users/me/zeta');
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/data/io_workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

import '../../testing/workspace_test_bindings.dart';

void main() {
  test(
    'opening a project reads only the requested tree layer and starts the index',
    () async {
      final root = Directory.systemTemp.createTempSync('zeta_workspace_slice_');
      addTearDown(() => root.deleteSync(recursive: true));
      final lib = Directory('${root.path}${Platform.pathSeparator}lib')
        ..createSync();
      File(
        '${lib.path}${Platform.pathSeparator}main.dart',
      ).writeAsStringSync('void main() {}');
      Directory(
        '${root.path}${Platform.pathSeparator}node_modules',
      ).createSync();

      var walkCount = 0;
      final index = WorkspaceFileIndexController(
        runWalk: (_) async {
          walkCount += 1;
          return const <WorkspaceNode>[];
        },
        watchDirectory: (_) => const Stream.empty(),
      );
      addTearDown(index.dispose);
      final bindings = WorkspaceTestBindings(
        catalog: const IoWorkspaceDirectoryCatalog(),
        index: index,
        now: () => DateTime(2026, 8, 23),
      );
      addTearDown(bindings.dispose);

      expect(await bindings.notifier.openOrActivate(root.path), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(walkCount, 1);
      expect(
        bindings.notifier.activeFileTree.tree.map((node) => node.name),
        <String>['lib'],
      );
      expect(
        bindings.notifier.activeFileTree.tree.single.childrenLoaded,
        isFalse,
      );

      bindings.notifier.setDirectoryExpanded(lib.path, true);
      final loaded = bindings.notifier.activeFileTree.tree.single;
      expect(loaded.childrenLoaded, isTrue);
      expect(loaded.children.single.name, 'main.dart');
    },
  );

  test('missing project is not committed', () async {
    final index = WorkspaceFileIndexController(
      runWalk: (_) async => const <WorkspaceNode>[],
      watchDirectory: (_) => const Stream.empty(),
    );
    addTearDown(index.dispose);
    final bindings = WorkspaceTestBindings(
      catalog: const IoWorkspaceDirectoryCatalog(),
      index: index,
    );
    addTearDown(bindings.dispose);

    expect(
      await bindings.notifier.openOrActivate('/zeta/missing/workspace'),
      isFalse,
    );
    expect(bindings.notifier.state.activeProjectPath, isNull);
    expect(bindings.notifier.activeFileTree.isLoading, isFalse);
  });
}

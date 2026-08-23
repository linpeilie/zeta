import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/workspace_slice/workspace_slice_composition.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

void main() {
  test(
    'runner reads only the requested tree layer and starts the index',
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
      final composition = WorkspaceSliceComposition.create(
        fileIndexController: index,
        now: () => DateTime(2026, 8, 23),
      );
      addTearDown(composition.dispose);

      expect(await composition.store.loadProject(root.path), isTrue);
      await Future<void>.delayed(Duration.zero);
      expect(walkCount, 1);
      expect(composition.store.state.tree.map((node) => node.name), <String>[
        'lib',
      ]);
      expect(composition.store.state.tree.single.childrenLoaded, isFalse);

      composition.store.setDirectoryExpanded(lib.path, true);
      final loaded = composition.store.state.tree.single;
      expect(loaded.childrenLoaded, isTrue);
      expect(loaded.children.single.name, 'main.dart');
    },
  );

  test('runner reports a missing project without committing it', () async {
    final index = WorkspaceFileIndexController(
      runWalk: (_) async => const <WorkspaceNode>[],
      watchDirectory: (_) => const Stream.empty(),
    );
    addTearDown(index.dispose);
    final composition = WorkspaceSliceComposition.create(
      fileIndexController: index,
    );
    addTearDown(composition.dispose);

    await expectLater(
      composition.store.loadProject('/zeta/missing/workspace'),
      throwsA(isA<FileSystemException>()),
    );
    expect(composition.store.state.activeProjectPath, isNull);
    expect(composition.store.state.isLoadingProject, isFalse);
  });
}

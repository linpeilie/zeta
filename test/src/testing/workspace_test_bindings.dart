import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/workspace/application/workspace_file_corpus.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_tree_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/data/io_workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_picker.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

import 'fake_workspace_directory_picker.dart';

/// 测试用 workspace 组合：picker / catalog / 索引都可以注入。
final class WorkspaceTestBindings {
  WorkspaceTestBindings({
    WorkspaceDirectoryPicker? directoryPicker,
    WorkspaceDirectoryCatalog? catalog,
    WorkspaceFileIndexController? index,
    DateTime Function()? now,
  }) : _ownedIndex = index == null,
       _index =
           index ??
           WorkspaceFileIndexController(
             runWalk: (_) async => const <WorkspaceNode>[],
             watchDirectory: (_) => const Stream.empty(),
           ) {
    container = ProviderContainer(
      overrides: [
        workspaceDirectoryPickerProvider.overrideWithValue(
          directoryPicker ?? FakeWorkspaceDirectoryPicker.cancelled(),
        ),
        workspaceDirectoryCatalogProvider.overrideWithValue(
          catalog ?? const IoWorkspaceDirectoryCatalog(),
        ),
        workspaceFileIndexControllerProvider.overrideWithValue(_index),
        if (now != null) workspaceNowProvider.overrideWithValue(now),
      ],
    );
  }

  late final ProviderContainer container;
  final WorkspaceFileIndexController _index;
  final bool _ownedIndex;

  WorkspaceNotifier get notifier => container.read(workspaceProvider.notifier);

  WorkspaceFileCorpusPort get corpus =>
      container.read(workspaceFileCorpusProvider);

  WorkspaceFileIndexController get index =>
      container.read(workspaceFileIndexControllerProvider);

  void dispose() {
    container.dispose();
    if (_ownedIndex) {
      _index.dispose();
    }
  }
}

/// 内存目录树，供 Notifier 单元测试使用。
final class MemoryWorkspaceDirectoryCatalog
    implements WorkspaceDirectoryCatalog {
  MemoryWorkspaceDirectoryCatalog({
    Set<String> existingPaths = const <String>{},
    Map<String, List<WorkspaceNode>> childrenByPath =
        const <String, List<WorkspaceNode>>{},
  }) : existingPaths = Set<String>.of(existingPaths),
       childrenByPath = Map<String, List<WorkspaceNode>>.of(childrenByPath);

  final Set<String> existingPaths;
  final Map<String, List<WorkspaceNode>> childrenByPath;

  @override
  bool exists(String path) => existingPaths.contains(path);

  @override
  List<WorkspaceNode> readChildren(
    String path, {
    Set<String> expandedPaths = const <String>{},
  }) {
    return List<WorkspaceNode>.unmodifiable(
      childrenByPath[path] ?? const <WorkspaceNode>[],
    );
  }
}

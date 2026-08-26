import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_tree_notifier.dart';
import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 由 Workspace Notifier 组装的 @mention 文件语料端口。
///
/// 完整索引未就绪时回退到当前激活项目的惰性目录树。
final class WorkspaceFileCorpus implements WorkspaceFileCorpusPort {
  const WorkspaceFileCorpus({
    required this.readActiveProjectPath,
    required this.readActiveTree,
    required this.fileIndexController,
  });

  final String? Function() readActiveProjectPath;
  final List<WorkspaceNode> Function() readActiveTree;
  final WorkspaceFileIndexController fileIndexController;

  @override
  List<WorkspaceNode> get files {
    final root = readActiveProjectPath();
    if (root != null) {
      final ready = fileIndexController.filesFor(root);
      if (ready != null) {
        return ready;
      }
    }
    return readActiveTree();
  }

  @override
  bool get isReady {
    final root = readActiveProjectPath();
    return root == null || fileIndexController.isReady(root);
  }

  @override
  void addListener(void Function() listener) =>
      fileIndexController.addListener(listener);

  @override
  void removeListener(void Function() listener) =>
      fileIndexController.removeListener(listener);
}

/// 活动工作区的 @mention 语料。
final workspaceFileCorpusProvider = Provider<WorkspaceFileCorpusPort>((ref) {
  final index = ref.watch(workspaceFileIndexControllerProvider);
  return WorkspaceFileCorpus(
    readActiveProjectPath: () => ref.read(workspaceProvider).activeProjectPath,
    readActiveTree: () {
      final path = ref.read(workspaceProvider).activeProjectPath;
      if (path == null) {
        return const <WorkspaceNode>[];
      }
      return ref.read(workspaceFileTreeProvider(path)).tree;
    },
    fileIndexController: index,
  );
}, name: 'workspaceFileCorpus');

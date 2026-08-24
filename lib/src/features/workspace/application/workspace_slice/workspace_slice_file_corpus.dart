import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_index_controller.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_store.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 由 Workspace slice 自己组装的 @mention 文件语料端口。
///
/// 在此之前这个端口是 `IdeShellController` 用四个闭包拼出来的
/// `CallbackWorkspaceFileCorpusPort`——Shell 因此既要知道后台索引的就绪语义，
/// 又要知道惰性目录树的回退规则，而这两件事都是 Workspace 的业务。
///
/// 现在语料的唯一事实来源是 Workspace 的 store 与索引控制器，Shell 只消费端口。
final class WorkspaceSliceFileCorpus implements WorkspaceFileCorpusPort {
  const WorkspaceSliceFileCorpus({
    required this.store,
    required this.fileIndexController,
  });

  final WorkspaceSliceStore store;
  final WorkspaceFileIndexController fileIndexController;

  @override
  List<WorkspaceNode> get files {
    // @mention 候选优先用后台预建的完整语料；未就绪时回退惰性目录树。
    final root = store.state.activeProjectPath;
    if (root != null) {
      final ready = fileIndexController.filesFor(root);
      if (ready != null) {
        return ready;
      }
    }
    return store.state.tree;
  }

  @override
  bool get isReady {
    final root = store.state.activeProjectPath;
    return root == null || fileIndexController.isReady(root);
  }

  @override
  void addListener(void Function() listener) =>
      fileIndexController.addListener(listener);

  @override
  void removeListener(void Function() listener) =>
      fileIndexController.removeListener(listener);
}

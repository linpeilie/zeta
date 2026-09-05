import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 测试用的回调式文件语料端口。
///
/// 生产侧的实现是 `WorkspaceFileCorpus`（由 Workspace Notifier 组装）。
/// 这个回调版本只服务于测试——测试需要用几个闭包临时拼一个语料，
/// 但生产代码不该为此保留一条通用回调路径。
final class CallbackWorkspaceFileCorpusPort implements WorkspaceFileCorpusPort {
  const CallbackWorkspaceFileCorpusPort({
    required this.filesProvider,
    required this.isReadyProvider,
    required this.addListenerCallback,
    required this.removeListenerCallback,
  });

  final List<WorkspaceNode> Function() filesProvider;
  final bool Function() isReadyProvider;
  final void Function(void Function() listener) addListenerCallback;
  final void Function(void Function() listener) removeListenerCallback;

  @override
  List<WorkspaceNode> get files => filesProvider();

  @override
  bool get isReady => isReadyProvider();

  @override
  void addListener(void Function() listener) => addListenerCallback(listener);

  @override
  void removeListener(void Function() listener) =>
      removeListenerCallback(listener);
}

import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 活动工作区的 @mention 文件语料查询端口。
///
/// 调用方只看到中立节点、就绪状态和纯 Dart 监听协议；索引缓存、文件监听与
/// Flutter `Listenable` 都留在端口实现之外。
abstract interface class WorkspaceFileCorpusPort {
  /// 当前活动工作区可查询的文件；完整索引未就绪时可返回惰性树投影。
  List<WorkspaceNode> get files;

  /// 完整后台索引是否已经就绪。
  bool get isReady;

  void addListener(void Function() listener);

  void removeListener(void Function() listener);
}

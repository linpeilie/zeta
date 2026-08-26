import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 工作区目录读取端口。
///
/// application 只依赖这份契约；`dart:io` 实现住在 data 层。
abstract interface class WorkspaceDirectoryCatalog {
  /// 目录是否存在。同步探测，避免 restore 在 widget 测试里挂起 IO Future。
  bool exists(String path);

  /// 读取 [path] 的下一层子节点。
  ///
  /// [expandedPaths] 命中的目录会继续读下一层，用于 restore 时重建展开态。
  /// 不 follow symlink；忽略规则由实现套用领域规则。
  List<WorkspaceNode> readChildren(
    String path, {
    Set<String> expandedPaths = const <String>{},
  });
}

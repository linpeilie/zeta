import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// `TreeView` 节点附带的轻量展示数据。
///
/// 这里故意只保留 UI 交互真正需要的字段，避免把完整领域结构塞进展示组件。
class FileNodeData {
  const FileNodeData({
    required this.path,
    required this.isDirectory,
    this.childrenLoaded = false,
  });

  factory FileNodeData.fromWorkspaceNode(WorkspaceNode node) {
    return FileNodeData(
      path: node.path,
      isDirectory: node.isDirectory,
      childrenLoaded: node.childrenLoaded,
    );
  }

  final String path;
  final bool isDirectory;
  final bool childrenLoaded;
}

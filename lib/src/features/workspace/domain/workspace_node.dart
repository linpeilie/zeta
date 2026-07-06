/// 工作区树中的节点类型。
enum WorkspaceNodeType { directory, file }

/// 工作区文件树的领域节点。
///
/// 该模型不依赖 `TreeView`、图标、颜色等展示细节，只描述文件树自身结构。
class WorkspaceNode {
  const WorkspaceNode({
    required this.path,
    required this.name,
    required this.type,
    this.childrenLoaded = false,
    this.children = const <WorkspaceNode>[],
  });

  /// 文件系统绝对路径。
  final String path;

  /// UI 可直接展示的名称，通常是路径的最后一段。
  final String name;

  /// 领域层节点类型。
  final WorkspaceNodeType type;

  /// 当前目录节点是否已经完成下一层扫描。
  final bool childrenLoaded;

  /// 已加载的子节点列表；文件节点始终为空。
  final List<WorkspaceNode> children;

  /// 是否为目录节点。
  bool get isDirectory => type == WorkspaceNodeType.directory;
}

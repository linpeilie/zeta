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

  /// 复制节点并替换指定字段，供文件树交互更新局部状态时复用。
  WorkspaceNode copyWith({
    bool? childrenLoaded,
    List<WorkspaceNode>? children,
  }) {
    return WorkspaceNode(
      path: path,
      name: name,
      type: type,
      childrenLoaded: childrenLoaded ?? this.childrenLoaded,
      children: children ?? this.children,
    );
  }

  /// 在树中按绝对路径查找节点。
  static WorkspaceNode? findByPath(Iterable<WorkspaceNode> nodes, String path) {
    for (final node in nodes) {
      if (node.path == path) {
        return node;
      }
      final nested = findByPath(node.children, path);
      if (nested != null) {
        return nested;
      }
    }
    return null;
  }

  /// 以不可变方式更新树中的单个节点；未命中时返回原列表。
  static List<WorkspaceNode> updateNode(
    List<WorkspaceNode> nodes,
    String path,
    WorkspaceNode Function(WorkspaceNode node) transform,
  ) {
    final result = _mapNodes(nodes, path, transform);
    return result.$2 ? result.$1 : nodes;
  }

  static (List<WorkspaceNode>, bool) _mapNodes(
    List<WorkspaceNode> nodes,
    String path,
    WorkspaceNode Function(WorkspaceNode node) transform,
  ) {
    var updated = false;
    final nextNodes = <WorkspaceNode>[];
    for (final node in nodes) {
      if (node.path == path) {
        nextNodes.add(transform(node));
        updated = true;
        continue;
      }
      if (node.children.isEmpty) {
        nextNodes.add(node);
        continue;
      }
      final nested = _mapNodes(node.children, path, transform);
      if (!nested.$2) {
        nextNodes.add(node);
        continue;
      }
      nextNodes.add(node.copyWith(children: nested.$1));
      updated = true;
    }
    if (!updated) {
      return (nodes, false);
    }
    return (List<WorkspaceNode>.unmodifiable(nextNodes), true);
  }
}

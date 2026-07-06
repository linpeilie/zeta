import 'dart:io';

import 'package:flutter_treeview/flutter_treeview.dart' as tree;

import 'package:zeta/src/features/workspace/application/workspace_tree_builder.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/workspace/presentation/file_node_data.dart';

/// 将目录直接构造成 `TreeView` 节点，保留旧调用点所需的便捷入口。
tree.Node<FileNodeData> buildDirectoryNode(
  Directory directory, {
  bool expanded = false,
  Set<String> expandedPaths = const <String>{},
}) {
  return mapWorkspaceNodeToTreeNode(
    buildWorkspaceDirectoryNode(
      directory,
      expanded: expanded,
      expandedPaths: expandedPaths,
    ),
  );
}

/// 将目录下一层直接映射为 `TreeView` 节点列表。
List<tree.Node<FileNodeData>> buildDirectoryChildren(
  Directory directory, {
  Set<String> expandedPaths = const <String>{},
}) {
  return mapWorkspaceNodesToTreeNodes(
    buildWorkspaceDirectoryChildren(directory, expandedPaths: expandedPaths),
  );
}

/// 将领域节点映射为 `TreeView` 节点。
tree.Node<FileNodeData> mapWorkspaceNodeToTreeNode(WorkspaceNode node) {
  return tree.Node<FileNodeData>(
    key: node.path,
    label: node.name,
    expanded: node.childrenLoaded,
    parent: node.isDirectory,
    data: FileNodeData.fromWorkspaceNode(node),
    children: mapWorkspaceNodesToTreeNodes(node.children),
  );
}

/// 将领域节点列表批量映射为 `TreeView` 节点列表。
List<tree.Node<FileNodeData>> mapWorkspaceNodesToTreeNodes(
  Iterable<WorkspaceNode> nodes,
) {
  return nodes.map(mapWorkspaceNodeToTreeNode).toList(growable: false);
}

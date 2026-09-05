import 'dart:io';

import 'package:zeta/src/features/workspace/data/workspace_tree_builder.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 基于本机文件系统的目录目录读取。
final class IoWorkspaceDirectoryCatalog implements WorkspaceDirectoryCatalog {
  const IoWorkspaceDirectoryCatalog();

  @override
  bool exists(String path) => Directory(path).existsSync();

  @override
  List<WorkspaceNode> readChildren(
    String path, {
    Set<String> expandedPaths = const <String>{},
  }) {
    return buildWorkspaceDirectoryChildren(
      Directory(path),
      expandedPaths: expandedPaths,
    );
  }
}

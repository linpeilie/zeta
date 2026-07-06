import 'dart:io';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_rules.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 构建单个目录的领域节点。
///
/// 当目录处于展开态或命中 [expandedPaths] 时，才会继续读取其下一层子节点。
WorkspaceNode buildWorkspaceDirectoryNode(
  Directory directory, {
  bool expanded = false,
  Set<String> expandedPaths = const <String>{},
}) {
  final path = directory.path;
  final shouldLoadChildren = expanded || expandedPaths.contains(path);
  return WorkspaceNode(
    path: path,
    name: fileName(path),
    type: WorkspaceNodeType.directory,
    childrenLoaded: shouldLoadChildren,
    children: shouldLoadChildren
        ? List<WorkspaceNode>.unmodifiable(
            buildWorkspaceDirectoryChildren(
              directory,
              expandedPaths: expandedPaths,
            ),
          )
        : const <WorkspaceNode>[],
  );
}

/// 读取目录下一层实体并转换为领域节点。
///
/// 该函数只负责文件系统扫描、过滤与排序，不包含任何 Flutter 或 TreeView 逻辑。
List<WorkspaceNode> buildWorkspaceDirectoryChildren(
  Directory directory, {
  Set<String> expandedPaths = const <String>{},
}) {
  final entities = <FileSystemEntity>[];
  try {
    entities.addAll(directory.listSync(followLinks: false));
  } on FileSystemException {
    return const <WorkspaceNode>[];
  }

  final visibleEntities = entities
      .where(_isSupportedWorkspaceEntity)
      .where((entity) {
        return !isIgnoredWorkspaceEntryName(fileName(entity.path));
      })
      .toList(growable: false);

  visibleEntities.sort(_compareWorkspaceEntities);

  return visibleEntities
      .map(
        (entity) =>
            _buildWorkspaceEntityNode(entity, expandedPaths: expandedPaths),
      )
      .nonNulls
      .toList(growable: false);
}

WorkspaceNode? _buildWorkspaceEntityNode(
  FileSystemEntity entity, {
  Set<String> expandedPaths = const <String>{},
}) {
  final type = _entityType(entity);
  if (type == FileSystemEntityType.directory) {
    return buildWorkspaceDirectoryNode(
      Directory(entity.path),
      expandedPaths: expandedPaths,
    );
  }
  if (type == FileSystemEntityType.file) {
    final path = entity.path;
    return WorkspaceNode(
      path: path,
      name: fileName(path),
      type: WorkspaceNodeType.file,
    );
  }
  return null;
}

bool _isSupportedWorkspaceEntity(FileSystemEntity entity) {
  final type = _entityType(entity);
  return type == FileSystemEntityType.directory ||
      type == FileSystemEntityType.file;
}

int _compareWorkspaceEntities(FileSystemEntity a, FileSystemEntity b) {
  final aType = _entityType(a);
  final bType = _entityType(b);
  final aIsDirectory = aType == FileSystemEntityType.directory;
  final bIsDirectory = bType == FileSystemEntityType.directory;
  if (aIsDirectory != bIsDirectory) {
    return aIsDirectory ? -1 : 1;
  }
  return fileName(
    a.path,
  ).toLowerCase().compareTo(fileName(b.path).toLowerCase());
}

FileSystemEntityType _entityType(FileSystemEntity entity) {
  try {
    return entity.statSync().type;
  } on FileSystemException {
    return FileSystemEntityType.notFound;
  }
}

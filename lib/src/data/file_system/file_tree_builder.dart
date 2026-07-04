import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_treeview/flutter_treeview.dart' as tree;

import '../../ui/core/app_theme.dart';
import 'file_node_data.dart';
import 'path_utils.dart';

const Set<String> ignoredFileTreeNames = {
  '.dart_tool',
  '.git',
  '.idea',
  '.vscode',
  'build',
  'node_modules',
};

tree.Node<FileNodeData> buildDirectoryNode(
  Directory directory, {
  bool expanded = false,
  Set<String> expandedPaths = const <String>{},
}) {
  final path = directory.path;
  final shouldLoadChildren = expanded || expandedPaths.contains(path);
  return tree.Node<FileNodeData>(
    key: path,
    label: fileName(path),
    expanded: shouldLoadChildren,
    parent: true,
    icon: Icons.folder_rounded,
    iconColor: ideWarningColor,
    selectedIconColor: ideAccentColor,
    data: FileNodeData(
      path: path,
      isDirectory: true,
      childrenLoaded: shouldLoadChildren,
    ),
    children: shouldLoadChildren
        ? buildDirectoryChildren(directory, expandedPaths: expandedPaths)
        : const [],
  );
}

List<tree.Node<FileNodeData>> buildDirectoryChildren(
  Directory directory, {
  Set<String> expandedPaths = const <String>{},
}) {
  final entities = <FileSystemEntity>[];
  try {
    entities.addAll(directory.listSync(followLinks: false));
  } on FileSystemException {
    return const [];
  }

  entities.removeWhere((entity) {
    final name = fileName(entity.path);
    if (ignoredFileTreeNames.contains(name)) {
      return true;
    }
    final type = entity.statSync().type;
    return type != FileSystemEntityType.directory &&
        type != FileSystemEntityType.file;
  });

  entities.sort((a, b) {
    final aIsDirectory = a.statSync().type == FileSystemEntityType.directory;
    final bIsDirectory = b.statSync().type == FileSystemEntityType.directory;
    if (aIsDirectory != bIsDirectory) {
      return aIsDirectory ? -1 : 1;
    }
    return fileName(
      a.path,
    ).toLowerCase().compareTo(fileName(b.path).toLowerCase());
  });

  return entities
      .map((entity) => _buildEntityNode(entity, expandedPaths: expandedPaths))
      .nonNulls
      .toList(growable: false);
}

tree.Node<FileNodeData>? _buildEntityNode(
  FileSystemEntity entity, {
  Set<String> expandedPaths = const <String>{},
}) {
  final stat = entity.statSync();
  if (stat.type == FileSystemEntityType.directory) {
    return buildDirectoryNode(
      Directory(entity.path),
      expandedPaths: expandedPaths,
    );
  }
  if (stat.type == FileSystemEntityType.file) {
    final path = entity.path;
    return tree.Node<FileNodeData>(
      key: path,
      label: fileName(path),
      icon: Icons.insert_drive_file_outlined,
      iconColor: ideMutedTextColor,
      selectedIconColor: ideAccentColor,
      data: FileNodeData(path: path, isDirectory: false),
    );
  }
  return null;
}

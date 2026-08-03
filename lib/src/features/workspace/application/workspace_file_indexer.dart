import 'dart:io';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_rules.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 递归扫描工作区根目录，返回扁平文件节点语料。
///
/// - 结果顺序为 DFS 遍历序（确定性，供空查询取前 N）。
/// - 尊重 [isIgnoredWorkspaceEntryName]，`.git`/`build`/`node_modules` 等目录整枝跳过。
/// - 不跟随符号链接（`followLinks: false`），避免逃逸工作区或成环。
/// - [maxFiles] 是防病态大仓的安全阀：达到上限即停止遍历并返回已收集部分。
List<WorkspaceNode> buildWorkspaceFileCorpus(
  Directory root, {
  int maxFiles = 50000,
}) {
  final files = <WorkspaceNode>[];

  void visit(Directory directory) {
    if (files.length >= maxFiles) {
      return;
    }
    List<FileSystemEntity> entities;
    try {
      entities = directory.listSync(followLinks: false);
    } on FileSystemException {
      return;
    }
    for (final entity in entities) {
      if (files.length >= maxFiles) {
        return;
      }
      FileSystemEntityType type;
      try {
        type = FileSystemEntity.typeSync(entity.path, followLinks: false);
      } on FileSystemException {
        continue;
      }
      if (type == FileSystemEntityType.directory) {
        if (!isIgnoredWorkspaceEntryName(fileName(entity.path))) {
          visit(Directory(entity.path));
        }
      } else if (type == FileSystemEntityType.file) {
        final path = entity.path;
        files.add(
          WorkspaceNode(
            path: path,
            name: fileName(path),
            type: WorkspaceNodeType.file,
          ),
        );
      }
      // link 及其余类型（socket/fifo 等）不在语料内。
    }
  }

  visit(root);
  return files;
}

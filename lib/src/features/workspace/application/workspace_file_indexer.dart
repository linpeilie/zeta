import 'dart:io';

import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_rules.dart';
import 'package:zeta/src/features/workspace/domain/workspace_gitignore.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

/// 递归扫描工作区根目录，返回扁平文件节点语料。
///
/// - 结果顺序为 DFS 遍历序（确定性，供空查询取前 N）。
/// - 尊重 [isIgnoredWorkspaceEntryName]（Zeta 策略：`.git`/`build`/`node_modules` 等
///   整枝跳过，不受 gitignore `!` 否定影响）。
/// - 感知 git 忽略：遍历时逐层读 `.gitignore`，并加载仓库根 `.git/info/exclude`
///   （存在 `.git` 时）；被 git 忽略的文件跳过、目录剪枝（存在否定模式时下钻判定）。
/// - 不跟随符号链接（`followLinks: false`），避免逃逸工作区或成环。
/// - [maxFiles] 是防病态大仓的安全阀：达到上限即停止遍历并返回已收集部分。
/// - [caseSensitive] 默认按平台（Windows 不区分大小写，对齐 git `core.ignorecase`）；
///   测试可显式注入。
List<WorkspaceNode> buildWorkspaceFileCorpus(
  Directory root, {
  int maxFiles = 50000,
  bool? caseSensitive,
}) {
  final files = <WorkspaceNode>[];
  final resolvedCaseSensitive = caseSensitive ?? !Platform.isWindows;
  final matcher = GitignoreMatcher(caseSensitive: resolvedCaseSensitive);

  // 仓库级 exclude：`.git/info/exclude`（仅当仓库根存在 `.git`）。
  final gitDir = Directory('${root.path}${Platform.pathSeparator}.git');
  if (gitDir.existsSync()) {
    final exclude = File(
      '${gitDir.path}${Platform.pathSeparator}info${Platform.pathSeparator}exclude',
    );
    if (exclude.existsSync()) {
      try {
        matcher.pushLayer(
          root.path,
          parseGitignore(
            exclude.readAsStringSync(),
            caseSensitive: resolvedCaseSensitive,
          ),
        );
      } on FileSystemException {
        // 读取失败不阻断遍历。
      }
    }
  }

  void visit(Directory directory) {
    if (files.length >= maxFiles) {
      return;
    }
    var pushedLayer = false;
    final own = File('${directory.path}${Platform.pathSeparator}.gitignore');
    if (own.existsSync()) {
      try {
        matcher.pushLayer(
          directory.path,
          parseGitignore(
            own.readAsStringSync(),
            caseSensitive: resolvedCaseSensitive,
          ),
        );
        pushedLayer = true;
      } on FileSystemException {
        // 读取失败不阻断遍历。
      }
    }
    try {
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
        final name = fileName(entity.path);
        // Zeta 硬编码策略：始终跳过，不受 gitignore `!` 否定影响。
        if (isIgnoredWorkspaceEntryName(name)) {
          continue;
        }
        final isDir = type == FileSystemEntityType.directory;
        if (matcher.isIgnored(entity.path, isDir: isDir)) {
          // 目录被忽略时剪枝；存在否定模式时仍下钻，判定子项是否被 `!` 重新包含。
          if (isDir && matcher.hasNegation) {
            visit(Directory(entity.path));
          }
          continue;
        }
        if (isDir) {
          visit(Directory(entity.path));
        } else if (type == FileSystemEntityType.file) {
          files.add(
            WorkspaceNode(
              path: entity.path,
              name: name,
              type: WorkspaceNodeType.file,
            ),
          );
        }
        // link 及其余类型（socket/fifo 等）不在语料内。
      }
    } finally {
      if (pushedLayer) {
        matcher.popLayer();
      }
    }
  }

  visit(root);
  return files;
}

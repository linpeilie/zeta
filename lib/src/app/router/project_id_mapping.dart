import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/workspace/domain/workspace_project.dart';

/// 项目路径 ↔ 不透明 `projectId` 双向映射。
///
/// `projectId` = 规范化路径 sha256 的前 12 位十六进制。本机路径不进 URL。
final class ProjectIdMapping {
  final Map<String, String> _idByPath = <String, String>{};
  final Map<String, String> _pathById = <String, String>{};

  /// 与工作区共用路径身份规则；大小写敏感目录不能在路由中合并。
  static String hashPath(String path) {
    final normalized = normalizeWorkspaceProjectPath(path);
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
  }

  /// 先验证整批映射再发布；碰撞时不覆盖另一项目或留下半份映射。
  void syncProjects(Iterable<String> openPaths) {
    final ids = <String, String>{};
    final paths = <String, String>{};
    for (final rawPath in openPaths) {
      final path = normalizeWorkspaceProjectPath(rawPath);
      final id = hashPath(path);
      if (paths.containsKey(id) && paths[id] != path) {
        throw StateError('Project route identity collision');
      }
      ids[path] = id;
      paths[id] = path;
    }
    _idByPath
      ..clear()
      ..addAll(ids);
    _pathById
      ..clear()
      ..addAll(paths);
  }

  String? idForPath(String path) =>
      _idByPath[normalizeWorkspaceProjectPath(path)];

  String? pathForId(String id) => _pathById[id];

  Set<String> get allIds => _pathById.keys.toSet();
}

/// 单例。可变对象用 plain Provider 持有；同步只经 refresh 桥。
final projectIdMappingProvider = Provider<ProjectIdMapping>(
  (ref) => ProjectIdMapping(),
  name: 'projectIdMapping',
);

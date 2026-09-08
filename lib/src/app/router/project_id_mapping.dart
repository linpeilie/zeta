import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 项目路径 ↔ 不透明 `projectId` 双向映射。
///
/// `projectId` = 规范化路径 sha256 的前 12 位十六进制。本机路径不进 URL。
final class ProjectIdMapping {
  final Map<String, String> _idByPath = <String, String>{};
  final Map<String, String> _pathById = <String, String>{};

  /// 输入为 `WorkspaceProject.path` 形态；散列前再规范化，
  /// 保证 Windows 下大小写与分隔符差异得到同一 id。
  static String hashPath(String path) {
    final normalized = path
        .trim()
        .replaceAll(r'\', '/')
        .replaceAll(RegExp('/+\$'), '')
        .toLowerCase();
    return sha256.convert(utf8.encode(normalized)).toString().substring(0, 12);
  }

  /// 随 `openProjects` 存废建立或回收。
  void syncProjects(Iterable<String> openPaths) {
    final live = openPaths.toSet();
    _idByPath.removeWhere((path, _) => !live.contains(path));
    _pathById.removeWhere((_, path) => !live.contains(path));
    for (final path in live) {
      final id = hashPath(path);
      _idByPath[path] = id;
      _pathById[id] = path;
    }
  }

  String? idForPath(String path) {
    final direct = _idByPath[path];
    if (direct != null) {
      return direct;
    }
    final id = hashPath(path);
    return _pathById.containsKey(id) ? id : null;
  }

  String? pathForId(String id) => _pathById[id];

  Set<String> get allIds => _pathById.keys.toSet();
}

/// 单例。可变对象用 plain Provider 持有；同步只经 refresh 桥。
final projectIdMappingProvider = Provider<ProjectIdMapping>(
  (ref) => ProjectIdMapping(),
  name: 'projectIdMapping',
);

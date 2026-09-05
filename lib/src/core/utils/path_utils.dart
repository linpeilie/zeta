String fileName(String path) {
  final normalized = path.replaceAll('\\', '/');
  final parts = normalized.split('/').where((part) => part.isNotEmpty).toList();
  if (parts.isEmpty) {
    return path;
  }
  return parts.last;
}

String formatBytes(int bytes) {
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(1)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// 过滤出确实存在的目录路径（去重、保序）。
///
/// 目录存在性由调用方注入的探针判定，本模块保持纯 Dart。
List<String> existingDirectoryPaths(
  Iterable<String> paths, {
  required bool Function(String path) directoryExists,
}) {
  final existingPaths = <String>[];
  final seenPaths = <String>{};

  for (final path in paths) {
    if (path.isEmpty || !seenPaths.add(path)) {
      continue;
    }
    if (directoryExists(path)) {
      existingPaths.add(path);
    }
  }

  return existingPaths;
}

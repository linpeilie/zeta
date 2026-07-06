import 'dart:io';

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

List<String> existingDirectoryPaths(Iterable<String> paths) {
  final existingPaths = <String>[];
  final seenPaths = <String>{};

  for (final path in paths) {
    if (path.isEmpty || !seenPaths.add(path)) {
      continue;
    }
    if (Directory(path).existsSync()) {
      existingPaths.add(path);
    }
  }

  return existingPaths;
}

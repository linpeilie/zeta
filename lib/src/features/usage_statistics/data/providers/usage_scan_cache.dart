import 'dart:convert';
import 'dart:io';

/// 为本地用量源文件生成稳定的 64-bit FNV-1a 标识。
///
/// 该标识只用于派生缓存匹配，避免把 Agent CLI session 文件路径写入 `~/.zeta`。
String usageSourceId(String sourcePath) {
  var hash = 0xcbf29ce484222325;
  for (final byte in utf8.encode(sourcePath)) {
    hash ^= byte;
    hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

/// 文件变更指纹：size + mtime(微秒)。
String usageFileFingerprint(FileStat stat) {
  return '${stat.size}:${stat.modified.microsecondsSinceEpoch}';
}

/// 判定派生索引是否可直接复用（跳过正文解析）。
bool usageCacheHit({
  required String? cachedFingerprint,
  required String currentFingerprint,
  required bool forceRefresh,
}) {
  if (forceRefresh) {
    return false;
  }
  return cachedFingerprint != null && cachedFingerprint == currentFingerprint;
}

/// 从缓存 map 查找条目：优先 sourceId，兼容历史 path 键。
T? findUsageCachedSession<T extends Object>(
  Map<String, T> cachedSessions,
  String sourcePath,
) {
  return cachedSessions[usageSourceId(sourcePath)] ??
      cachedSessions[sourcePath];
}

import 'dart:convert';

import 'package:zeta_foundation/zeta_foundation.dart';

final _log = zetaLoggerFor('zeta.agent.claude_code.hidden_threads');

/// Claude Code 本地历史的 Zeta 隐藏列表存储边界。
abstract interface class ClaudeCodeHiddenThreadStore {
  Future<Set<String>> load();

  Future<void> save(Set<String> hiddenThreadKeys);
}

/// `~/.zeta` 内版本化、宽容解码的 Claude Code 隐藏列表。
///
/// JSON 白名单只有 `version` 与 `hiddenThreadKeys`；不保存 prompt、回复、工具
/// 输出或 Provider raw payload。
final class FileClaudeCodeHiddenThreadStore
    implements ClaudeCodeHiddenThreadStore {
  /// [storage] 由组合层注入：应用传 `FileStorageService`，测试传内存实现。
  /// 适配器自己不碰 `dart:io`，这样它可以随 Provider 包脱离根 app。
  FileClaudeCodeHiddenThreadStore({required StorageService storage})
    : _file = storage;

  static const int currentVersion = 1;

  final StorageService _file;

  @override
  Future<Set<String>> load() async {
    try {
      final source = await _file.read();
      if (source == null || source.trim().isEmpty) {
        return <String>{};
      }
      final decoded = jsonDecode(source);
      if (decoded is! Map) {
        return <String>{};
      }
      if (decoded['version'] != currentVersion) {
        return <String>{};
      }
      final entries = decoded['hiddenThreadKeys'];
      if (entries is! List) {
        return <String>{};
      }
      return <String>{
        for (final entry in entries)
          if (_normalizeHiddenKey(entry) case final String key) key,
      };
    } catch (error) {
      // 派生隐藏列表损坏不能阻断 Provider 启动；回退为空列表。
      _log.w(
        'Could not load Claude Code hidden threads (${error.runtimeType})',
      );
      return <String>{};
    }
  }

  @override
  Future<void> save(Set<String> hiddenThreadKeys) async {
    final entries = <String>[
      for (final entry in hiddenThreadKeys)
        if (_normalizeHiddenKey(entry) case final String key) key,
    ]..sort();
    await _file.write(
      jsonEncode(<String, Object?>{
        'version': currentVersion,
        'hiddenThreadKeys': entries,
      }),
    );
  }
}

String? _normalizeHiddenKey(Object? value) {
  if (value is! String) {
    return null;
  }
  final key = value.trim();
  if (key.isEmpty ||
      key.length > 4096 ||
      key.contains('\n') ||
      key.contains('\r')) {
    return null;
  }
  return key;
}

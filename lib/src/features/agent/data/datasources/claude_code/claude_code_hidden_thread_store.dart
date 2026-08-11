import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/storage/atomic_text_file.dart';

final _log = loggerFor('zeta.agent.claude_code.hidden_threads');

/// Claude Code 本地历史的 Zeta 隐藏列表存储边界。
abstract interface class ClaudeCodeHiddenThreadStore {
  Future<Set<String>> load();

  Future<void> save(Set<String> hiddenThreadKeys);
}

/// 不落盘的隐藏列表，供测试和无文件持久化宿主使用。
final class MemoryClaudeCodeHiddenThreadStore
    implements ClaudeCodeHiddenThreadStore {
  Set<String> _hiddenThreadKeys = <String>{};

  @override
  Future<Set<String>> load() async => Set<String>.of(_hiddenThreadKeys);

  @override
  Future<void> save(Set<String> hiddenThreadKeys) async {
    _hiddenThreadKeys = Set<String>.of(hiddenThreadKeys);
  }
}

/// `~/.zeta` 内版本化、宽容解码的 Claude Code 隐藏列表。
///
/// JSON 白名单只有 `version` 与 `hiddenThreadKeys`；不保存 prompt、回复、工具
/// 输出或 Provider raw payload。
final class FileClaudeCodeHiddenThreadStore
    implements ClaudeCodeHiddenThreadStore {
  FileClaudeCodeHiddenThreadStore({required File file})
    : _file = AtomicTextFile(file);

  static const int currentVersion = 1;

  final AtomicTextFile _file;

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
      final version = decoded['version'];
      final entries = switch (version) {
        currentVersion => decoded['hiddenThreadKeys'],
        0 => decoded['hiddenThreads'],
        _ => null,
      };
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

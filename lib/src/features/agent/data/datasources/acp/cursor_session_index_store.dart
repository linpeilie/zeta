import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Cursor 会话最小索引的持久化版本。
const int cursorSessionIndexVersion = 1;

/// Cursor 会话索引的旧版 shared_preferences key。
const String cursorSessionIndexStorageKey = 'zeta.agent.cursor.sessions.v1';

/// 单条 Cursor 会话索引。
///
/// 只保存列表、恢复和路由所需的最小 metadata；prompt、回复正文、token 和完整
/// provider payload 不会写入本地索引。
class CursorSessionIndexEntry {
  CursorSessionIndexEntry({
    required this.sessionId,
    required this.providerId,
    required String workspacePath,
    required this.createdAt,
    required this.updatedAt,
    this.title,
    this.status = AgentThreadRuntimeStatus.idle,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : workspacePath =
           normalizeCursorWorkspacePath(workspacePath) ?? workspacePath,
       metadata = Map<String, Object?>.unmodifiable(
         sanitizeCursorSessionMetadata(metadata),
       );

  final String sessionId;
  final String providerId;
  final String workspacePath;
  final String? title;
  final DateTime createdAt;
  final DateTime updatedAt;
  final AgentThreadRuntimeStatus status;
  final Map<String, Object?> metadata;

  CursorSessionIndexEntry copyWith({
    String? providerId,
    String? workspacePath,
    Object? title = _unchanged,
    DateTime? createdAt,
    DateTime? updatedAt,
    AgentThreadRuntimeStatus? status,
    Map<String, Object?>? metadata,
  }) {
    return CursorSessionIndexEntry(
      sessionId: sessionId,
      providerId: providerId ?? this.providerId,
      workspacePath: workspacePath ?? this.workspacePath,
      title: identical(title, _unchanged) ? this.title : title as String?,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      status: status ?? this.status,
      metadata: metadata ?? this.metadata,
    );
  }

  AgentThreadSummary toThreadSummary() {
    return AgentThreadSummary(
      id: sessionId,
      providerId: providerId,
      projectPath: workspacePath,
      title: title,
      // Cursor 没有本地 JSONL 路径；这里保存 provider 恢复所需的 workspace locator。
      sessionPath: workspacePath,
      preview: '',
      createdAt: createdAt,
      updatedAt: updatedAt,
      recencyAt: updatedAt,
      status: status,
      raw: <String, Object?>{
        'source': 'zeta-cursor-session-index',
        if (metadata.isNotEmpty) 'metadata': metadata,
      },
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'sessionId': sessionId,
      'providerId': providerId,
      'workspacePath': workspacePath,
      'title': title,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'updatedAt': updatedAt.toUtc().toIso8601String(),
      'status': status.name,
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }

  /// 宽容读取当前或旧版最小索引条目；损坏条目返回 null。
  static CursorSessionIndexEntry? tryDecode(Object? value) {
    final map = _asMap(value);
    if (map == null) {
      return null;
    }
    final sessionId = _nonEmptyString(map['sessionId'] ?? map['id']);
    final workspacePath = _nonEmptyString(
      map['workspacePath'] ?? map['cwd'] ?? map['projectPath'],
    );
    if (sessionId == null || workspacePath == null) {
      return null;
    }
    final createdAt = _decodeDateTime(map['createdAt']);
    final updatedAt = _decodeDateTime(map['updatedAt']);
    final fallbackAt = updatedAt ?? createdAt;
    if (fallbackAt == null) {
      return null;
    }
    return CursorSessionIndexEntry(
      sessionId: sessionId,
      providerId: _nonEmptyString(map['providerId']) ?? cursorAgentProviderId,
      workspacePath: workspacePath,
      title: _optionalString(map['title']),
      createdAt: createdAt ?? fallbackAt,
      updatedAt: updatedAt ?? fallbackAt,
      status: _decodeStatus(map['status']),
      metadata:
          _asMap(map['metadata'] ?? map['_meta']) ?? const <String, Object?>{},
    );
  }
}

/// Cursor 会话索引快照。
class CursorSessionIndexSnapshot {
  CursorSessionIndexSnapshot({
    this.version = cursorSessionIndexVersion,
    Iterable<CursorSessionIndexEntry> sessions =
        const <CursorSessionIndexEntry>[],
  }) : sessions = List<CursorSessionIndexEntry>.unmodifiable(sessions);

  final int version;
  final List<CursorSessionIndexEntry> sessions;

  CursorSessionIndexEntry? find(String sessionId) {
    for (final session in sessions) {
      if (session.sessionId == sessionId) {
        return session;
      }
    }
    return null;
  }

  CursorSessionIndexSnapshot upsert(CursorSessionIndexEntry entry) {
    final next = <CursorSessionIndexEntry>[];
    var replaced = false;
    for (final existing in sessions) {
      if (existing.sessionId != entry.sessionId) {
        next.add(existing);
        continue;
      }
      replaced = true;
      next.add(
        entry.copyWith(
          createdAt: existing.createdAt.isBefore(entry.createdAt)
              ? existing.createdAt
              : entry.createdAt,
        ),
      );
    }
    if (!replaced) {
      next.add(entry);
    }
    next.sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return CursorSessionIndexSnapshot(sessions: next);
  }

  CursorSessionIndexSnapshot remove(String sessionId) {
    return CursorSessionIndexSnapshot(
      sessions: sessions.where((entry) => entry.sessionId != sessionId),
    );
  }

  Map<String, Object?> toJson() {
    return <String, Object?>{
      'version': cursorSessionIndexVersion,
      'sessions': sessions.map((entry) => entry.toJson()).toList(),
    };
  }

  /// 宽容读取索引；未知字段、旧版本、重复和损坏条目不会阻塞启动。
  static CursorSessionIndexSnapshot tryDecode(Object? value) {
    final map = _asMap(value);
    final rawSessions = value is List
        ? value
        : map?['sessions'] ?? map?['entries'];
    if (rawSessions is! List) {
      return CursorSessionIndexSnapshot();
    }

    final deduplicated = <String, CursorSessionIndexEntry>{};
    for (final raw in rawSessions) {
      final entry = CursorSessionIndexEntry.tryDecode(raw);
      if (entry == null) {
        continue;
      }
      final previous = deduplicated[entry.sessionId];
      if (previous == null || !entry.updatedAt.isBefore(previous.updatedAt)) {
        deduplicated[entry.sessionId] = entry;
      }
    }
    final sessions = deduplicated.values.toList()
      ..sort((left, right) => right.updatedAt.compareTo(left.updatedAt));
    return CursorSessionIndexSnapshot(sessions: sessions);
  }
}

/// Cursor 会话最小索引仓库。
abstract class CursorSessionIndexStore {
  Future<CursorSessionIndexSnapshot> load();

  /// 在同一进程内串行执行一次 read-modify-write，避免并发更新丢失其他 session。
  Future<void> update(
    CursorSessionIndexSnapshot Function(CursorSessionIndexSnapshot current)
    transform,
  );
}

/// 基于 JSON 文件的生产索引仓库。
class FileCursorSessionIndexStore implements CursorSessionIndexStore {
  FileCursorSessionIndexStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;
  static final _MutationQueue _mutationQueue = _MutationQueue();

  @override
  Future<CursorSessionIndexSnapshot> load() async {
    try {
      return _decodeIndex(await _storage.read());
    } on IOException {
      // 索引文件不可读时回退为空列表，后续仍可从官方 session/list 回填。
      return CursorSessionIndexSnapshot();
    } on FormatException {
      // 索引文件不可读时回退为空列表，后续仍可从官方 session/list 回填。
      return CursorSessionIndexSnapshot();
    }
  }

  @override
  Future<void> update(
    CursorSessionIndexSnapshot Function(CursorSessionIndexSnapshot current)
    transform,
  ) {
    return _mutationQueue.run(() async {
      final current = await load();
      final next = transform(current);
      await _storage.write(jsonEncode(next.toJson()));
    });
  }
}

/// 通过 JSON 回调读写的索引仓库，供单元测试或宿主环境注入。
class CallbackCursorSessionIndexStore implements CursorSessionIndexStore {
  CallbackCursorSessionIndexStore({
    required this.loadJson,
    required this.saveJson,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;
  final _MutationQueue _mutationQueue = _MutationQueue();

  @override
  Future<CursorSessionIndexSnapshot> load() async {
    return _decodeIndex(await loadJson());
  }

  @override
  Future<void> update(
    CursorSessionIndexSnapshot Function(CursorSessionIndexSnapshot current)
    transform,
  ) {
    return _mutationQueue.run(() async {
      final next = transform(await load());
      await saveJson(jsonEncode(next.toJson()));
    });
  }
}

/// 内存索引仓库。
class MemoryCursorSessionIndexStore implements CursorSessionIndexStore {
  MemoryCursorSessionIndexStore([CursorSessionIndexSnapshot? initial])
    : _snapshot = initial ?? CursorSessionIndexSnapshot();

  CursorSessionIndexSnapshot _snapshot;
  final _MutationQueue _mutationQueue = _MutationQueue();

  @override
  Future<CursorSessionIndexSnapshot> load() async => _snapshot;

  @override
  Future<void> update(
    CursorSessionIndexSnapshot Function(CursorSessionIndexSnapshot current)
    transform,
  ) {
    return _mutationQueue.run(() async {
      _snapshot = transform(_snapshot);
    });
  }
}

/// 规范化 Cursor workspace，用于索引过滤和 workspace-scoped peer 复用。
String? normalizeCursorWorkspacePath(String? value) {
  final trimmed = value?.trim();
  if (trimmed == null || trimmed.isEmpty) {
    return null;
  }
  var normalized = Directory(trimmed).absolute.path;
  while (normalized.length > 1 &&
      (normalized.endsWith('/') || normalized.endsWith('\\'))) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}

bool cursorWorkspacePathsEqual(String? left, String? right) {
  if (left == null || right == null) {
    return left == right;
  }
  return Platform.isWindows
      ? left.toLowerCase() == right.toLowerCase()
      : left == right;
}

/// 只保留适合进入最小索引的短标量 metadata，并过滤可能包含正文或凭据的字段。
Map<String, Object?> sanitizeCursorSessionMetadata(
  Map<String, Object?> metadata,
) {
  final sanitized = <String, Object?>{};
  for (final entry in metadata.entries) {
    final key = entry.key.trim();
    if (key.isEmpty || key.length > 64 || _sensitiveMetadataKey(key)) {
      continue;
    }
    final value = entry.value;
    if (value is String) {
      if (value.length <= 512) {
        sanitized[key] = value;
      }
    } else if (value is num || value is bool) {
      sanitized[key] = value;
    }
  }
  return sanitized;
}

CursorSessionIndexSnapshot _decodeIndex(String? value) {
  if (value == null || value.trim().isEmpty) {
    return CursorSessionIndexSnapshot();
  }
  try {
    return CursorSessionIndexSnapshot.tryDecode(jsonDecode(value));
  } catch (_) {
    return CursorSessionIndexSnapshot();
  }
}

class _MutationQueue {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _tail = _tail.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }
}

const Object _unchanged = Object();

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

String? _nonEmptyString(Object? value) {
  final text = value?.toString().trim();
  return text == null || text.isEmpty ? null : text;
}

String? _optionalString(Object? value) {
  if (value == null) {
    return null;
  }
  return value.toString();
}

DateTime? _decodeDateTime(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(value, isUtc: true);
  }
  if (value is num) {
    return DateTime.fromMillisecondsSinceEpoch(value.toInt(), isUtc: true);
  }
  return DateTime.tryParse(value?.toString() ?? '')?.toUtc();
}

AgentThreadRuntimeStatus _decodeStatus(Object? value) {
  final name = value?.toString();
  for (final status in AgentThreadRuntimeStatus.values) {
    if (status.name == name) {
      return status;
    }
  }
  return AgentThreadRuntimeStatus.idle;
}

bool _sensitiveMetadataKey(String key) {
  final normalized = key.toLowerCase();
  return const <String>[
    'prompt',
    'message',
    'content',
    'auth',
    'token',
    'secret',
    'api_key',
    'apikey',
  ].any(normalized.contains);
}

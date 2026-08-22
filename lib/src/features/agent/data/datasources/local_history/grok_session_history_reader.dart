import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_chat_history_parser.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_updates_history_parser.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = loggerFor('zeta.agent.grok_session_history');

/// 从 `~/.grok/sessions` 本地目录读取 Grok session 列表与历史。
///
/// Grok ACP 未实现 `session/list`，项目 thread 列表依赖本地存储扫描。
/// 历史优先解析 `updates.jsonl`（与 session/load 回放同构），降级
/// `chat_history.jsonl`。
class GrokSessionHistoryReader {
  GrokSessionHistoryReader({
    this.grokHome,
    this.homeResolver,
    this.updatesParser = const GrokUpdatesHistoryParser(),
    this.chatHistoryParser = const GrokChatHistoryParser(),
  });

  /// 测试可注入的 Grok 家目录。
  final String? grokHome;

  /// 测试可注入的用户 home 解析。
  final String? Function()? homeResolver;

  final GrokUpdatesHistoryParser updatesParser;
  final GrokChatHistoryParser chatHistoryParser;

  /// 解析 Grok 家目录：`GROK_HOME` > 注入路径 > `~/.grok`。
  String resolveGrokHome({Map<String, String>? environment}) {
    final env = environment ?? Platform.environment;
    final fromEnv = env['GROK_HOME']?.trim();
    if (fromEnv != null && fromEnv.isNotEmpty) {
      return fromEnv;
    }
    final injected = grokHome?.trim();
    if (injected != null && injected.isNotEmpty) {
      return injected;
    }
    final home =
        homeResolver?.call() ??
        env[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (home == null || home.isEmpty) {
      return '.grok';
    }
    return '$home${Platform.pathSeparator}.grok';
  }

  /// 按项目路径列出本地 session 摘要。
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
    required String providerId,
    Map<String, String>? environment,
  }) async {
    final projectPath = query.projectPath?.trim() ?? '';
    if (projectPath.isEmpty) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }

    final sessionsRoot = Directory(
      '${resolveGrokHome(environment: environment)}'
      '${Platform.pathSeparator}sessions',
    );
    if (!await sessionsRoot.exists()) {
      return const AgentThreadPage(
        threads: <AgentThreadSummary>[],
        nextCursor: null,
      );
    }

    final summaries = <AgentThreadSummary>[];
    final seenSessionIds = <String>{};

    // 先按已知编码候选直接命中项目目录（Unix 用 %2F…，旧逻辑曾误用 %5C…）。
    for (final projectKey in _projectDirNameCandidates(projectPath)) {
      final projectDir = Directory(
        '${sessionsRoot.path}${Platform.pathSeparator}$projectKey',
      );
      if (!await projectDir.exists()) {
        continue;
      }
      await for (final entity in projectDir.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final summary = await _readSessionSummary(
          sessionDir: entity,
          providerId: providerId,
          projectPath: projectPath,
        );
        if (summary != null && seenSessionIds.add(summary.id)) {
          summaries.add(summary);
        }
      }
      if (summaries.isNotEmpty) {
        break;
      }
    }

    // 兼容：扫描 sessions 根下任意项目目录名（编码差异 / 原始路径）。
    if (summaries.isEmpty) {
      await for (final entity in sessionsRoot.list(followLinks: false)) {
        if (entity is! Directory) {
          continue;
        }
        final name = _directoryBaseName(entity);
        if (!_pathLooksLikeProject(name, projectPath)) {
          continue;
        }
        await for (final child in entity.list(followLinks: false)) {
          if (child is! Directory) {
            continue;
          }
          final summary = await _readSessionSummary(
            sessionDir: child,
            providerId: providerId,
            projectPath: projectPath,
          );
          if (summary != null && seenSessionIds.add(summary.id)) {
            summaries.add(summary);
          }
        }
      }
    }

    summaries.sort((a, b) {
      final aTime = a.recencyAt ?? a.updatedAt;
      final bTime = b.recencyAt ?? b.updatedAt;
      return bTime.compareTo(aTime);
    });

    final limit = query.limit <= 0 ? 50 : query.limit;
    final offset = _parseOffset(query.cursor);
    final page = summaries.skip(offset).take(limit).toList(growable: false);
    final nextOffset = offset + page.length;
    final nextCursor = nextOffset < summaries.length ? '$nextOffset' : null;

    return AgentThreadPage(
      threads: List<AgentThreadSummary>.unmodifiable(page),
      nextCursor: nextCursor,
    );
  }

  /// 读取 thread 历史并映射为 UI 时间线可用的 turn 快照。
  ///
  /// 查找顺序：
  /// 1. [sessionPath] 指向的 session 目录
  /// 2. 按 [projectPath] + [threadId] 定位
  /// 3. 递归扫描 sessions 根目录
  ///
  /// 内容优先级：`updates.jsonl` > `chat_history.jsonl`。
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    required String providerId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final sessionDir = await _resolveSessionDirectory(
      threadId: threadId,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: environment,
    );
    if (sessionDir == null) {
      return AgentThreadHistorySnapshot(
        threadId: threadId,
        turns: const <AgentHistoryTurn>[],
      );
    }

    final meta = <String, Object?>{
      'sessionPath': sessionDir.path,
      'providerId': providerId,
    };

    final updatesFile = File(
      '${sessionDir.path}${Platform.pathSeparator}updates.jsonl',
    );
    if (await updatesFile.exists()) {
      try {
        final content = await updatesFile.readAsString();
        final snapshot = updatesParser.parse(
          threadId: threadId,
          content: content,
          raw: <String, Object?>{...meta, 'source': 'updates.jsonl'},
        );
        if (snapshot.turns.isNotEmpty) {
          return snapshot;
        }
        _log.t(
          'updates.jsonl for $threadId produced empty turns; trying chat_history',
        );
      } catch (error, stackTrace) {
        _log.w(
          'Could not parse updates.jsonl for $threadId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final historyFile = File(
      '${sessionDir.path}${Platform.pathSeparator}chat_history.jsonl',
    );
    if (await historyFile.exists()) {
      try {
        final content = await historyFile.readAsString();
        return chatHistoryParser.parse(
          threadId: threadId,
          content: content,
          raw: <String, Object?>{...meta, 'source': 'chat_history.jsonl'},
        );
      } catch (error, stackTrace) {
        _log.w(
          'Could not parse chat_history.jsonl for $threadId',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
      raw: meta,
    );
  }

  Future<Directory?> _resolveSessionDirectory({
    required String threadId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final direct = sessionPath?.trim();
    if (direct != null && direct.isNotEmpty) {
      final asDir = Directory(direct);
      if (await asDir.exists()) {
        return asDir;
      }
      // sessionPath 有时指向文件；回退到父目录。
      final parent = Directory(asDir.uri.resolve('.').toFilePath());
      if (await parent.exists() && _directoryBaseName(parent) == threadId) {
        return parent;
      }
      final fileParent = File(direct).parent;
      if (await fileParent.exists()) {
        return fileParent;
      }
    }
    return _findSessionDirectory(
      threadId: threadId,
      projectPath: projectPath,
      environment: environment,
    );
  }

  /// 读取本地 `summary.json` 中的标题字段。
  ///
  /// Grok 会在首轮对话后异步写入 `generated_title` / `session_summary`，
  /// ACP 协议本身不推送改名通知，因此 live UI 需要主动轮询该文件。
  ///
  /// live 自动改名应优先等待 [GrokSessionTitleSnapshot.generatedTitle]；
  /// [sessionSummary] 可能更早出现或与首条用户消息混淆，不宜单独作为终态。
  Future<GrokSessionTitleSnapshot?> readSessionTitleSnapshot({
    required String threadId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final resolved = await resolveSessionDirectory(
      threadId: threadId,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: environment,
    );
    if (resolved == null) {
      return null;
    }
    final summaryFile = File(
      '${resolved.path}${Platform.pathSeparator}summary.json',
    );
    if (!await summaryFile.exists()) {
      return GrokSessionTitleSnapshot(sessionPath: resolved.path);
    }
    try {
      final decoded = jsonDecode(await summaryFile.readAsString());
      if (decoded is! Map) {
        return GrokSessionTitleSnapshot(sessionPath: resolved.path);
      }
      final raw = decoded.map(
        (key, value) => MapEntry(key.toString(), value as Object?),
      );
      return GrokSessionTitleSnapshot(
        sessionPath: resolved.path,
        generatedTitle: _nonEmpty(raw['generated_title']?.toString()),
        sessionSummary: _nonEmpty(raw['session_summary']?.toString()),
      );
    } catch (error, stackTrace) {
      _log.t(
        'Could not read Grok title snapshot for $threadId',
        error: error,
        stackTrace: stackTrace,
      );
      return GrokSessionTitleSnapshot(sessionPath: resolved.path);
    }
  }

  /// 读取展示标题；优先 `generated_title`。
  Future<String?> readSessionDisplayTitle({
    required String threadId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final snapshot = await readSessionTitleSnapshot(
      threadId: threadId,
      projectPath: projectPath,
      sessionPath: sessionPath,
      environment: environment,
    );
    return snapshot?.displayTitle;
  }

  /// 解析 session 目录；[sessionPath] 优先，否则按项目路径候选与递归扫描。
  Future<Directory?> resolveSessionDirectory({
    required String threadId,
    String? projectPath,
    String? sessionPath,
    Map<String, String>? environment,
  }) async {
    final explicitPath = sessionPath?.trim();
    if (explicitPath != null && explicitPath.isNotEmpty) {
      final dir = Directory(explicitPath);
      if (await dir.exists()) {
        return dir;
      }
    }
    return _findSessionDirectory(
      threadId: threadId,
      projectPath: projectPath,
      environment: environment,
    );
  }

  Future<AgentThreadSummary?> _readSessionSummary({
    required Directory sessionDir,
    required String providerId,
    required String projectPath,
  }) async {
    final id = _directoryBaseName(sessionDir);
    // UUID 形态的 session 目录才纳入列表。
    if (!_looksLikeSessionId(id)) {
      return null;
    }

    final summaryFile = File(
      '${sessionDir.path}${Platform.pathSeparator}summary.json',
    );
    Map<String, Object?> raw = const <String, Object?>{};
    String? title;
    String preview = '';
    DateTime? createdAt;
    DateTime? updatedAt;
    DateTime? lastActiveAt;

    if (await summaryFile.exists()) {
      try {
        final decoded = jsonDecode(await summaryFile.readAsString());
        if (decoded is Map) {
          raw = decoded.map(
            (key, value) => MapEntry(key.toString(), value as Object?),
          );
          title =
              raw['generated_title']?.toString() ??
              raw['session_summary']?.toString();
          preview = (raw['session_summary']?.toString() ?? title ?? '').trim();
          createdAt = DateTime.tryParse(raw['created_at']?.toString() ?? '');
          updatedAt = DateTime.tryParse(raw['updated_at']?.toString() ?? '');
          lastActiveAt = DateTime.tryParse(
            raw['last_active_at']?.toString() ?? '',
          );
          final info = raw['info'];
          if (info is Map) {
            final cwd = info['cwd']?.toString();
            if (cwd != null &&
                cwd.isNotEmpty &&
                !_sameProjectPath(cwd, projectPath)) {
              return null;
            }
          }
        }
      } catch (error, stackTrace) {
        _log.t(
          'Could not parse Grok summary.json for $id',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    final stat = await sessionDir.stat();
    final fallbackTime = stat.modified;
    return AgentThreadSummary(
      id: id,
      providerId: providerId,
      projectPath: projectPath,
      title: title?.trim().isEmpty == true ? null : title?.trim(),
      sessionPath: sessionDir.path,
      preview: preview.isEmpty ? id : preview,
      createdAt: createdAt ?? fallbackTime,
      updatedAt: updatedAt ?? lastActiveAt ?? fallbackTime,
      recencyAt: lastActiveAt ?? updatedAt ?? fallbackTime,
      status: AgentThreadRuntimeStatus.idle,
      raw: raw,
    );
  }

  Future<Directory?> _findSessionDirectory({
    required String threadId,
    String? projectPath,
    Map<String, String>? environment,
  }) async {
    final sessionsRoot = Directory(
      '${resolveGrokHome(environment: environment)}'
      '${Platform.pathSeparator}sessions',
    );
    if (!await sessionsRoot.exists()) {
      return null;
    }

    if (projectPath != null && projectPath.trim().isNotEmpty) {
      for (final projectKey in _projectDirNameCandidates(projectPath)) {
        final candidate = Directory(
          '${sessionsRoot.path}${Platform.pathSeparator}$projectKey'
          '${Platform.pathSeparator}$threadId',
        );
        if (await candidate.exists()) {
          return candidate;
        }
      }
    }

    await for (final entity in sessionsRoot.list(
      recursive: true,
      followLinks: false,
    )) {
      if (entity is! Directory) {
        continue;
      }
      final name = _directoryBaseName(entity);
      if (name == threadId) {
        return entity;
      }
    }
    return null;
  }
}

/// 本地 summary 标题快照。
class GrokSessionTitleSnapshot {
  const GrokSessionTitleSnapshot({
    this.sessionPath,
    this.generatedTitle,
    this.sessionSummary,
  });

  /// session 目录绝对路径（便于后续 watch / 直读）。
  final String? sessionPath;

  /// Grok 异步生成的正式标题。
  final String? generatedTitle;

  /// 会话摘要；可能与 generated_title 相同，也可能更早/更粗糙。
  final String? sessionSummary;

  /// live 自动改名应使用的终态标题。
  String? get authoritativeTitle => generatedTitle;

  /// 列表/展示回退链。
  String? get displayTitle => generatedTitle ?? sessionSummary;
}

String? _nonEmpty(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  return cleaned;
}

/// Grok session 项目目录名候选。
///
/// 实测 macOS 上 Grok 使用 `Uri.encodeComponent('/Users/...')` → `%2FUsers%2F...`；
/// 旧代码误把 `/` 换成 `\` 再编码得到 `%5CUsers%5C...`，会导致直接路径命中失败。
List<String> _projectDirNameCandidates(String projectPath) {
  final trimmed = projectPath.trim();
  if (trimmed.isEmpty) {
    return const <String>[];
  }
  final withSlash = trimmed.replaceAll('\\', '/');
  final withBackslash = trimmed.replaceAll('/', '\\');
  return <String>{
    Uri.encodeComponent(withSlash),
    Uri.encodeComponent(withBackslash),
    Uri.encodeComponent(trimmed),
  }.toList(growable: false);
}

/// 取目录 basename；避免 Windows 上 `uri.pathSegments.last` 为空字符串。
String _directoryBaseName(Directory directory) {
  final path = directory.path;
  final parts = path.split(RegExp(r'[\\/]+')).where((part) => part.isNotEmpty);
  if (parts.isEmpty) {
    return path;
  }
  return parts.last;
}

bool _pathLooksLikeProject(String encodedOrRaw, String projectPath) {
  try {
    final decoded = Uri.decodeComponent(encodedOrRaw);
    return _sameProjectPath(decoded, projectPath) ||
        _sameProjectPath(encodedOrRaw, projectPath);
  } catch (_) {
    return _sameProjectPath(encodedOrRaw, projectPath);
  }
}

bool _sameProjectPath(String a, String b) {
  final na = a.replaceAll('/', '\\').toLowerCase().trim();
  final nb = b.replaceAll('/', '\\').toLowerCase().trim();
  if (na == nb) {
    return true;
  }
  final stripA = na.endsWith('\\') ? na.substring(0, na.length - 1) : na;
  final stripB = nb.endsWith('\\') ? nb.substring(0, nb.length - 1) : nb;
  return stripA == stripB;
}

bool _looksLikeSessionId(String value) {
  return RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  ).hasMatch(value);
}

int _parseOffset(String? cursor) {
  if (cursor == null || cursor.isEmpty) {
    return 0;
  }
  return int.tryParse(cursor) ?? 0;
}

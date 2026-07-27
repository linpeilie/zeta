import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_updates_history_parser.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 单个 Grok `updates.jsonl` 对应的可统计会话快照。
class GrokUsageSessionSnapshot {
  const GrokUsageSessionSnapshot({
    required this.sourcePath,
    required this.threadId,
    required this.projectPath,
    required this.modifiedAt,
    required this.history,
  });

  final String sourcePath;
  final String threadId;
  final String projectPath;
  final DateTime modifiedAt;
  final AgentThreadHistorySnapshot history;
}

/// Grok 本地用量扫描结果。
class GrokUsageScanResult {
  GrokUsageScanResult({
    required List<GrokUsageSessionSnapshot> sessions,
    required List<String> warnings,
  }) : sessions = List<GrokUsageSessionSnapshot>.unmodifiable(sessions),
       warnings = List<String>.unmodifiable(warnings);

  final List<GrokUsageSessionSnapshot> sessions;
  final List<String> warnings;
}

/// 可注入的 Grok 本地 usage 扫描接口。
abstract interface class GrokUsageLogScanner {
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    bool forceRefresh = false,
  });
}

/// 扫描 `$GROK_HOME/sessions/**/updates.jsonl` 中的跨项目用量。
class FileSystemGrokUsageLogScanner implements GrokUsageLogScanner {
  const FileSystemGrokUsageLogScanner({
    this.parser = const GrokUpdatesHistoryParser(),
  });

  final GrokUpdatesHistoryParser parser;

  @override
  Future<GrokUsageScanResult> scan({
    required String grokHome,
    bool forceRefresh = false,
  }) {
    if (forceRefresh) {
      // Grok parser 会同步归并完整历史，强制刷新时放到后台 isolate 执行。
      return Isolate.run(
        () => _scan(grokHome: grokHome),
        debugName: 'zeta-grok-usage-scan',
      );
    }
    return _scan(grokHome: grokHome);
  }

  Future<GrokUsageScanResult> _scan({required String grokHome}) async {
    // 当前 Grok 扫描器没有缓存，每次都读取最新文件。
    final sessionsDirectory = Directory(_joinPath(grokHome, 'sessions'));
    if (!await sessionsDirectory.exists()) {
      return GrokUsageScanResult(
        sessions: const <GrokUsageSessionSnapshot>[],
        warnings: const <String>[],
      );
    }

    final files = <File>[];
    var discoveryFailures = 0;
    try {
      await for (final entity in sessionsDirectory.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File &&
            _basename(entity.path).toLowerCase() == 'updates.jsonl') {
          files.add(entity);
        }
      }
    } on FileSystemException {
      discoveryFailures += 1;
    }
    files.sort((left, right) => left.path.compareTo(right.path));

    final sessions = <GrokUsageSessionSnapshot>[];
    var unreadableFiles = 0;
    for (final file in files) {
      try {
        final stat = await file.stat();
        final sessionDirectory = file.parent;
        final threadId = _basename(sessionDirectory.path);
        final projectPath = await _readProjectPath(sessionDirectory);
        final history = parser.parse(
          threadId: threadId,
          content: await file.readAsString(),
          raw: <String, Object?>{
            'source': 'updates.jsonl',
            'sourcePath': file.path,
            'projectPath': projectPath,
          },
        );
        sessions.add(
          GrokUsageSessionSnapshot(
            sourcePath: file.path,
            threadId: threadId,
            projectPath: projectPath,
            modifiedAt: stat.modified,
            history: history,
          ),
        );
      } on FileSystemException {
        unreadableFiles += 1;
      } on FormatException {
        unreadableFiles += 1;
      } catch (_) {
        // 单个会话包含未知结构时继续统计其他会话。
        unreadableFiles += 1;
      }
    }

    return GrokUsageScanResult(
      sessions: sessions,
      warnings: <String>[
        if (discoveryFailures > 0) 'Grok 会话目录未能完整枚举，已展示可读取的数据。',
        if (unreadableFiles > 0) '$unreadableFiles 个 Grok 会话文件读取失败，已展示其余数据。',
      ],
    );
  }

  Future<String> _readProjectPath(Directory sessionDirectory) async {
    final summary = File(_joinPath(sessionDirectory.path, 'summary.json'));
    if (await summary.exists()) {
      try {
        final decoded = jsonDecode(await summary.readAsString());
        if (decoded is Map) {
          final info = decoded['info'];
          if (info is Map) {
            final cwd = info['cwd']?.toString().trim();
            if (cwd != null && cwd.isNotEmpty) {
              return cwd;
            }
          }
        }
      } on FileSystemException {
        // summary 仅用于补全项目路径，失败时仍可从目录名恢复。
      } on FormatException {
        // 损坏的 summary 不影响 updates.jsonl 用量读取。
      }
    }

    final encoded = _basename(sessionDirectory.parent.path);
    try {
      final decoded = Uri.decodeComponent(encoded).trim();
      return decoded.isEmpty ? 'unknown' : decoded;
    } on FormatException {
      return encoded.isEmpty ? 'unknown' : encoded;
    }
  }
}

String _joinPath(String left, String right) {
  if (left.endsWith('/') || left.endsWith(r'\')) {
    return '$left$right';
  }
  return '$left${Platform.pathSeparator}$right';
}

String _basename(String path) {
  final parts = path
      .split(RegExp(r'[\\/]+'))
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? path : parts.last;
}

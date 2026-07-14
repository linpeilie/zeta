import 'dart:collection';

import 'package:zeta/src/core/security/sensitive_data_redactor.dart';

/// Cursor 内存诊断记录级别。
enum CursorDiagnosticLevel { debug, info, warning, error }

/// 一条已经脱敏且有界的 Cursor 运行诊断。
class CursorDiagnosticRecord {
  const CursorDiagnosticRecord({
    required this.id,
    required this.source,
    required this.message,
    required this.level,
    required this.timestamp,
  });

  final String id;
  final String source;
  final String message;
  final CursorDiagnosticLevel level;
  final DateTime timestamp;
}

/// 最近一次成功 ACP 握手的安全摘要。
class CursorHandshakeDiagnostics {
  const CursorHandshakeDiagnostics({
    required this.protocolVersion,
    required this.capabilities,
    required this.capabilityFingerprint,
    required this.recordedAt,
    this.cliVersion,
    this.agentName,
    this.agentVersion,
  });

  final String protocolVersion;
  final String? cliVersion;
  final String? agentName;
  final String? agentVersion;
  final List<String> capabilities;
  final String capabilityFingerprint;
  final DateTime recordedAt;
}

/// Cursor 运行诊断的只读快照。
class CursorDiagnosticsSnapshot {
  const CursorDiagnosticsSnapshot({
    required this.records,
    this.handshake,
    this.exitReason,
  });

  final List<CursorDiagnosticRecord> records;
  final CursorHandshakeDiagnostics? handshake;
  final String? exitReason;
}

/// 仅保存在当前 Zeta 进程内的 Cursor stderr 与协议诊断 ring buffer。
///
/// 不接收 prompt 正文或完整 wire payload；所有文本进入缓冲区前都会脱敏、折叠换行并截断。
class CursorDiagnosticsStore {
  CursorDiagnosticsStore({
    this.maxRecords = 200,
    this.maxLineLength = 1000,
    DateTime Function()? clock,
  }) : assert(maxRecords > 0),
       assert(maxLineLength > 0),
       _clock = clock ?? DateTime.now;

  /// 生产环境 provider 与 Agent 管理页共享的进程内实例。
  static final CursorDiagnosticsStore shared = CursorDiagnosticsStore();

  static const String runtimeSource = 'Cursor ACP（内存诊断）';

  final int maxRecords;
  final int maxLineLength;
  final DateTime Function() _clock;
  final ListQueue<CursorDiagnosticRecord> _records =
      ListQueue<CursorDiagnosticRecord>();
  CursorHandshakeDiagnostics? _handshake;
  String? _exitReason;
  int _sequence = 0;

  CursorDiagnosticsSnapshot get snapshot => CursorDiagnosticsSnapshot(
    records: List<CursorDiagnosticRecord>.unmodifiable(_records),
    handshake: _handshake,
    exitReason: _exitReason,
  );

  void recordStderr(String line) {
    if (line.trim().isEmpty) {
      return;
    }
    record(source: 'Cursor stderr（内存）', message: line, level: _levelFor(line));
  }

  void record({
    required String source,
    required String message,
    CursorDiagnosticLevel level = CursorDiagnosticLevel.info,
  }) {
    final safeMessage = _safeLine(message);
    if (safeMessage.isEmpty) {
      return;
    }
    final timestamp = _clock();
    _records.addLast(
      CursorDiagnosticRecord(
        id: 'cursor-diagnostic-${timestamp.microsecondsSinceEpoch}-${_sequence++}',
        source: source,
        message: safeMessage,
        level: level,
        timestamp: timestamp,
      ),
    );
    while (_records.length > maxRecords) {
      _records.removeFirst();
    }
  }

  /// 保存 initialize 的白名单字段与 capability 键名，不保存原始响应。
  void recordHandshake({
    required Object? protocolVersion,
    required Object? agentInfo,
    required Object? capabilities,
    String? cliVersion,
  }) {
    final info = _asMap(agentInfo);
    final capabilityNames = _capabilityNames(capabilities);
    final fingerprint = _fingerprint(capabilityNames);
    _handshake = CursorHandshakeDiagnostics(
      protocolVersion: _safeScalar(protocolVersion) ?? 'unknown',
      cliVersion: _safeScalar(cliVersion),
      agentName: _safeScalar(info?['title'] ?? info?['name']),
      agentVersion: _safeScalar(info?['version']),
      capabilities: List<String>.unmodifiable(capabilityNames),
      capabilityFingerprint: fingerprint,
      recordedAt: _clock(),
    );
    _exitReason = null;
    record(
      source: runtimeSource,
      message:
          'handshake ready; cli=${_handshake!.cliVersion ?? 'unknown'}; '
          'protocol=${_handshake!.protocolVersion}; '
          'agent=${_handshake!.agentName ?? 'Cursor Agent'}; '
          'agentVersion=${_handshake!.agentVersion ?? 'unknown'}; '
          'capabilities=${capabilityNames.isEmpty ? 'none declared' : capabilityNames.join(',')}',
    );
  }

  void recordExit(String reason, {bool expected = false}) {
    _exitReason = _safeLine(reason);
    record(
      source: runtimeSource,
      message: 'process exit; reason=$_exitReason',
      level: expected
          ? CursorDiagnosticLevel.info
          : CursorDiagnosticLevel.error,
    );
  }

  void clear() {
    _records.clear();
    _handshake = null;
    _exitReason = null;
    _sequence = 0;
  }

  String _safeLine(String value) {
    final singleLine = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    final redacted = redactSensitiveText(singleLine);
    return redacted.length <= maxLineLength
        ? redacted
        : '${redacted.substring(0, maxLineLength)}…';
  }
}

CursorDiagnosticLevel _levelFor(String value) {
  final normalized = value.toLowerCase();
  if (normalized.contains('error') || normalized.contains('fatal')) {
    return CursorDiagnosticLevel.error;
  }
  if (normalized.contains('warn')) {
    return CursorDiagnosticLevel.warning;
  }
  if (normalized.contains('debug') || normalized.contains('trace')) {
    return CursorDiagnosticLevel.debug;
  }
  return CursorDiagnosticLevel.info;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return <String, Object?>{
    for (final entry in value.entries) entry.key.toString(): entry.value,
  };
}

String? _safeScalar(Object? value) {
  if (value == null || (value is! String && value is! num && value is! bool)) {
    return null;
  }
  final redacted = redactSensitiveText(value.toString().trim());
  if (redacted.isEmpty) {
    return null;
  }
  return redacted.length <= 120 ? redacted : '${redacted.substring(0, 120)}…';
}

List<String> _capabilityNames(Object? value) {
  final output = <String>{};

  void visit(Object? node, String path, int depth) {
    if (depth > 4 || output.length >= 64) {
      return;
    }
    final map = _asMap(node);
    if (map == null) {
      if (path.isNotEmpty && node == true) {
        output.add(path);
      }
      return;
    }
    for (final entry in map.entries) {
      final key = entry.key.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '');
      if (key.isEmpty) {
        continue;
      }
      final next = path.isEmpty ? key : '$path.$key';
      final child = _asMap(entry.value);
      if (child == null) {
        if (entry.value == true || entry.value is List) {
          output.add(next);
        }
      } else if (child.isEmpty) {
        output.add(next);
      } else {
        visit(child, next, depth + 1);
      }
    }
  }

  visit(value, '', 0);
  final sorted = output.toList()..sort();
  return sorted;
}

String _fingerprint(List<String> capabilities) {
  var hash = 0x811c9dc5;
  for (final unit in capabilities.join('|').codeUnits) {
    hash ^= unit;
    hash = (hash * 0x01000193) & 0x7fffffff;
  }
  return hash.toRadixString(16).padLeft(8, '0');
}

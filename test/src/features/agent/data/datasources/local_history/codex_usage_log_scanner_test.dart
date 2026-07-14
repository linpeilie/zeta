import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  late Directory tempDirectory;

  setUp(() async {
    tempDirectory = await Directory.systemTemp.createTemp('zeta-codex-usage-');
  });

  tearDown(() async {
    await tempDirectory.delete(recursive: true);
  });

  test(
    'discovers rollout files and aggregates exact last usage samples',
    () async {
      final file = await _writeRollout(tempDirectory, <Map<String, Object?>>[
        _meta(),
        _event('task_started', timestamp: '2026-07-08T09:00:01Z'),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:02Z',
          total: _usage(
            input: 70,
            cached: 20,
            output: 20,
            reasoning: 10,
            total: 100,
          ),
          last: _usage(
            input: 70,
            cached: 20,
            output: 20,
            reasoning: 10,
            total: 100,
          ),
        ),
        // 相同累计总量是 Codex 的重复通知，不能重复计算。
        _tokenEvent(
          timestamp: '2026-07-08T09:00:03Z',
          total: _usage(
            input: 70,
            cached: 20,
            output: 20,
            reasoning: 10,
            total: 100,
          ),
          last: _usage(input: 1, cached: 0, output: 1, reasoning: 0, total: 2),
        ),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:04Z',
          total: _usage(
            input: 120,
            cached: 30,
            output: 35,
            reasoning: 15,
            total: 180,
          ),
          last: _usage(
            input: 50,
            cached: 10,
            output: 15,
            reasoning: 5,
            total: 80,
          ),
        ),
        _event('task_complete', timestamp: '2026-07-08T09:00:05Z'),
      ]);

      final result = await const FileSystemCodexUsageLogScanner().scan(
        codexHome: tempDirectory.path,
        cachedSessions: const <String, CodexUsageSessionSnapshot>{},
      );

      expect(result.warnings, isEmpty);
      expect(result.sessions.keys, contains(file.path));
      final session = result.sessions[file.path]!;
      expect(session.threadId, 'thread-1');
      expect(session.projectPath, r'C:\work\zeta');
      expect(session.turns, hasLength(1));
      expect(session.turns.single.status, AgentHistoryTurnStatus.completed);
      expect(session.turns.single.samples, hasLength(2));
      expect(session.turns.single.samples.first.inputTokens, 50);
      expect(session.turns.single.samples.first.cachedInputTokens, 20);
      expect(session.turns.single.samples.first.outputTokens, 10);
      expect(session.turns.single.samples.first.reasoningTokens, 10);
      expect(session.turns.single.samples.last.inputTokens, 40);
    },
  );

  test(
    'falls back to cumulative deltas and advances mixed baselines',
    () async {
      final file = await _writeRollout(tempDirectory, <Map<String, Object?>>[
        _meta(),
        _event('task_started', timestamp: '2026-07-08T09:00:01Z'),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:02Z',
          total: _usage(
            input: 40,
            cached: 10,
            output: 8,
            reasoning: 2,
            total: 50,
          ),
          last: _usage(
            input: 40,
            cached: 10,
            output: 8,
            reasoning: 2,
            total: 50,
          ),
        ),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:03Z',
          total: _usage(
            input: 70,
            cached: 15,
            output: 15,
            reasoning: 5,
            total: 90,
          ),
        ),
      ]);

      final result = await const FileSystemCodexUsageLogScanner().scan(
        codexHome: tempDirectory.path,
        cachedSessions: const <String, CodexUsageSessionSnapshot>{},
      );
      final samples = result.sessions[file.path]!.turns.single.samples;

      expect(samples, hasLength(2));
      expect(samples.last.inputTokens, 25);
      expect(samples.last.cachedInputTokens, 5);
      expect(samples.last.outputTokens, 4);
      expect(samples.last.reasoningTokens, 3);
      expect(samples.last.totalTokens, 40);
    },
  );

  test('skips fork replay window but retains later divergent work', () async {
    final file = await _writeRollout(tempDirectory, <Map<String, Object?>>[
      _meta(forkedFromId: 'parent-1'),
      _event('task_started', timestamp: '2026-07-08T09:00:01Z'),
      _tokenEvent(
        timestamp: '2026-07-08T09:00:02Z',
        total: _usage(
          input: 40,
          cached: 0,
          output: 10,
          reasoning: 0,
          total: 50,
        ),
        last: _usage(input: 40, cached: 0, output: 10, reasoning: 0, total: 50),
      ),
      _tokenEvent(
        timestamp: '2026-07-08T09:00:10Z',
        total: _usage(
          input: 70,
          cached: 0,
          output: 20,
          reasoning: 0,
          total: 90,
        ),
        last: _usage(input: 30, cached: 0, output: 10, reasoning: 0, total: 40),
      ),
    ]);

    final result = await const FileSystemCodexUsageLogScanner().scan(
      codexHome: tempDirectory.path,
      cachedSessions: const <String, CodexUsageSessionSnapshot>{},
    );
    final samples = result.sessions[file.path]!.turns.single.samples;

    expect(samples, hasLength(1));
    expect(samples.single.totalTokens, 40);
    expect(samples.single.deduplicationKey, startsWith('codex:parent-1:'));
  });

  test(
    'keeps equal totals with different breakdowns and clamps resets',
    () async {
      final file = await _writeRollout(tempDirectory, <Map<String, Object?>>[
        _meta(),
        _event('task_started', timestamp: '2026-07-08T09:00:01Z'),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:02Z',
          total: _usage(
            input: 80,
            cached: 10,
            output: 15,
            reasoning: 5,
            total: 100,
          ),
          last: _usage(
            input: 80,
            cached: 10,
            output: 15,
            reasoning: 5,
            total: 100,
          ),
        ),
        _tokenEvent(
          timestamp: '2026-07-08T09:00:03Z',
          total: _usage(
            input: 85,
            cached: 10,
            output: 10,
            reasoning: 5,
            total: 100,
          ),
          last: _usage(input: 5, cached: 0, output: 0, reasoning: 0, total: 5),
        ),
        // 累计计数器重置时所有 fallback 差分归零，不制造负 token。
        _tokenEvent(
          timestamp: '2026-07-08T09:00:04Z',
          total: _usage(input: 1, cached: 0, output: 0, reasoning: 0, total: 1),
        ),
      ]);

      final result = await const FileSystemCodexUsageLogScanner().scan(
        codexHome: tempDirectory.path,
        cachedSessions: const <String, CodexUsageSessionSnapshot>{},
      );
      final samples = result.sessions[file.path]!.turns.single.samples;

      expect(samples, hasLength(2));
      expect(samples.last.inputTokens, 5);
      expect(samples.last.totalTokens, 5);
    },
  );

  test('accepts long metadata and never estimates missing usage', () async {
    final meta = _meta();
    (meta['payload']! as Map<String, Object?>)['base_instructions'] =
        List<String>.filled(200000, 'x').join();
    final file = await _writeRollout(tempDirectory, <Map<String, Object?>>[
      meta,
      _event('task_started', timestamp: '2026-07-08T09:00:01Z'),
      <String, Object?>{
        'timestamp': '2026-07-08T09:00:02Z',
        'type': 'event_msg',
        'payload': <String, Object?>{
          'type': 'token_count',
          'turn_id': 'turn-1',
        },
      },
      _event('task_complete', timestamp: '2026-07-08T09:00:03Z'),
    ]);

    final result = await const FileSystemCodexUsageLogScanner().scan(
      codexHome: tempDirectory.path,
      cachedSessions: const <String, CodexUsageSessionSnapshot>{},
    );

    expect(result.sessions[file.path], isNotNull);
    expect(result.sessions[file.path]!.turns.single.samples, isEmpty);
  });

  test('discovers rollout files across year and month directories', () async {
    final first = await _writeRollout(
      tempDirectory,
      <Map<String, Object?>>[_meta()],
      name: 'rollout-first.jsonl',
      year: '2025',
      month: '12',
      day: '31',
    );
    final second = await _writeRollout(
      tempDirectory,
      <Map<String, Object?>>[_meta(sessionId: 'thread-2')],
      name: 'rollout-second.jsonl',
      year: '2026',
      month: '01',
      day: '01',
    );

    final result = await const FileSystemCodexUsageLogScanner().scan(
      codexHome: tempDirectory.path,
      cachedSessions: const <String, CodexUsageSessionSnapshot>{},
    );

    expect(
      result.sessions.keys,
      containsAll(<String>[first.path, second.path]),
    );
  });

  test('rejects non-Codex and damaged first lines and reuses fingerprints', () async {
    await _writeRollout(tempDirectory, <Map<String, Object?>>[
      _meta(originator: 'other'),
    ], name: 'rollout-other.jsonl');
    final damaged = File(
      '${tempDirectory.path}${Platform.pathSeparator}sessions${Platform.pathSeparator}'
      '2026${Platform.pathSeparator}07${Platform.pathSeparator}08${Platform.pathSeparator}'
      'rollout-damaged.jsonl',
    );
    await damaged.parent.create(recursive: true);
    await damaged.writeAsString('{broken\n');
    final valid = await _writeRollout(tempDirectory, <Map<String, Object?>>[
      _meta(),
    ], name: 'rollout-valid.jsonl');
    const scanner = FileSystemCodexUsageLogScanner();

    final first = await scanner.scan(
      codexHome: tempDirectory.path,
      cachedSessions: const <String, CodexUsageSessionSnapshot>{},
    );
    final second = await scanner.scan(
      codexHome: tempDirectory.path,
      cachedSessions: first.sessions,
    );
    final persisted = CodexUsageSessionSnapshot.tryDecode(
      first.sessions[valid.path]!.toJson(),
    )!;
    final restored = await scanner.scan(
      codexHome: tempDirectory.path,
      cachedSessions: <String, CodexUsageSessionSnapshot>{
        persisted.sourceId: persisted,
      },
    );

    expect(first.sessions, hasLength(1));
    expect(
      identical(first.sessions[valid.path], second.sessions[valid.path]),
      isTrue,
    );
    expect(restored.sessions[valid.path]?.sourcePath, valid.path);
    expect(restored.sessions[valid.path]?.fingerprint, persisted.fingerprint);

    await valid.writeAsString(
      '${jsonEncode(_tokenEvent(timestamp: '2026-07-08T09:00:10Z', total: _usage(input: 10, cached: 0, output: 2, reasoning: 0, total: 12), last: _usage(input: 10, cached: 0, output: 2, reasoning: 0, total: 12)))}\n',
      mode: FileMode.append,
    );
    final modified = await scanner.scan(
      codexHome: tempDirectory.path,
      cachedSessions: second.sessions,
    );
    expect(
      identical(second.sessions[valid.path], modified.sessions[valid.path]),
      isFalse,
    );
    expect(modified.sessions[valid.path]!.turns.single.samples, hasLength(1));

    await valid.delete();
    final removed = await scanner.scan(
      codexHome: tempDirectory.path,
      cachedSessions: modified.sessions,
    );
    expect(removed.sessions, isEmpty);
  });
}

Future<File> _writeRollout(
  Directory codexHome,
  List<Map<String, Object?>> records, {
  String name = 'rollout-test.jsonl',
  String year = '2026',
  String month = '07',
  String day = '08',
}) async {
  final directory = Directory(
    '${codexHome.path}${Platform.pathSeparator}sessions${Platform.pathSeparator}'
    '$year${Platform.pathSeparator}$month${Platform.pathSeparator}$day',
  );
  await directory.create(recursive: true);
  final file = File('${directory.path}${Platform.pathSeparator}$name');
  await file.writeAsString('${records.map(jsonEncode).join('\n')}\n');
  return file;
}

Map<String, Object?> _meta({
  String originator = 'codex_cli_rs',
  String sessionId = 'thread-1',
  String? forkedFromId,
}) => <String, Object?>{
  'timestamp': '2026-07-08T09:00:00Z',
  'type': 'session_meta',
  'payload': <String, Object?>{
    'originator': originator,
    'session_id': sessionId,
    'forked_from_id': forkedFromId,
    'cwd': r'C:\work\zeta',
    'model': 'gpt-5',
  },
};

Map<String, Object?> _event(String type, {required String timestamp}) =>
    <String, Object?>{
      'timestamp': timestamp,
      'type': 'event_msg',
      'payload': <String, Object?>{'type': type, 'turn_id': 'turn-1'},
    };

Map<String, Object?> _tokenEvent({
  required String timestamp,
  required Map<String, Object?> total,
  Map<String, Object?>? last,
}) => <String, Object?>{
  'timestamp': timestamp,
  'type': 'event_msg',
  'payload': <String, Object?>{
    'type': 'token_count',
    'turn_id': 'turn-1',
    'info': <String, Object?>{
      'total_token_usage': total,
      'last_token_usage': ?last,
    },
  },
};

Map<String, Object?> _usage({
  required int input,
  required int cached,
  required int output,
  required int reasoning,
  required int total,
}) => <String, Object?>{
  'input_tokens': input,
  'cached_input_tokens': cached,
  'output_tokens': output,
  'reasoning_output_tokens': reasoning,
  'total_tokens': total,
};

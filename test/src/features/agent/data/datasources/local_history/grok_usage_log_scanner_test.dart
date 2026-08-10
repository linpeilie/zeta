import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/data/datasources/local_history/grok_usage_log_scanner.dart';

void main() {
  test('跨项目扫描 updates，并只保留 turn_completed 的单回合用量', () async {
    final grokHome = await Directory.systemTemp.createTemp('zeta-grok-usage-');
    addTearDown(() async {
      if (await grokHome.exists()) {
        await grokHome.delete(recursive: true);
      }
    });

    final first = await _writeSession(
      grokHome: grokHome,
      projectDirectoryName: Uri.encodeComponent(r'D:\work\alpha'),
      threadId: '11111111-1111-1111-1111-111111111111',
      projectPath: r'D:\canonical\alpha',
      timestampMs: DateTime.utc(2026, 7, 21, 1).millisecondsSinceEpoch,
      inputTokens: 100,
      cachedTokens: 40,
      outputTokens: 20,
      reasoningTokens: 5,
      totalTokens: 120,
    );
    final second = await _writeSession(
      grokHome: grokHome,
      projectDirectoryName: Uri.encodeComponent('/work/beta'),
      threadId: '22222222-2222-2222-2222-222222222222',
      timestampMs: DateTime.utc(2026, 7, 21, 2).millisecondsSinceEpoch,
      inputTokens: 50,
      cachedTokens: 0,
      outputTokens: 10,
      reasoningTokens: 0,
      totalTokens: 60,
    );
    final ignoredDirectory = Directory(
      '${grokHome.path}${Platform.pathSeparator}sessions'
      '${Platform.pathSeparator}ignored'
      '${Platform.pathSeparator}33333333-3333-3333-3333-333333333333',
    );
    await ignoredDirectory.create(recursive: true);
    await File(
      '${ignoredDirectory.path}${Platform.pathSeparator}chat_history.jsonl',
    ).writeAsString('{}');

    final result = await const FileSystemGrokUsageLogScanner().scan(
      grokHome: grokHome.path,
      cachedSessions: const <String, GrokUsageIndexedSession>{},
      forceRefresh: true,
    );

    expect(result.warnings, isEmpty);
    expect(result.sessions, hasLength(2));
    final firstSession = result.sessions[first.path]!;
    final secondSession = result.sessions[second.path]!;
    expect(firstSession.projectPath, r'D:\canonical\alpha');
    expect(secondSession.projectPath, '/work/beta');
    expect(firstSession.turns.single.totalTokens, 120);
    // 输入口径为扣掉 cached 后的独占部分。
    expect(firstSession.turns.single.inputTokens, 60);
    expect(firstSession.turns.single.cachedInputTokens, 40);
    expect(secondSession.turns.single.totalTokens, 60);

    // fingerprint 命中时跳过正文重解析。
    final cached = await const FileSystemGrokUsageLogScanner().scan(
      grokHome: grokHome.path,
      cachedSessions: <String, GrokUsageIndexedSession>{
        for (final session in result.sessions.values) session.sourceId: session,
      },
    );
    expect(cached.sessions, hasLength(2));
    expect(cached.sessions[first.path]!.fingerprint, firstSession.fingerprint);
  });
}

Future<File> _writeSession({
  required Directory grokHome,
  required String projectDirectoryName,
  required String threadId,
  required int timestampMs,
  required int inputTokens,
  required int cachedTokens,
  required int outputTokens,
  required int reasoningTokens,
  required int totalTokens,
  String? projectPath,
}) async {
  final directory = Directory(
    '${grokHome.path}${Platform.pathSeparator}sessions'
    '${Platform.pathSeparator}$projectDirectoryName'
    '${Platform.pathSeparator}$threadId',
  );
  await directory.create(recursive: true);
  if (projectPath != null) {
    await File(
      '${directory.path}${Platform.pathSeparator}summary.json',
    ).writeAsString(
      jsonEncode(<String, Object?>{
        'info': <String, Object?>{'cwd': projectPath},
      }),
    );
  }

  final updates = <Map<String, Object?>>[
    <String, Object?>{
      'timestamp': timestampMs ~/ Duration.millisecondsPerSecond,
      'method': 'session/update',
      'params': <String, Object?>{
        'sessionId': threadId,
        'update': <String, Object?>{
          'sessionUpdate': 'user_message_chunk',
          'content': <String, Object?>{'type': 'text', 'text': 'hello'},
        },
        '_meta': <String, Object?>{
          'eventId': '$threadId-user',
          'agentTimestampMs': timestampMs,
        },
      },
    },
    <String, Object?>{
      'timestamp': timestampMs ~/ Duration.millisecondsPerSecond,
      'method': 'session/update',
      'params': <String, Object?>{
        'sessionId': threadId,
        'update': <String, Object?>{
          'sessionUpdate': 'usage_update',
          'used': 999999,
        },
        '_meta': <String, Object?>{
          'eventId': '$threadId-cumulative',
          'agentTimestampMs': timestampMs + 100,
        },
      },
    },
    <String, Object?>{
      'timestamp': timestampMs ~/ Duration.millisecondsPerSecond,
      'method': '_x.ai/session/update',
      'params': <String, Object?>{
        'sessionId': threadId,
        'update': <String, Object?>{
          'sessionUpdate': 'turn_completed',
          'stop_reason': 'end_turn',
          'usage': <String, Object?>{
            'inputTokens': inputTokens,
            'cachedReadTokens': cachedTokens,
            'outputTokens': outputTokens,
            'reasoningTokens': reasoningTokens,
            'totalTokens': totalTokens,
          },
        },
        '_meta': <String, Object?>{
          'eventId': '$threadId-complete',
          'agentTimestampMs': timestampMs + 200,
        },
      },
    },
  ];
  final file = File('${directory.path}${Platform.pathSeparator}updates.jsonl');
  await file.writeAsString(updates.map(jsonEncode).join('\n'));
  return file;
}

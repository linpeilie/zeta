import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_usage_partition_codec.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_log_scanner.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_usage_partition_codec.dart';

void main() {
  const queryCoreFiles = <String>[
    'lib/src/features/usage_statistics/application/agent_usage_query_service.dart',
    'lib/src/features/usage_statistics/data/usage_statistics_partition_store.dart',
  ];
  const g1SharedFiles = <String>[
    'packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart',
    'packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart',
    'packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart',
    'packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart',
    'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart',
  ];

  group('usage statistics layering', () {
    test('presentation and IdeHome do not import usage data', () {
      final presentationFiles =
          Directory('lib/src/features/usage_statistics/presentation')
              .listSync(recursive: true)
              .whereType<File>()
              .where((file) => file.path.endsWith('.dart'));
      final files = <File>[
        ...presentationFiles,
        File('lib/src/ui/features/ide/views/ide_home.dart'),
      ];

      for (final file in files) {
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('/usage_statistics/data/')),
          reason: '${file.path} must consume application/domain contracts only',
        );
      }
    });

    test('query service and partition store stay Provider-neutral', () {
      final concreteImport = RegExp(
        r"^import\s+'[^']*/usage_statistics/data/providers/",
        multiLine: true,
      );
      final hardCodedProviderId = RegExp(
        r"'(?:codex|grok|claude|claude_code)'",
        caseSensitive: false,
      );
      for (final path in queryCoreFiles) {
        final code = _stripLineComments(_read(path));
        expect(
          concreteImport.hasMatch(code),
          isFalse,
          reason: '$path must not import a concrete token source',
        );
        expect(
          code,
          isNot(contains('AgentProviderKind')),
          reason: '$path must not branch on Provider kind',
        );
        expect(
          hardCodedProviderId.hasMatch(code),
          isFalse,
          reason: '$path must not branch on a Provider id',
        );
      }
    });

    test(
      'legacy Provider partition key stays out of the v4 production path',
      () {
        final partitionStore = _stripLineComments(_read(queryCoreFiles.last));
        final legacyDecoder = _read(
          'lib/src/features/usage_statistics/data/'
          'legacy_usage_statistics_index_decoder.dart',
        );

        expect(partitionStore, isNot(contains("'codex'")));
        expect(partitionStore, isNot(contains("'grok'")));
        expect(partitionStore, isNot(contains("'claude'")));
        expect(legacyDecoder, contains("'codex'"));
        expect(legacyDecoder, contains('仅供 v4 Store 读取 v2/v3 派生索引的专用 decoder'));
        expect(
          File(
            'lib/src/features/usage_statistics/data/'
            'usage_statistics_index_store.dart',
          ).existsSync(),
          isFalse,
        );
      },
    );

    test('Provider partition codecs omit private paths and raw failures', () {
      const privatePath = '/private/session/rollout-secret.jsonl';
      const privateError = 'raw provider error with prompt contents';
      const privateCode = 'credential-bearing-provider-code';
      final codex = CodexUsagePartitionCodec().encode(
        <CodexUsageSessionSnapshot>[
          CodexUsageSessionSnapshot(
            sourcePath: privatePath,
            sourceId: 'codex-source-id',
            fingerprint: '1:2',
            threadId: 'thread-codex',
            projectPath: '/workspace/project',
            sourceKind: 'codex_app_server',
            createdAt: DateTime.utc(2026, 8, 12),
            turns: <CodexUsageTurnSnapshot>[
              const CodexUsageTurnSnapshot(
                id: 'turn-codex',
                status: AgentHistoryTurnStatus.failed,
                samples: <CodexUsageSample>[],
                errorMessage: privateError,
                errorCode: privateCode,
              ),
            ],
          ),
        ],
      ).payload;
      final grok = GrokUsagePartitionCodec().encode(<GrokUsageIndexedSession>[
        GrokUsageIndexedSession(
          sourcePath: privatePath,
          sourceId: 'grok-source-id',
          fingerprint: '3:4',
          threadId: 'thread-grok',
          projectPath: '/workspace/project',
          sourceKind: 'grok_acp',
          modifiedAt: DateTime.utc(2026, 8, 12),
          turns: const <GrokUsageIndexedTurn>[
            GrokUsageIndexedTurn(
              id: 'turn-grok',
              status: AgentHistoryTurnStatus.failed,
              errorMessage: privateError,
              errorCode: privateCode,
            ),
          ],
        ),
      ]).payload;
      final claude = ClaudeCodeUsagePartitionCodec().encode(
        <ClaudeCodeUsageIndexedSession>[
          ClaudeCodeUsageIndexedSession(
            sourcePath: privatePath,
            sourceId: 'claude-source-id',
            fingerprint: '5:6',
            threadId: 'thread-claude',
            projectPath: '/workspace/project',
            sourceKind: 'claude_code_stream_json',
            modifiedAt: DateTime.utc(2026, 8, 12),
            turns: const <ClaudeCodeUsageIndexedTurn>[
              ClaudeCodeUsageIndexedTurn(
                id: 'turn-claude',
                status: AgentHistoryTurnStatus.failed,
                errorMessage: privateError,
                errorCode: privateCode,
              ),
            ],
          ),
        ],
      ).payload;

      for (final payload in <Map<String, Object?>>[codex, grok, claude]) {
        final keys = <String>{};
        final strings = <String>[];
        _collectJson(payload, keys: keys, strings: strings);
        expect(
          keys.intersection(_forbiddenPersistedKeys),
          isEmpty,
          reason: 'partition payload contains a forbidden field',
        );
        expect(strings, isNot(contains(privatePath)));
        expect(strings, isNot(contains(privateError)));
        expect(strings, isNot(contains(privateCode)));
      }
    });

    test('usage query work does not modify G1 shared adapters', () {
      for (final path in g1SharedFiles) {
        final code = _stripLineComments(_read(path));
        expect(
          code,
          isNot(contains('usage_statistics')),
          reason: '$path must not depend on the usage statistics feature',
        );
      }
    });
  });
}

const _forbiddenPersistedKeys = <String>{
  'accessToken',
  'credentials',
  'environment',
  'errorCode',
  'errorMessage',
  'prompt',
  'raw',
  'rawPayload',
  'response',
  'sessionPath',
  'sourcePath',
  'toolOutput',
};

String _read(String path) {
  final file = File(path);
  expect(file.existsSync(), isTrue, reason: 'missing $path');
  return file.readAsStringSync();
}

String _stripLineComments(String source) {
  final result = StringBuffer();
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) {
      continue;
    }
    final commentIndex = line.indexOf('//');
    result.writeln(commentIndex < 0 ? line : line.substring(0, commentIndex));
  }
  return result.toString();
}

void _collectJson(
  Object? value, {
  required Set<String> keys,
  required List<String> strings,
}) {
  switch (value) {
    case Map():
      for (final entry in value.entries) {
        if (entry.key case final String key) {
          keys.add(key);
        }
        _collectJson(entry.value, keys: keys, strings: strings);
      }
    case List():
      for (final item in value) {
        _collectJson(item, keys: keys, strings: strings);
      }
    case String():
      strings.add(value);
  }
}

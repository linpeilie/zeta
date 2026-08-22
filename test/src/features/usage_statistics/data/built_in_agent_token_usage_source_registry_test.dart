import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_session_history_reader.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_query_service.dart';
import 'package:zeta/src/features/usage_statistics/application/query_agent_usage_panel_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/query_usage_statistics_repository.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/data/built_in_agent_token_usage_source_registry.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/claude_code/claude_code_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/codex/codex_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/providers/grok/grok_token_usage_source.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_query_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_quota_source.dart';

void main() {
  test('registry exposes every active Provider token source', () {
    final registry = BuiltInAgentTokenUsageSourceRegistry(
      MemoryUsageStatisticsPartitionStore(),
    );

    expect(
      registry.createFor(AgentProviderConfig.defaultCodex),
      isA<CodexTokenUsageSource>(),
    );
    expect(
      registry.createFor(AgentProviderConfig.defaultGrok),
      isA<GrokTokenUsageSource>(),
    );
    expect(
      registry.createFor(AgentProviderConfig.defaultClaudeCode),
      isA<ClaudeCodeTokenUsageSource>(),
    );
  });

  test(
    'registered Claude history reaches the panel and statistics page',
    () async {
      final userHome = await Directory.systemTemp.createTemp(
        'zeta-claude-registry-',
      );
      addTearDown(() async {
        if (await userHome.exists()) {
          await userHome.delete(recursive: true);
        }
      });
      final startedAt = DateTime(2026, 8, 14, 9);
      final now = DateTime(2026, 8, 14, 12);
      await _writeClaudeHistory(userHome, startedAt);
      final config = AgentProviderConfig.defaultClaudeCode.copyWith(
        environment: <String, String>{
          Platform.isWindows ? 'USERPROFILE' : 'HOME': userHome.path,
        },
      );
      final queryService = AgentUsageQueryService(
        () async => <AgentProviderConfig>[config],
        const _UnsupportedQuotaSource(),
        BuiltInAgentTokenUsageSourceRegistry(
          MemoryUsageStatisticsPartitionStore(),
        ),
        clock: () => now,
      );

      final panelResult = await QueryAgentUsagePanelRepository(
        queryService,
        clock: () => now,
      ).loadProvider(config.id);
      final statisticsController = UsageStatisticsController(
        repository: QueryUsageStatisticsRepository(
          queryService,
          clock: () => now,
        ),
        clock: () => now,
      );
      addTearDown(statisticsController.dispose);
      await statisticsController.initialize();

      expect(panelResult!.entry.providerId, defaultClaudeCodeProviderId);
      expect(panelResult.entry.todayTokens?.inputTokens, 3);
      expect(panelResult.entry.todayTokens?.outputTokens, 2);
      expect(panelResult.entry.todayTokens?.totalTokens, 5);
      expect(statisticsController.report?.agentOptions, <String>[
        defaultClaudeCodeProviderId,
      ]);
      expect(statisticsController.report?.overview.tokens.totalTokens, 5);
    },
  );
}

Future<void> _writeClaudeHistory(Directory userHome, DateTime startedAt) async {
  final claudeHome = Directory(
    '${userHome.path}${Platform.pathSeparator}.claude',
  );
  final projectDirectory = Directory(
    '${claudeHome.path}${Platform.pathSeparator}projects'
    '${Platform.pathSeparator}'
    '${ClaudeCodeSessionHistoryReader.encodeProjectPath('/workspace/project')}',
  );
  await projectDirectory.create(recursive: true);
  final completedAt = startedAt.add(const Duration(seconds: 1));
  final frames = <Map<String, Object?>>[
    <String, Object?>{
      'type': 'user',
      'sessionId': 'claude-session',
      'uuid': 'claude-user',
      'timestamp': startedAt.toIso8601String(),
      'cwd': '/workspace/project',
      'message': <String, Object?>{'role': 'user', 'content': '[REDACTED]'},
    },
    <String, Object?>{
      'type': 'assistant',
      'sessionId': 'claude-session',
      'uuid': 'claude-assistant',
      'timestamp': startedAt
          .add(const Duration(milliseconds: 100))
          .toIso8601String(),
      'message': <String, Object?>{
        'id': 'claude-message',
        'role': 'assistant',
        'model': 'claude-test-model',
        'content': <Object?>[
          <String, Object?>{'type': 'text', 'text': '[REDACTED]'},
        ],
      },
    },
    <String, Object?>{
      'type': 'result',
      'subtype': 'success',
      'sessionId': 'claude-session',
      'uuid': 'claude-result',
      'timestamp': completedAt.toIso8601String(),
      'duration_ms': 1000,
      'result': '[REDACTED]',
      'usage': <String, Object?>{'input_tokens': 3, 'output_tokens': 2},
    },
  ];
  await File(
    '${projectDirectory.path}${Platform.pathSeparator}session.jsonl',
  ).writeAsString('${frames.map(jsonEncode).join('\n')}\n');
}

final class _UnsupportedQuotaSource implements AgentUsageQuotaSource {
  const _UnsupportedQuotaSource();

  @override
  Future<AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>> loadQuota(
    AgentProviderConfig config,
  ) async =>
      const AgentUsageCapabilityResult<AgentUsageQuotaSnapshot>.unsupported();
}

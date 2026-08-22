import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_turn_context_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/settings/data/general_settings_codec.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 持久化 JSON 不得写入 Zeta 本地化 UI 文案。
///
/// 用户标题、路径、Provider id 可以原文落盘；欢迎语、相对时间、管理页
/// chrome 等进程内文案不能进入 session / settings / cache / 通知 payload。
void main() {
  test('persisted Zeta JSON does not embed localized UI chrome', () {
    const codec = GeneralSettingsCodec();
    final now = DateTime.utc(2026, 8, 17, 12);

    final documents = <String, String>{
      'general-en': jsonEncode(
        codec.encode(const GeneralSettings(appLanguage: AppLanguage.english)),
      ),
      'general-zh': jsonEncode(
        codec.encode(
          const GeneralSettings(appLanguage: AppLanguage.simplifiedChinese),
        ),
      ),
      'appearance': jsonEncode(const AppearanceSettings().toJson()),
      'session': IdeSessionState(
        projectPaths: const <String>['/workspace/demo'],
        activeProjectPath: '/workspace/demo',
        activeAgentProviderId: defaultAgentProviderId,
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          '/workspace/demo': <AgentThreadSummary>[
            AgentThreadSummary(
              id: 'thread-1',
              providerId: defaultAgentProviderId,
              projectPath: '/workspace/demo',
              title: 'Provider thread title',
              sessionPath: '/workspace/demo/thread-1.jsonl',
              preview: 'user preview',
              createdAt: now,
              updatedAt: now,
              recencyAt: now,
              status: AgentThreadRuntimeStatus.idle,
            ),
          ],
        },
        projectLastOpenedAtByPath: <String, DateTime>{'/workspace/demo': now},
        workbenchLayout: const IdeWorkbenchLayoutState(
          selectedAgentUsageProviderId: defaultAgentProviderId,
        ),
      ).encode(),
      'turn-context': jsonEncode(
        encodeAgentThreadTurnContext(
          AgentThreadTurnContext(
            providerId: defaultAgentProviderId,
            threadId: 'thread-1',
            turns: <AgentTurnContextRecord>[
              AgentTurnContextRecord(
                turnId: 'turn-1',
                modelId: 'gpt-5',
                startedAt: now,
                completedAt: now,
                status: AgentHistoryTurnStatus.completed,
              ),
            ],
          ),
        ),
      ),
      'provider-settings': jsonEncode(const AgentProviderSettings().toJson()),
      'usage-index': jsonEncode(
        UsageStatisticsIndexPartition(
          schemaVersion: 4,
          payload: const <String, Object?>{
            'sourceKey': 'codex',
            'updatedAt': '2026-08-17T12:00:00.000Z',
          },
        ).toJson(),
      ),
      'desktop-payload': jsonEncode(<String, Object?>{
        'version': 1,
        'providerId': defaultAgentProviderId,
        'threadId': 'thread-1',
        'identity': 'turn-complete:thread-1:turn-1',
      }),
    };

    for (final entry in documents.entries) {
      for (final chrome in _localizedUiChrome) {
        expect(
          entry.value,
          isNot(contains(chrome)),
          reason: '${entry.key} must not persist "$chrome"',
        );
      }
    }

    final general =
        jsonDecode(documents['general-zh']!) as Map<String, Object?>;
    expect(general['appLanguage'], 'zh-Hans');
    expect(general.keys, isNot(contains('locale')));

    final payload =
        jsonDecode(documents['desktop-payload']!) as Map<String, Object?>;
    expect(payload.keys.toSet(), {
      'version',
      'providerId',
      'threadId',
      'identity',
    });
    expect(payload.containsKey('title'), isFalse);
    expect(payload.containsKey('body'), isFalse);
  });

  test('desktop attention payload type stays identity-only', () {
    const request = DesktopNotificationRequest(
      id: 1,
      title: '欢迎使用 Zeta',
      body: '刚刚完成',
      payload: '{"version":1,"providerId":"codex","threadId":"t1"}',
    );
    expect(request.title, '欢迎使用 Zeta');
    expect(jsonDecode(request.payload), isA<Map<String, Object?>>());
    final payload = jsonDecode(request.payload) as Map<String, Object?>;
    expect(payload.keys, isNot(contains('title')));
    expect(payload.keys, isNot(contains('body')));
  });
}

const _localizedUiChrome = <String>[
  '欢迎使用 Zeta',
  'Welcome to Zeta',
  '刚刚',
  'Just now',
  '近期项目',
  'Recent projects',
  '已安装 Provider',
  'Installed providers',
  '自动检测 Agent',
  'Auto-detect Agents',
  '打开 Zeta',
  'Open Zeta',
];

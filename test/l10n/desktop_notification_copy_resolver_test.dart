import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/l10n/l10n.dart';

void main() {
  DesktopNotificationCopyResolver resolver(String languageCode) {
    return DesktopNotificationCopyResolver(
      lookupAppLocalizations(Locale(languageCode)),
    );
  }

  AgentWorkspaceAttention attention(
    AgentAttentionKind kind, {
    String projectPath = r'C:\workspace\zeta',
  }) {
    return AgentWorkspaceAttention(
      signal: AgentAttentionSignal(
        kind: kind,
        phase: AgentAttentionPhase.raised,
        sourceId: 'request-1',
      ),
      providerId: 'codex',
      threadId: 'thread-1',
      projectPath: projectPath,
    );
  }

  test('maps every attention kind in English and Chinese', () {
    final expectedTitles = <String, List<String>>{
      'en': <String>[
        'Task completed',
        'Task failed',
        'Task interrupted',
        'Permission required',
        'Question required',
        'Plan approval required',
        'Plan ready to execute',
      ],
      'zh': <String>[
        '任务已完成',
        '任务执行失败',
        '任务已中断',
        '需要确认权限',
        '需要回答问题',
        '需要确认计划',
        '计划可以执行',
      ],
    };

    for (final entry in expectedTitles.entries) {
      final copy = resolver(entry.key);
      final requests = <String>[
        for (final kind in AgentAttentionKind.values)
          copy.resolve(attention(kind)).title,
      ];
      expect(requests, entry.value);
    }
  });

  test('uses only a safe project name and a stable identity tag', () {
    final en = resolver('en');
    final windows = en.resolve(attention(AgentAttentionKind.turnCompleted));
    final posix = en.resolve(
      attention(
        AgentAttentionKind.turnCompleted,
        projectPath: '/workspace/alpha/',
      ),
    );
    final fallback = en.resolve(
      attention(AgentAttentionKind.turnCompleted, projectPath: r'\\\'),
    );

    expect(windows.body, 'zeta · Agent session');
    expect(posix.body, 'alpha · Agent session');
    expect(fallback.body, 'Current project · Agent session');
    expect(
      windows.tag,
      'turnCompleted:codex:thread-1:request-1',
    );
    expect(en.linuxActionName, 'Open Zeta');
    expect(resolver('zh').linuxActionName, '打开 Zeta');
  });
}

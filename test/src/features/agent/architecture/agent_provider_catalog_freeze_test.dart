import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 内置 Provider 目录冻结守卫。
///
/// `zeta_agent_core` 里仍有一张集中式 Provider 类型表：`AgentProviderKind`
/// 三个枚举值、三个内置 Provider 的稳定 ID 与默认 CLI 配置、按 ID 归一化显示名。
/// 它与目标架构 §9.3「新增 Provider 只动 providers 包 + 一行注册」冲突——加一种
/// 协议要改内核枚举，并牵动 factory / usage statistics / settings / presentation
/// 的 exhaustive switch。
///
/// 这张表是拆包前的既有设计，收口安排在 Phase 3 第 6 批（三个 Provider 转成显式
/// 插件贡献）。在那之前**冻结它**：任何增删都必须先回到架构讨论，而不是顺手加
/// 一个 case——否则这笔欠债会在无人注意时继续变大。
void main() {
  test('AgentProviderKind 的取值集合被冻结', () {
    expect(AgentProviderKind.values.map((kind) => kind.name), <String>[
      'codexAppServer',
      'acp',
      'claudeCode',
    ]);
  });

  test('内置 Provider ID 与默认配置被冻结', () {
    expect(defaultAgentProviderId, 'codex');
    expect(grokAgentProviderId, 'grok');
    expect(defaultClaudeCodeProviderId, 'claude_code');

    expect(AgentProviderConfig.defaultCodex.command, 'codex');
    expect(AgentProviderConfig.defaultCodex.arguments, <String>['app-server']);
    expect(AgentProviderConfig.defaultGrok.command, 'grok');
    expect(AgentProviderConfig.defaultClaudeCode.command, 'claude');
  });

  test('内核里按 Provider 身份分支的文件只有这一个', () {
    final offenders = Directory('packages/zeta_agent_core/lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .where((file) {
          final codeOnly = file
              .readAsStringSync()
              .split('\n')
              .where((line) {
                final trimmed = line.trimLeft();
                return !trimmed.startsWith('//') && !trimmed.startsWith('///');
              })
              .join('\n');
          return codeOnly.contains('defaultAgentProviderId') ||
              codeOnly.contains('grokAgentProviderId') ||
              codeOnly.contains('defaultClaudeCodeProviderId') ||
              codeOnly.contains('claudeCodeAccountDataEnrichmentKey');
        })
        .map((file) => file.path.replaceAll(r'\', '/'))
        .toList(growable: false);

    expect(
      offenders,
      <String>[
        'packages/zeta_agent_core/lib/src/domain/agent_provider_models.dart',
      ],
      reason:
          '内置 Provider 身份只允许出现在这张待迁移的目录表里；'
          '其它内核文件必须保持 Provider 无关。',
    );
  });
}

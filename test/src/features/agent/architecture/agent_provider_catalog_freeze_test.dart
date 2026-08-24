import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 开放 Provider definition 目录守卫。
///
/// core 只保留开放 value object；内置身份与默认配置必须全部由 providers 插件拥有。
void main() {
  test('AgentProviderTypeId 接受插件声明的未来类型', () {
    const futureType = AgentProviderTypeId('future.protocol.v1');

    expect(futureType.value, 'future.protocol.v1');
    expect(futureType, const AgentProviderTypeId('future.protocol.v1'));
    expect(futureType, isNot(codexAgentProviderType));
  });

  test('内置 Provider ID 与默认配置由插件 definition 声明', () {
    expect(defaultAgentProviderId, 'codex');
    expect(grokAgentProviderId, 'grok');
    expect(defaultClaudeCodeProviderId, 'claude_code');

    expect(defaultCodexAgentProviderConfig.command, 'codex');
    expect(defaultCodexAgentProviderConfig.arguments, <String>['app-server']);
    expect(defaultGrokAgentProviderConfig.command, 'grok');
    expect(defaultClaudeCodeAgentProviderConfig.command, 'claude');
  });

  test('中立内核不含任何内置 Provider 身份或协议域', () {
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
              codeOnly.contains('claudeCodeAccountDataEnrichmentKey') ||
              codeOnly.contains('codexAppServer') ||
              codeOnly.contains("'acp'") ||
              codeOnly.contains("'claudeCode'");
        })
        .map((file) => file.path.replaceAll(r'\', '/'))
        .toList(growable: false);

    expect(
      offenders,
      isEmpty,
      reason: '内置 Provider 身份、默认配置和协议域只能由 providers 插件声明。',
    );
  });
}

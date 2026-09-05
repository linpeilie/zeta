library;

/// 宿主测试访问插件实现的唯一公共入口；身份常量走生产 manifest。

export 'package:zeta_agent_provider_codex/zeta_agent_provider_codex_testing.dart'
    hide
        defaultAgentProviderId,
        codexAgentProviderType,
        codexAgentProviderDefinition,
        defaultCodexAgentProviderConfig;
export 'package:zeta_agent_provider_grok/zeta_agent_provider_grok_testing.dart'
    hide
        grokAgentProviderId,
        grokAgentProviderType,
        grokAgentProviderDefinition,
        defaultGrokAgentProviderConfig;
export 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart'
    hide
        defaultClaudeCodeProviderId,
        claudeCodeAgentProviderType,
        claudeCodeAgentProviderDefinition,
        defaultClaudeCodeAgentProviderConfig;

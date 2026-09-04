import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta_agent_providers/claude_code_plugin.dart';
import 'package:zeta_agent_providers/codex_plugin.dart';
import 'package:zeta_agent_providers/grok_plugin.dart';
import 'package:zeta_agent_providers/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:zeta_agent_providers/src/datasources/claude_code/claude_code_hidden_thread_store.dart';
import 'package:zeta_agent_providers/src/datasources/claude_code/claude_code_permission_policy_adapter.dart';

/// 三个内置插件 definition 的编译期目录。
const List<AgentProviderDefinition> builtInAgentProviderDefinitions =
    <AgentProviderDefinition>[
      codexAgentProviderDefinition,
      grokAgentProviderDefinition,
      claudeCodeAgentProviderDefinition,
    ];

/// 与旧默认值逐字段相同的 Provider settings 测试/启动快照。
const AgentProviderSettings builtInAgentProviderSettings =
    AgentProviderSettings(
      providers: <AgentProviderConfig>[
        defaultCodexAgentProviderConfig,
        defaultGrokAgentProviderConfig,
        defaultClaudeCodeAgentProviderConfig,
      ],
      activeProviderId: defaultAgentProviderId,
    );

/// 不依赖插件激活的只读 definition 目录，供 codec/DI 测试构造。
final AgentProviderDefinitionCatalog builtInAgentProviderDefinitionCatalog =
    AgentProviderDefinitionCatalog(builtInAgentProviderDefinitions);

/// 根 app 唯一调用的 compile-time Provider 插件注册函数。
List<ZetaPluginFactory> createBuiltInAgentProviderPlugins({
  ClaudeCodeSessionDecisionStoreFactory? claudeCodeSessionDecisionStoreFactory,
  ClaudeCodeHiddenThreadStore? claudeCodeHiddenThreadStore,
  ClaudeCodeCliMetadataLoader? claudeCodeMetadataLoader,
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) => <ZetaPluginFactory>[
  CodexAgentProviderPlugin(textCatalog: textCatalog),
  GrokAgentProviderPlugin(textCatalog: textCatalog),
  ClaudeCodeAgentProviderPlugin(
    sessionDecisionStoreFactory: claudeCodeSessionDecisionStoreFactory,
    hiddenThreadStore: claudeCodeHiddenThreadStore,
    metadataLoader: claudeCodeMetadataLoader,
    textCatalog: textCatalog,
  ),
];

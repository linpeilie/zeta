/// Agent Provider 的编译期登记入口；新增插件在这里登记 definition、settings 与工厂。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/app/storage/zeta_storage_providers.dart';
import 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart';
import 'package:zeta_agent_provider_grok/zeta_agent_provider_grok.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

export 'package:zeta_agent_provider_codex/zeta_agent_provider_codex.dart'
    show
        defaultAgentProviderId,
        codexAgentProviderType,
        codexAgentProviderDefinition,
        defaultCodexAgentProviderConfig;
export 'package:zeta_agent_provider_grok/zeta_agent_provider_grok.dart'
    show
        grokAgentProviderId,
        grokAgentProviderType,
        grokAgentProviderDefinition,
        defaultGrokAgentProviderConfig;
export 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code.dart'
    show
        defaultClaudeCodeProviderId,
        claudeCodeAgentProviderType,
        claudeCodeAgentProviderDefinition,
        defaultClaudeCodeAgentProviderConfig;

/// 三个内置插件 definition 的编译期目录。
const List<AgentProviderDefinition> zetaAgentProviderDefinitions =
    <AgentProviderDefinition>[
      codexAgentProviderDefinition,
      grokAgentProviderDefinition,
      claudeCodeAgentProviderDefinition,
    ];

/// 与旧默认值逐字段相同的 Provider settings 测试/启动快照。
const AgentProviderSettings zetaBuiltInAgentProviderSettings =
    AgentProviderSettings(
      providers: <AgentProviderConfig>[
        defaultCodexAgentProviderConfig,
        defaultGrokAgentProviderConfig,
        defaultClaudeCodeAgentProviderConfig,
      ],
      activeProviderId: defaultAgentProviderId,
    );

/// 不依赖插件激活的只读 definition 目录，供 codec/DI 测试构造。
final AgentProviderDefinitionCatalog zetaAgentProviderDefinitionCatalog =
    AgentProviderDefinitionCatalog(zetaAgentProviderDefinitions);

/// 根 app 唯一调用的 compile-time Provider 插件注册函数。
List<ZetaPluginFactory> zetaAgentProviderPluginFactories({
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

/// 默认激活 Provider 的稳定身份。
const String zetaDefaultAgentProviderId = defaultAgentProviderId;

/// Claude Code 隐藏 thread 仓库。
final claudeCodeHiddenThreadStoreProvider =
    Provider<ClaudeCodeHiddenThreadStore>(
      (ref) => FileClaudeCodeHiddenThreadStore(
        storage: ref.watch(claudeHiddenThreadsStorageProvider),
      ),
      name: 'claudeCodeHiddenThreadStore',
    );

/// Claude Code 每会话决策仓库工厂。
final claudeCodeSessionDecisionStoreFactoryProvider =
    Provider<ClaudeCodeSessionDecisionStoreFactory>((ref) {
      final openStorage = ref.watch(
        claudeSessionDecisionStorageFactoryProvider,
      );
      return (sessionId) =>
          FileClaudeCodeSessionDecisionStore(storage: openStorage(sessionId));
    }, name: 'claudeCodeSessionDecisionStoreFactory');

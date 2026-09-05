import 'package:test/test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

/// 只激活被测插件，独立包测试不依赖其他 Provider。
AgentProviderBundleFactory activateBuiltInAgentProviderBundleFactory({
  ClaudeCodeCliMetadataLoader? claudeCodeMetadataLoader,
}) {
  final registry = ZetaPluginRegistry(
    factories: [
      ClaudeCodeAgentProviderPlugin(metadataLoader: claudeCodeMetadataLoader),
    ],
  );
  addTearDown(registry.close);
  final report = registry.activateAllSynchronously();
  if (report.isDegraded) {
    throw StateError('Provider plugin failed to activate');
  }
  return registry
      .contributions<AgentProviderPluginContribution>()
      .single
      .bundleFactory;
}

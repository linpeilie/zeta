import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';
import 'package:zeta/src/app/plugins/agent_provider_manifest.dart';
import 'agent_provider_implementations.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

/// 同步激活三个生产 Provider 插件，并把插件目录关闭登记到当前测试。
AgentProviderBundleFactory activateBuiltInAgentProviderBundleFactory({
  ClaudeCodeCliMetadataLoader? claudeCodeMetadataLoader,
}) {
  final registry = ZetaPluginRegistry(
    factories: zetaAgentProviderPluginFactories(
      claudeCodeMetadataLoader: claudeCodeMetadataLoader,
    ),
  );
  addTearDown(registry.close);
  final report = registry.activateAllSynchronously();
  if (report.isDegraded) {
    throw StateError('Built-in Agent provider plugins failed to activate');
  }
  return ResolvedAgentProviderPlugins(
    registry.contributions<AgentProviderPluginContribution>(),
  ).bundleFactory;
}

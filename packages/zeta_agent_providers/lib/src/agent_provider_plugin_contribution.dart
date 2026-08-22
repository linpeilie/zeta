import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Agent Provider 插件贡献：向宿主提供一个中立的 [AgentProviderBundleFactory]。
///
/// 这是首期唯一的贡献类型。它定义在 data 层（未来的 `zeta_agent_providers`）
/// 而不是内核里：内核不认识 Agent 语义，也不 import Provider 契约。
final class AgentProviderPluginContribution extends ZetaPluginContribution {
  const AgentProviderPluginContribution({required this.bundleFactory});

  /// 由该插件提供的 bundle 工厂。
  ///
  /// 工厂只被 `AgentProviderRuntimeRegistry` 调用；调用方仍必须显式传 scope。
  final AgentProviderBundleFactory bundleFactory;

  @override
  String get contributionKind => 'zeta.agent.provider-bundle-factory';
}

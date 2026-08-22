import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta/src/features/agent/data/agent_provider_plugin_contribution.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 过渡插件：把**现有**的 `DefaultAgentProviderFactory` 原样包成单个贡献。
///
/// ## 这是兼容层
///
/// - **owner**：架构迁移（Phase 1 引入）；
/// - **目的**：让宿主先改成"从插件目录取工厂"，而工厂内部按 kind 分派的 switch
///   保持一字不变——本阶段的目标是搬边界，不是改行为；
/// - **删除计划**：Phase 3 第 6 批把 Codex / Grok / Claude Code 拆成三个显式
///   compile-time 插件贡献后删除本文件，并同步删除
///   `ZetaPluginCatalog.compatibility` 入口；
/// - **使用点计数**：整个仓库只允许有 1 个实例，由
///   `test/src/app/plugins/zeta_plugin_catalog_test.dart` 断言。
///
/// 激活只是把已经构造好的工厂交出去，没有任何 IO，因此实现同步激活接口，
/// 保证启动关键路径不多等一个 microtask。
final class CompatibilityAgentProviderPlugin
    implements ZetaSynchronousPluginFactory {
  CompatibilityAgentProviderPlugin({required this.bundleFactory});

  /// 兼容插件的稳定 ID。
  static const String pluginId = 'zeta.agent.compatibility-provider-factory';

  /// 宿主已经构造好的工厂；插件不负责决定它怎么造。
  final AgentProviderBundleFactory bundleFactory;

  @override
  final ZetaPluginDescriptor descriptor = ZetaPluginDescriptor(
    id: pluginId,
    apiVersion: ZetaPluginApiVersion.current,
    // Agent Provider 是产品核心能力：缺了它应用必须显式进入 degraded 状态，
    // 而不是拿着一个空目录假装启动成功。
    essential: true,
  );

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) {
    return _CompatibilityAgentProviderHandle(
      AgentProviderPluginContribution(bundleFactory: bundleFactory),
    );
  }
}

final class _CompatibilityAgentProviderHandle implements ZetaPluginHandle {
  _CompatibilityAgentProviderHandle(this._contribution);

  final AgentProviderPluginContribution _contribution;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _contribution,
  ];

  @override
  Future<void> close() async {
    // 运行时进程的所有权仍在 AgentProviderRuntimeRegistry：兼容插件只是把工厂
    // 转交出去，不持有任何 CLI 进程，因此这里没有可释放的资源。
  }
}

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/agent_provider_plugin_contribution.dart';
import 'package:zeta/src/features/agent/data/compatibility_agent_provider_plugin.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

final _log = loggerFor('zeta.app.plugin_catalog');

/// 应用的**编译期**插件目录。
///
/// 这是唯一的插件注册点：目录是一段写死的 Dart 代码，不扫描目录、不下载、
/// 不反射。要新增插件就改这里，改动会经过评审和编译期检查。
///
/// 阶段 1 只登记一个兼容插件（[CompatibilityAgentProviderPlugin]），把现有
/// `DefaultAgentProviderFactory` 原样接进内核；Provider 的分派逻辑一字未动。
final class ZetaPluginCatalog {
  ZetaPluginCatalog._(this._registry);

  /// 兼容目录：只登记 Agent Provider 兼容插件。
  ///
  /// [bundleFactory] 由 app 组合层构造（它需要文本目录与持久化文件），插件
  /// 只负责把它作为贡献交给内核。
  factory ZetaPluginCatalog.compatibility({
    required AgentProviderBundleFactory bundleFactory,
    Clock clock = systemClock,
    ZetaMetricsPort metrics = noopZetaMetricsPort,
  }) {
    return ZetaPluginCatalog._(
      ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          CompatibilityAgentProviderPlugin(bundleFactory: bundleFactory),
        ],
        clock: clock,
        metrics: metrics,
      ),
    );
  }

  final ZetaPluginRegistry _registry;
  ZetaPluginActivationReport? _report;

  /// 内核注册表；只暴露给诊断与测试，业务代码通过本目录取贡献。
  ZetaPluginRegistry get registry => _registry;

  /// 最近一次激活报告；尚未激活时为 null。
  ZetaPluginActivationReport? get report => _report;

  /// 在启动关键路径上同步激活全部插件。
  ///
  /// 同步是有意的：首帧就需要 Agent Provider 工厂，异步激活会引入一个"还没有
  /// 工厂"的中间态。可信插件的激活只是构造对象图，本来就没有 IO。
  ZetaPluginActivationReport activate() {
    final report = _registry.activateAllSynchronously();
    _report = report;
    if (report.isDegraded) {
      // 只记录 ID 与分类，不记录异常文本（G7）。
      _log.e(
        'Essential Zeta plugins failed to activate: '
        '${report.failedIds.join(', ')}',
      );
    }
    return report;
  }

  /// 取出唯一的 Agent Provider 工厂。
  ///
  /// **fail-closed**：没有任何插件贡献工厂时抛 [StateError]，而不是回退到某个
  /// 内置默认值——静默降级会让用户以为 Provider 正常可用。
  AgentProviderBundleFactory resolveAgentProviderBundleFactory() {
    final contributions = _registry
        .contributions<AgentProviderPluginContribution>();
    if (contributions.isEmpty) {
      throw StateError(
        'No plugin contributed an AgentProviderBundleFactory; '
        'the app cannot start Agent providers',
      );
    }
    if (contributions.length > 1) {
      // 阶段 1 只允许一个贡献者。多个工厂意味着"谁来造 bundle"没有唯一答案，
      // 必须先在目录层面解决，不能在这里随便挑一个。
      throw StateError(
        'Expected exactly one AgentProviderBundleFactory contribution, '
        'found ${contributions.length}',
      );
    }
    return contributions.single.bundleFactory;
  }

  /// 关闭全部插件（按激活反序）。
  Future<void> close() => _registry.close();
}

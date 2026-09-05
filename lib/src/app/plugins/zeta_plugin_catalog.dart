import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta_agent_provider_api/zeta_agent_provider_api.dart';

final _log = loggerFor('zeta.app.plugin_catalog');

/// 应用的**编译期**插件目录。
///
/// 这是唯一的插件注册点：目录是一段写死的 Dart 代码，不扫描目录、不下载、
/// 不反射。要新增插件就改这里，改动会经过评审和编译期检查。
///
/// Provider 工厂由 agent_provider_manifest.dart 显式登记并传入；目录只负责激活。
final class ZetaPluginCatalog {
  ZetaPluginCatalog._(this._registry);

  /// 创建三个显式内置 Provider 插件的编译期目录。
  factory ZetaPluginCatalog.builtIn({
    required Iterable<ZetaPluginFactory> factories,
    Clock clock = systemClock,
    ZetaMetricsPort metrics = noopZetaMetricsPort,
  }) {
    return ZetaPluginCatalog._(
      ZetaPluginRegistry(factories: factories, clock: clock, metrics: metrics),
    );
  }

  /// 测试专用目录，用来覆盖重复域、激活失败与反序关闭等 fail-closed 契约。
  factory ZetaPluginCatalog.forTesting({
    required Iterable<ZetaPluginFactory> factories,
    Clock clock = systemClock,
    ZetaMetricsPort metrics = noopZetaMetricsPort,
  }) => ZetaPluginCatalog._(
    ZetaPluginRegistry(factories: factories, clock: clock, metrics: metrics),
  );

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

  /// 解析激活后的 Provider definitions 与聚合 bundle factory。
  ///
  /// **fail-closed**：未激活、任一 essential 插件失败、无贡献或重复 Provider
  /// type 时均抛 [StateError]，绝不返回部分目录或回落到 Codex。
  ResolvedAgentProviderPlugins resolveAgentProviders() {
    final report = _report;
    if (report == null) {
      throw StateError('Zeta plugins must be activated before resolve');
    }
    if (report.isDegraded) {
      throw StateError('Essential Agent provider plugins failed to activate');
    }
    for (final state in report.states) {
      if (state.status != ZetaPluginStatus.active ||
          !state.descriptor.essential) {
        continue;
      }
      final ownedContributions = _registry
          .contributionsOf<AgentProviderPluginContribution>(
            state.descriptor.id,
          );
      if (ownedContributions.length != 1) {
        throw StateError(
          'Essential Agent provider plugin ${state.descriptor.id} must '
          'contribute exactly one provider definition',
        );
      }
    }
    final contributions = _registry
        .contributions<AgentProviderPluginContribution>();
    if (contributions.isEmpty) {
      throw StateError(
        'No plugin contributed an Agent provider definition; '
        'the app cannot start Agent providers',
      );
    }
    return ResolvedAgentProviderPlugins(contributions);
  }

  /// 校验每个激活 Provider 自身拥有的管理与用量贡献，禁止串用其他插件身份。
  ResolvedAgentHostContributions resolveAgentHostContributions() {
    resolveAgentProviders();
    final management = <AgentManagementContribution>[];
    final usage = <AgentUsageContribution>[];
    final managementIds = <String>{};
    final usageTypes = <Object>{};
    for (final state in _registry.states) {
      if (state.status != ZetaPluginStatus.active) continue;
      final id = state.descriptor.id;
      final providers = _registry
          .contributionsOf<AgentProviderPluginContribution>(id);
      final managed = _registry.contributionsOf<AgentManagementContribution>(
        id,
      );
      final sources = _registry.contributionsOf<AgentUsageContribution>(id);
      if (providers.isEmpty && managed.isEmpty && sources.isEmpty) continue;
      if (providers.length != 1 || managed.length != 1 || sources.length != 1) {
        throw StateError(
          'Agent plugin must contribute one provider, management repository and usage source',
        );
      }
      final definition = providers.single.definition;
      final managementContribution = managed.single;
      final usageContribution = sources.single;
      if (managementContribution.providerId != definition.providerId ||
          managementContribution.definition.id != definition.providerId ||
          usageContribution.providerType != definition.providerType ||
          !managementIds.add(managementContribution.providerId) ||
          !usageTypes.add(usageContribution.providerType)) {
        throw StateError(
          'Duplicate or mismatched Agent host contribution identity',
        );
      }
      management.add(managementContribution);
      usage.add(usageContribution);
    }
    if (management.isEmpty || usage.isEmpty) {
      throw StateError('No plugin contributed Agent host services');
    }
    return ResolvedAgentHostContributions(management: management, usage: usage);
  }

  /// 激活并解析启动必需的 Provider；任一步失败都会立即回收已激活 handle。
  ///
  /// 该同步组合方法不把半激活目录交给调用方。插件关闭可以包含异步清理，因此
  /// 失败会原样抛回启动路径，同时在后台完成反序关闭。
  ResolvedAgentProviderPlugins activateAndResolveAgentProviders() {
    try {
      activate();
      return resolveAgentProviders();
    } on Object catch (error, stackTrace) {
      unawaited(_closeAfterFailedActivation());
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// 关闭全部插件（按激活反序）。
  Future<void> close() => _registry.close();

  Future<void> _closeAfterFailedActivation() async {
    try {
      await close();
    } on Object {
      // 启动异常仍是首要失败；这里只记录稳定分类，避免泄漏插件异常正文。
      _log.e('Could not close plugins after Agent provider activation failed');
    }
  }
}

/// 从同一次激活结果提取的不可变宿主贡献。
final class ResolvedAgentHostContributions {
  ResolvedAgentHostContributions({
    required Iterable<AgentManagementContribution> management,
    required Iterable<AgentUsageContribution> usage,
  }) : management = List.unmodifiable(management),
       usage = List.unmodifiable(usage);
  final List<AgentManagementContribution> management;
  final List<AgentUsageContribution> usage;
}

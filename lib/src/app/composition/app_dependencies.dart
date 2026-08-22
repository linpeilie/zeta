/// 应用级依赖 Provider。
///
/// 阶段 1 只把**可注入的基础依赖**放进 Riverpod，业务状态一律不动：
/// feature controller 仍是各自业务事实的唯一 owner，Riverpod 目前只承担
/// "组合根 + 覆盖点"的角色。
///
/// 约定：
///
/// - 有安全默认值的依赖（时钟、no-op 指标端口）直接给默认实现；
/// - 没有安全默认值的依赖（例如 Agent Provider 工厂）**fail-closed**：
///   未覆盖就抛错，绝不静默返回一个假的实现；
/// - 测试用 `ProviderContainer(overrides: ...)` 注入 fake，业务代码不读全局容器。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// 系统时钟；测试与回放通过覆盖注入固定时钟。
final zetaClockProvider = Provider<Clock>(
  (ref) => systemClock,
  name: 'zeta.clock',
);

/// 脱敏指标端口。
///
/// 默认 no-op：未显式开启可观测性时，读到它的调用方只剩一次常量分支。
/// 生产由 `main` 用 `ZetaObservability` 的实例覆盖。
final zetaMetricsPortProvider = Provider<ZetaMetricsPort>(
  (ref) => noopZetaMetricsPort,
  name: 'zeta.metrics',
);

/// 必须由组合根覆盖的依赖 Provider 基类工具。
///
/// 用它声明"没有默认实现"的依赖，读取未覆盖的 Provider 会立刻失败，
/// 而不是等到某个功能静默不工作时才被发现。
Provider<T> requiredDependency<T>(String name) {
  return Provider<T>(
    (ref) => throw StateError(
      'Dependency "$name" was read before the composition root overrode it',
    ),
    name: name,
  );
}

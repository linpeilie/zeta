import 'package:zeta_foundation/zeta_foundation.dart';

/// 宿主提供的插件 API 版本。
///
/// 插件在 descriptor 里声明自己针对哪个主版本编写；主版本不一致时内核
/// **fail-closed**，不做"尽量兼容"的猜测。次版本只允许向后兼容的新增。
final class ZetaPluginApiVersion {
  const ZetaPluginApiVersion(this.major, this.minor);

  /// 当前宿主实现的 API 版本。
  static const ZetaPluginApiVersion current = ZetaPluginApiVersion(1, 0);

  final int major;
  final int minor;

  /// 宿主 [current] 能否加载声明了 `this` 的插件。
  bool get isSupportedByHost =>
      major == current.major && minor <= current.minor;

  @override
  bool operator ==(Object other) =>
      other is ZetaPluginApiVersion &&
      other.major == major &&
      other.minor == minor;

  @override
  int get hashCode => Object.hash(major, minor);

  @override
  String toString() => '$major.$minor';
}

/// 插件的编译期稳定元数据。
///
/// descriptor 只描述"这是谁、需要什么、什么时候启动"，不含任何运行期状态，
/// 也不含用户内容——它会进日志和指标。
final class ZetaPluginDescriptor {
  ZetaPluginDescriptor({
    required this.id,
    required this.apiVersion,
    this.dependsOn = const <String>[],
    this.essential = false,
  }) : assert(id != ''),
       dependencies = List<String>.unmodifiable(dependsOn);

  /// 稳定插件 ID（形如 `zeta.agent.codex`），日志与指标里的唯一标识。
  final String id;

  /// 插件面向的宿主 API 版本。
  final ZetaPluginApiVersion apiVersion;

  /// 依赖的插件 ID；内核据此做拓扑排序。
  final List<String> dependsOn;

  /// 只读依赖视图。
  final List<String> dependencies;

  /// 是否为核心必需插件。
  ///
  /// 必需插件激活失败时，应用进入明确的 degraded 状态，而不是假装成功。
  final bool essential;

  @override
  String toString() => 'ZetaPluginDescriptor($id, api $apiVersion)';
}

/// 插件贡献的基类。
///
/// 内核只负责登记与分发贡献，**不理解**任何具体贡献的语义，因此这里不是
/// `sealed`：具体贡献类型（例如 Agent Provider 贡献）定义在各自的 Package
/// 里，内核不 import 它们，也不按 ID 做 switch。
abstract base class ZetaPluginContribution {
  const ZetaPluginContribution();

  /// 贡献所属的稳定类别标签，仅用于诊断分组。
  String get contributionKind;
}

/// 内核在激活时交给插件的窄端口集合。
///
/// 它**不是** `BuildContext`、`ProviderContainer` 或 service locator：只提供
/// 插件自身的 descriptor、时钟和脱敏指标端口。需要更多能力时必须显式扩展这个
/// 契约，并同步更新能力声明。
final class ZetaPluginContext {
  const ZetaPluginContext({
    required this.descriptor,
    required this.clock,
    required this.metrics,
  });

  final ZetaPluginDescriptor descriptor;
  final Clock clock;
  final ZetaMetricsPort metrics;
}

/// 编译期注册的插件工厂。
abstract interface class ZetaPluginFactory {
  ZetaPluginDescriptor get descriptor;

  /// 激活插件并返回句柄；抛异常等价于激活失败。
  Future<ZetaPluginHandle> activate(ZetaPluginContext context);
}

/// 可同步激活的编译期插件。
///
/// 可信插件的激活通常只是构造对象图，没有任何 IO。实现这个接口的插件可以在
/// **启动关键路径**上被同步激活：宿主不必为了等一个必然立即完成的 Future 而
/// 把首帧推迟到下一个 microtask。
///
/// [ZetaPluginFactory.activate] 仍然保留，异步宿主路径可以照常使用。
abstract interface class ZetaSynchronousPluginFactory
    implements ZetaPluginFactory {
  /// 同步激活；抛异常等价于激活失败。
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context);
}

/// 已激活插件的句柄。
abstract interface class ZetaPluginHandle {
  List<ZetaPluginContribution> get contributions;

  Future<void> close();
}

/// 插件生命周期状态。
enum ZetaPluginStatus { registered, activating, active, failed, stopped }

/// 插件激活失败的分类。
///
/// 只记录分类，不记录原始异常文本——原因文本可能带路径或凭证。
enum ZetaPluginFailureReason {
  /// descriptor 声明的 API 主版本与宿主不符。
  apiVersionMismatch,

  /// 依赖的插件缺失。
  missingDependency,

  /// 依赖图存在环。
  dependencyCycle,

  /// 依赖的插件本身激活失败。
  dependencyFailed,

  /// 插件 `activate` 抛出异常。
  activationThrew,

  /// 宿主要求同步激活，但该插件只支持异步激活。
  requiresSynchronousActivation,
}

/// 单个插件的只读运行状态。
final class ZetaPluginState {
  const ZetaPluginState({
    required this.descriptor,
    required this.status,
    this.failureReason,
    this.contributionKinds = const <String>[],
  });

  final ZetaPluginDescriptor descriptor;
  final ZetaPluginStatus status;

  /// 仅当 [status] 为 [ZetaPluginStatus.failed] 时存在。
  final ZetaPluginFailureReason? failureReason;

  /// 该插件贡献的类别标签，便于诊断而不暴露贡献实例。
  final List<String> contributionKinds;

  @override
  String toString() =>
      'ZetaPluginState(${descriptor.id}, ${status.name}'
      '${failureReason == null ? '' : ', ${failureReason!.name}'})';
}

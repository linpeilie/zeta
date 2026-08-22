import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta_plugin_kernel/src/plugin_contracts.dart';

/// 一次 `activateAll` 的只读结果。
final class ZetaPluginActivationReport {
  ZetaPluginActivationReport({
    required this.generation,
    required Iterable<ZetaPluginState> states,
    required Iterable<String> activationOrder,
  }) : states = List<ZetaPluginState>.unmodifiable(states),
       activeIds = List<String>.unmodifiable(activationOrder);

  /// 本次激活的代数；旧代数的回调必须被丢弃。
  final int generation;

  /// 全部插件状态，按注册顺序（含未激活与失败的插件）。
  final List<ZetaPluginState> states;

  /// 成功激活的插件 ID，按实际激活顺序（依赖在前）。
  final List<String> activeIds;

  /// 激活失败的插件 ID。
  List<String> get failedIds => states
      .where((state) => state.status == ZetaPluginStatus.failed)
      .map((state) => state.descriptor.id)
      .toList(growable: false);

  /// 是否有**核心必需**插件失败。
  ///
  /// 为 true 时应用必须进入明确的 degraded 状态，不允许假装启动成功。
  bool get isDegraded => states.any(
    (state) =>
        state.descriptor.essential && state.status != ZetaPluginStatus.active,
  );
}

/// 可信插件的编译期注册表与生命周期目录。
///
/// 内核只做四件事：登记、按拓扑序激活、汇总贡献、按反序关闭。它**不认识**任何
/// 具体 Provider：没有 provider/plugin ID 的 switch，也不 import 任何插件实现。
///
/// fail-closed 规则：
///
/// - 重复 ID：构造即抛（编译期目录写错了，不该拖到运行期）；
/// - API 主版本不符 / 依赖缺失 / 依赖成环 / 依赖失败 / `activate` 抛异常：
///   该插件进入 [ZetaPluginStatus.failed]，其余插件继续激活；
/// - 必需插件失败：报告 [ZetaPluginActivationReport.isDegraded]。
final class ZetaPluginRegistry {
  ZetaPluginRegistry({
    required Iterable<ZetaPluginFactory> factories,
    this.clock = systemClock,
    this.metrics = noopZetaMetricsPort,
  }) {
    for (final factory in factories) {
      final id = factory.descriptor.id;
      if (_factories.containsKey(id)) {
        throw ArgumentError.value(id, 'factories', '插件 ID 重复注册');
      }
      _factories[id] = factory;
      _states[id] = ZetaPluginState(
        descriptor: factory.descriptor,
        status: ZetaPluginStatus.registered,
      );
    }
  }

  /// 注入的时钟；插件 context 与激活耗时都用它。
  final Clock clock;

  /// 脱敏指标端口；默认 no-op。
  final ZetaMetricsPort metrics;
  final Map<String, ZetaPluginFactory> _factories =
      <String, ZetaPluginFactory>{};
  final Map<String, ZetaPluginState> _states = <String, ZetaPluginState>{};
  final Map<String, ZetaPluginHandle> _handles = <String, ZetaPluginHandle>{};

  /// 激活时**一次性冻结**的贡献快照。
  ///
  /// 不保存快照、每次回调插件 getter 的话，一个 getter 抛异常的坏插件会在每次
  /// `contributions()` 时把异常抛给调用方，等于用一个插件阻断整个 catalog。
  final Map<String, List<ZetaPluginContribution>> _contributions =
      <String, List<ZetaPluginContribution>>{};
  final List<String> _activationOrder = <String>[];

  int _generation = 0;
  bool _closed = false;
  Future<void>? _closeFuture;
  Future<ZetaPluginActivationReport>? _activation;

  /// 关闭期间到达、需要就地释放的迟到句柄；`close()` 必须等它们收尾。
  final List<Future<void>> _lateHandleCloses = <Future<void>>[];

  /// 当前激活代数；每次 [activateAll] 递增。
  int get activationGeneration => _generation;

  /// 全部插件的只读状态，按注册顺序。
  List<ZetaPluginState> get states =>
      List<ZetaPluginState>.unmodifiable(_states.values);

  /// 查询单个插件状态。
  ZetaPluginState? stateOf(String pluginId) => _states[pluginId];

  /// 汇总所有 active 插件里类型为 [T] 的贡献。
  ///
  /// 调用方按类型取自己认识的贡献；内核不解释贡献语义。
  List<T> contributions<T extends ZetaPluginContribution>() {
    if (_closed) {
      // 已关闭的内核不再对外供货：宁可让调用方 fail-closed，也不给出可能
      // 已经释放资源的贡献。
      return const [];
    }
    final result = <T>[];
    for (final id in _activationOrder) {
      final snapshot = _contributions[id];
      if (snapshot == null) {
        continue;
      }
      result.addAll(snapshot.whereType<T>());
    }
    return List<T>.unmodifiable(result);
  }

  /// 按拓扑序激活全部插件。
  ///
  /// 每个 registry 只能激活一次：编译期目录没有"重新激活"的语义，而重复激活会
  /// 覆盖旧句柄（旧句柄再也关不掉）并让同一个插件的贡献出现两遍。需要换代时应
  /// 关闭本实例、重建一个新的 registry。
  Future<ZetaPluginActivationReport> activateAll() {
    final inFlight = _activation;
    if (inFlight != null) {
      throw StateError(
        'ZetaPluginRegistry has already been activated; '
        'create a new registry instead of re-activating',
      );
    }
    _assertNotClosed();
    final activation = _activateAllOnce();
    _activation = activation;
    return activation;
  }

  Future<ZetaPluginActivationReport> _activateAllOnce() async {
    _generation += 1;
    metrics.gauge(ZetaMetric.pluginActivationGeneration, _generation);

    final order = _resolveActivationOrder();
    for (final id in order) {
      // 每一步都重新检查：close() 可能在上一次 await 期间跑完。
      if (_closed) {
        break;
      }
      await _activateOne(id);
    }
    metrics.gauge(ZetaMetric.pluginActiveCount, _handles.length);
    return ZetaPluginActivationReport(
      generation: _generation,
      states: _states.values,
      activationOrder: _activationOrder,
    );
  }

  /// 同步激活全部插件。
  ///
  /// 只接受实现了 [ZetaSynchronousPluginFactory] 的插件；其余插件 fail-closed
  /// 标记为 [ZetaPluginFailureReason.requiresSynchronousActivation]，而不是被
  /// 静默跳过。启动关键路径（例如首帧就要拿到 Agent Provider 工厂）用这个入口。
  ZetaPluginActivationReport activateAllSynchronously() {
    if (_activation != null) {
      throw StateError(
        'ZetaPluginRegistry has already been activated; '
        'create a new registry instead of re-activating',
      );
    }
    _assertNotClosed();
    _generation += 1;
    metrics.gauge(ZetaMetric.pluginActivationGeneration, _generation);

    final order = _resolveActivationOrder();
    for (final id in order) {
      final factory = _factories[id]!;
      if (factory is! ZetaSynchronousPluginFactory) {
        _markFailed(id, ZetaPluginFailureReason.requiresSynchronousActivation);
        continue;
      }
      final blocker = _blockingReasonFor(factory.descriptor);
      if (blocker != null) {
        _markFailed(id, blocker);
        continue;
      }
      _activateSynchronously(id, factory);
    }
    metrics.gauge(ZetaMetric.pluginActiveCount, _handles.length);
    final report = ZetaPluginActivationReport(
      generation: _generation,
      states: _states.values,
      activationOrder: _activationOrder,
    );
    _activation = Future<ZetaPluginActivationReport>.value(report);
    return report;
  }

  /// 按激活反序关闭全部插件。
  ///
  /// 并发调用返回**同一个**关闭任务：只看 `_closed` 标志会让第二个调用方在句柄
  /// 还没释放时就拿到"已完成"，从而以为资源全放完了。`MainApp.dispose` 与桌面
  /// 窗口关闭 hook 就可能同时触发这里。
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) {
      return existing;
    }
    final future = _closeOnce();
    _closeFuture = future;
    return future;
  }

  Future<void> _closeOnce() async {
    // 同步置位：激活循环靠它提前退出，不能等到第一个 await 之后。
    _closed = true;
    // 在途激活必须先结束，否则它恢复后会把句柄写进已关闭的 registry 并永久泄漏。
    // 激活循环自己会看到 _closed 提前退出，这里只等它收尾。
    final activation = _activation;
    if (activation != null) {
      try {
        await activation;
      } catch (_) {
        // 激活失败不影响关闭流程；失败分类已经记在插件状态里。
      }
    }
    for (final id in _activationOrder.reversed) {
      _contributions.remove(id);
      final handle = _handles.remove(id);
      if (handle == null) {
        continue;
      }
      try {
        await handle.close();
      } catch (_) {
        // 单个插件关闭失败不能阻断其余插件的关闭；异常文本不进日志/指标。
      }
      metrics.counter(ZetaMetric.pluginClosed, tags: _tagsFor(id));
      _states[id] = ZetaPluginState(
        descriptor: _states[id]!.descriptor,
        status: ZetaPluginStatus.stopped,
      );
    }
    // 迟到句柄的释放同样属于关闭流程：close() 返回时不能还有句柄在半路。
    if (_lateHandleCloses.isNotEmpty) {
      final pending = List<Future<void>>.of(_lateHandleCloses);
      _lateHandleCloses.clear();
      await Future.wait(pending);
    }
    _activationOrder.clear();
    metrics.gauge(ZetaMetric.pluginActiveCount, 0);
  }

  Future<void> _activateOne(String id) async {
    final factory = _factories[id]!;
    final descriptor = factory.descriptor;

    final blocker = _blockingReasonFor(descriptor);
    if (blocker != null) {
      _markFailed(id, blocker);
      return;
    }

    _states[id] = ZetaPluginState(
      descriptor: descriptor,
      status: ZetaPluginStatus.activating,
    );
    final startedAt = clock();
    try {
      final handle = await factory.activate(
        ZetaPluginContext(
          descriptor: descriptor,
          clock: clock,
          metrics: metrics,
        ),
      );
      _adoptHandle(id, descriptor, handle, startedAt);
    } catch (_) {
      // 只记录分类：异常文本可能带路径、命令或凭证（G7）。
      _markFailed(id, ZetaPluginFailureReason.activationThrew);
    }
  }

  void _activateSynchronously(String id, ZetaSynchronousPluginFactory factory) {
    final descriptor = factory.descriptor;
    _states[id] = ZetaPluginState(
      descriptor: descriptor,
      status: ZetaPluginStatus.activating,
    );
    final startedAt = clock();
    try {
      _adoptHandle(
        id,
        descriptor,
        factory.activateSynchronously(
          ZetaPluginContext(
            descriptor: descriptor,
            clock: clock,
            metrics: metrics,
          ),
        ),
        startedAt,
      );
    } catch (_) {
      _markFailed(id, ZetaPluginFailureReason.activationThrew);
    }
  }

  void _adoptHandle(
    String id,
    ZetaPluginDescriptor descriptor,
    ZetaPluginHandle handle,
    DateTime startedAt,
  ) {
    if (_closed) {
      // 迟到的激活结果：registry 已经关闭，句柄不能登记（登记了就再也不会被
      // 关闭），直接就地释放并把状态标成 stopped。
      _states[id] = ZetaPluginState(
        descriptor: descriptor,
        status: ZetaPluginStatus.stopped,
      );
      _lateHandleCloses.add(_closeQuietly(handle, id));
      return;
    }
    // 先把贡献读成不可变快照：读取过程仍属于"激活"，失败必须落在该插件头上，
    // 而不是等到别人调用 contributions() 时才炸。
    final List<ZetaPluginContribution> snapshot;
    final Set<String> kinds;
    try {
      snapshot = List<ZetaPluginContribution>.unmodifiable(
        handle.contributions,
      );
      kinds = <String>{
        for (final contribution in snapshot) contribution.contributionKind,
      };
    } catch (_) {
      // 坏插件不能留在 registry 里：句柄就地释放，状态标 failed，其余插件不受影响。
      _markFailed(id, ZetaPluginFailureReason.activationThrew);
      _lateHandleCloses.add(_closeQuietly(handle, id));
      return;
    }

    // 快照成功后才原子登记，三张表要么一起写、要么都不写。
    _handles[id] = handle;
    _contributions[id] = snapshot;
    _activationOrder.add(id);
    _states[id] = ZetaPluginState(
      descriptor: descriptor,
      status: ZetaPluginStatus.active,
      contributionKinds: List<String>.unmodifiable(kinds),
    );
    metrics
      ..counter(ZetaMetric.pluginActivated, tags: _tagsFor(id))
      ..duration(
        ZetaMetric.pluginActivationDuration,
        clock().difference(startedAt),
        tags: _tagsFor(id),
      );
  }

  Future<void> _closeQuietly(ZetaPluginHandle handle, String id) async {
    try {
      await handle.close();
    } catch (_) {
      // 关闭失败不能冒泡到业务路径；异常文本不进日志/指标（G7）。
    }
    metrics.counter(ZetaMetric.pluginClosed, tags: _tagsFor(id));
  }

  void _assertNotClosed() {
    if (_closed) {
      throw StateError('ZetaPluginRegistry is closed');
    }
  }

  /// 激活前的静态阻断判定，全部 fail-closed。
  ZetaPluginFailureReason? _blockingReasonFor(ZetaPluginDescriptor descriptor) {
    if (!descriptor.apiVersion.isSupportedByHost) {
      return ZetaPluginFailureReason.apiVersionMismatch;
    }
    for (final dependency in descriptor.dependencies) {
      final state = _states[dependency];
      if (state == null) {
        return ZetaPluginFailureReason.missingDependency;
      }
      if (state.status != ZetaPluginStatus.active) {
        return ZetaPluginFailureReason.dependencyFailed;
      }
    }
    return null;
  }

  void _markFailed(String id, ZetaPluginFailureReason reason) {
    _states[id] = ZetaPluginState(
      descriptor: _states[id]!.descriptor,
      status: ZetaPluginStatus.failed,
      failureReason: reason,
    );
    metrics.counter(
      ZetaMetric.pluginActivationFailed,
      tags: ZetaMetricTags(
        component: ZetaMetricLabel.declaredIdentifier(id),
        outcome: ZetaMetricOutcome.failure,
      ),
    );
  }

  /// 稳定的激活顺序：依赖在前，同层按注册顺序。
  ///
  /// 环上的插件直接标记为 [ZetaPluginFailureReason.dependencyCycle]，依赖了环但
  /// 自身不在环上的插件标记为 [ZetaPluginFailureReason.dependencyFailed]。两类
  /// 都不会进入激活序列——一次错误的目录配置不能静默降级成"随机顺序启动"。
  List<String> _resolveActivationOrder() {
    final visited = <String>{};
    final visiting = <String>{};
    final order = <String>[];
    final inCycle = <String>{};
    final blocked = <String>{};

    final stack = <String>[];

    bool visit(String id) {
      if (visited.contains(id)) {
        return !inCycle.contains(id) && !blocked.contains(id);
      }
      if (!visiting.add(id)) {
        // 回边：从被再次访问的节点起，当前路径上的所有节点都在环上。
        inCycle.addAll(stack.sublist(stack.indexOf(id)));
        return false;
      }
      stack.add(id);
      var healthy = true;
      for (final dependency in _factories[id]!.descriptor.dependencies) {
        if (!_factories.containsKey(dependency)) {
          continue; // 缺失依赖由 _blockingReasonFor 统一判定。
        }
        if (!visit(dependency)) {
          healthy = false;
        }
      }
      visiting.remove(id);
      stack.removeLast();
      visited.add(id);
      if (!healthy) {
        // 已经在回边上被标成环成员的节点保持原分类。
        if (!inCycle.contains(id)) {
          blocked.add(id);
        }
        return false;
      }
      if (inCycle.contains(id)) {
        return false;
      }
      order.add(id);
      return true;
    }

    for (final id in _factories.keys) {
      visit(id);
    }
    for (final id in inCycle) {
      _markFailed(id, ZetaPluginFailureReason.dependencyCycle);
    }
    for (final id in blocked) {
      _markFailed(id, ZetaPluginFailureReason.dependencyFailed);
    }
    return order;
  }

  /// 插件 ID 来自编译期目录；形态异常时 [ZetaMetricLabel] 会自动降级为 hash。
  ZetaMetricTags _tagsFor(String pluginId) => metrics.isEnabled
      ? ZetaMetricTags(component: ZetaMetricLabel.declaredIdentifier(pluginId))
      : ZetaMetricTags.none;
}

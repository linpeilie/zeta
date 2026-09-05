import 'dart:async';
import 'package:test/test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_plugin_kernel/zeta_plugin_kernel.dart';

void main() {
  group('ZetaPluginRegistry 注册', () {
    test('重复 ID 直接 fail-closed', () {
      expect(
        () => ZetaPluginRegistry(
          factories: <ZetaPluginFactory>[
            _FakePluginFactory(id: 'a'),
            _FakePluginFactory(id: 'a'),
          ],
        ),
        throwsArgumentError,
      );
    });

    test('未激活前全部处于 registered', () {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );

      expect(registry.stateOf('a')!.status, ZetaPluginStatus.registered);
      expect(registry.activationGeneration, 0);
      expect(registry.contributions<_FakeContribution>(), isEmpty);
    });
  });

  group('ZetaPluginRegistry 激活顺序', () {
    test('依赖在前，关闭按反序', () async {
      final log = <String>[];
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'ui', dependsOn: <String>['core'], log: log),
          _FakePluginFactory(id: 'core', log: log),
        ],
      );

      final report = await registry.activateAll();
      await registry.close();

      expect(report.activeIds, <String>['core', 'ui']);
      expect(log, <String>[
        'activate:core',
        'activate:ui',
        'close:ui',
        'close:core',
      ]);
      expect(report.isDegraded, isFalse);
    });

    test('重复激活 fail-closed，不覆盖旧句柄也不重复贡献', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );

      final first = await registry.activateAll();

      expect(first.generation, 1);
      expect(registry.activateAll, throwsStateError);
      expect(registry.activateAllSynchronously, throwsStateError);
      expect(registry.contributions<_FakeContribution>(), hasLength(1));
      expect(registry.activationGeneration, 1);
    });

    test('同步激活后同样禁止再次激活', () {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );

      registry.activateAllSynchronously();

      expect(registry.activateAllSynchronously, throwsStateError);
      expect(registry.activateAll, throwsStateError);
      expect(registry.contributions<_FakeContribution>(), hasLength(1));
    });
  });

  group('ZetaPluginRegistry fail-closed', () {
    test('API 主版本不符的插件不激活，其余插件不受影响', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(
            id: 'future',
            apiVersion: const ZetaPluginApiVersion(99, 0),
          ),
          _FakePluginFactory(id: 'ok'),
        ],
      );

      final report = await registry.activateAll();

      expect(
        registry.stateOf('future')!.failureReason,
        ZetaPluginFailureReason.apiVersionMismatch,
      );
      expect(report.activeIds, <String>['ok']);
    });

    test('缺失依赖的插件标记 missingDependency', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'a', dependsOn: <String>['nope']),
        ],
      );

      await registry.activateAll();

      expect(
        registry.stateOf('a')!.failureReason,
        ZetaPluginFailureReason.missingDependency,
      );
    });

    test('依赖成环时环上插件全部失败，环外依赖者标记 dependencyFailed', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'a', dependsOn: <String>['b']),
          _FakePluginFactory(id: 'b', dependsOn: <String>['a']),
          _FakePluginFactory(id: 'c', dependsOn: <String>['a']),
          _FakePluginFactory(id: 'standalone'),
        ],
      );

      final report = await registry.activateAll();

      expect(
        registry.stateOf('a')!.failureReason,
        ZetaPluginFailureReason.dependencyCycle,
      );
      expect(
        registry.stateOf('b')!.failureReason,
        ZetaPluginFailureReason.dependencyCycle,
      );
      expect(
        registry.stateOf('c')!.failureReason,
        ZetaPluginFailureReason.dependencyFailed,
      );
      expect(report.activeIds, <String>['standalone']);
    });

    test('单个插件抛异常只影响自己与其依赖者', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'broken', throwsOnActivate: true),
          _FakePluginFactory(id: 'dependent', dependsOn: <String>['broken']),
          _FakePluginFactory(id: 'healthy'),
        ],
      );

      final report = await registry.activateAll();

      expect(
        registry.stateOf('broken')!.failureReason,
        ZetaPluginFailureReason.activationThrew,
      );
      expect(
        registry.stateOf('dependent')!.failureReason,
        ZetaPluginFailureReason.dependencyFailed,
      );
      expect(report.activeIds, contains('healthy'));
      expect(report.failedIds, <String>['broken', 'dependent']);
    });

    test('核心必需插件失败会产生明确的 degraded 状态', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(
            id: 'essential',
            essential: true,
            throwsOnActivate: true,
          ),
        ],
      );

      final report = await registry.activateAll();

      expect(report.isDegraded, isTrue);
    });

    test('关闭后不允许再次激活', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );
      await registry.activateAll();
      await registry.close();

      expect(registry.activateAll, throwsStateError);
    });

    test('单个插件 close 抛异常不阻断其余插件关闭', () async {
      final log = <String>[];
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'a', log: log),
          _FakePluginFactory(id: 'b', throwsOnClose: true, log: log),
        ],
      );
      await registry.activateAll();

      await registry.close();

      expect(registry.stateOf('a')!.status, ZetaPluginStatus.stopped);
      expect(log, contains('close:a'));
    });
  });

  group('ZetaPluginRegistry 关闭与激活的竞态', () {
    test('关闭期间到达的激活结果不会被登记，且立刻释放', () async {
      final plugin = _GatedPluginFactory(id: 'slow');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[plugin],
      );

      final activating = registry.activateAll();
      await Future<void>.delayed(Duration.zero);
      final closing = registry.close();
      plugin.release();
      await activating;
      await closing;

      expect(plugin.closedHandles, 1, reason: '迟到句柄必须就地释放，否则永远没人关它');
      expect(
        registry.stateOf('slow')!.status,
        ZetaPluginStatus.stopped,
        reason: '已关闭的 registry 不能把插件标成 active',
      );
      expect(registry.contributions<_FakeContribution>(), isEmpty);
    });

    test('close 会等待在途激活收尾，且不再启动后续插件', () async {
      final first = _GatedPluginFactory(id: 'first');
      final second = _GatedPluginFactory(id: 'second');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[first, second],
      );

      final activating = registry.activateAll();
      await Future<void>.delayed(Duration.zero);
      first.release();
      final closing = registry.close();
      second.release();
      await activating;
      await closing;

      // 第一个插件的激活在关闭之后才落地 → 就地释放，不登记。
      expect(first.closedHandles, 1);
      expect(registry.stateOf('first')!.status, ZetaPluginStatus.stopped);
      // 第二个插件在关闭后根本不该被启动：关闭中的 registry 不再拉新资源。
      expect(second.closedHandles, 0);
      expect(registry.stateOf('second')!.status, ZetaPluginStatus.registered);
      expect(registry.contributions<_FakeContribution>(), isEmpty);
    });

    test('并发 close 返回同一个任务，都等到句柄真正释放', () async {
      final plugin = _SlowClosingPluginFactory(id: 'slow');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[plugin],
      );
      registry.activateAllSynchronously();

      final first = registry.close();
      final second = registry.close();
      await second;

      expect(plugin.closedHandles, 1, reason: '第二个调用方拿到"已完成"时，句柄必须真的已经释放');
      await first;
      expect(plugin.closedHandles, 1);
    });

    test('关闭后不允许再次激活（同步入口同样）', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );
      await registry.close();

      expect(registry.activateAll, throwsStateError);
      expect(registry.activateAllSynchronously, throwsStateError);
    });
  });

  group('ZetaPluginRegistry 同步激活', () {
    test('同步入口立刻返回可用贡献，无需等待 microtask', () {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'second', dependsOn: <String>['first']),
          _FakePluginFactory(id: 'first'),
        ],
      );

      final report = registry.activateAllSynchronously();

      expect(report.activeIds, <String>['first', 'second']);
      expect(registry.contributions<_FakeContribution>(), hasLength(2));
    });

    test('只支持异步激活的插件 fail-closed，不被静默跳过', () {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_AsyncOnlyPluginFactory(id: 'async')],
      );

      final report = registry.activateAllSynchronously();

      expect(
        registry.stateOf('async')!.failureReason,
        ZetaPluginFailureReason.requiresSynchronousActivation,
      );
      expect(report.activeIds, isEmpty);
    });
  });

  group('ZetaPluginRegistry 贡献快照', () {
    test('贡献 getter 抛异常只拖垮该插件，且句柄立即释放', () async {
      final bad = _BadContributionPluginFactory(id: 'bad');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          bad,
          _FakePluginFactory(id: 'good'),
        ],
      );

      final report = await registry.activateAll();

      expect(
        registry.stateOf('bad')!.failureReason,
        ZetaPluginFailureReason.activationThrew,
      );
      expect(bad.closedHandles, 1, reason: '坏插件的句柄不能留在 registry 里');
      expect(report.activeIds, <String>['good']);
      // 关键：坏插件不能阻断整个 catalog——多次读取都不该抛异常。
      expect(registry.contributions<_FakeContribution>(), hasLength(1));
      expect(registry.contributions<_FakeContribution>(), hasLength(1));
    });

    test('贡献是激活时冻结的快照，之后不再回调插件 getter', () async {
      final plugin = _CountingContributionPluginFactory(id: 'counting');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[plugin],
      );
      await registry.activateAll();

      registry.contributions<_FakeContribution>();
      registry.contributions<_FakeContribution>();

      expect(
        plugin.contributionReads,
        1,
        reason: 'contributions() 必须是无副作用的纯读操作',
      );
    });
  });

  group('ZetaPluginRegistry 贡献与上下文', () {
    test('按类型汇总贡献，顺序与激活顺序一致', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'second', dependsOn: <String>['first']),
          _FakePluginFactory(id: 'first'),
        ],
      );
      await registry.activateAll();

      final contributions = registry.contributions<_FakeContribution>();

      expect(contributions.map((contribution) => contribution.owner), <String>[
        'first',
        'second',
      ]);
      expect(registry.stateOf('first')!.contributionKinds, <String>[
        'fake.contribution',
      ]);
      expect(
        () => contributions.add(_FakeContribution('x')),
        throwsA(anything),
      );
    });

    test('context 只暴露 descriptor、时钟与指标端口', () async {
      final metrics = InMemoryZetaMetricsPort();
      final factory = _FakePluginFactory(id: 'a');
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[factory],
        clock: fixedClock(DateTime.utc(2026, 8, 21)),
        metrics: metrics,
      );

      await registry.activateAll();

      expect(factory.receivedContext!.descriptor.id, 'a');
      expect(factory.receivedContext!.clock(), DateTime.utc(2026, 8, 21));
      expect(factory.receivedContext!.metrics, same(metrics));
    });
  });

  group('ZetaPluginRegistry 指标', () {
    test('激活、失败与关闭都记入白名单指标，且不含异常文本', () async {
      final metrics = InMemoryZetaMetricsPort();
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[
          _FakePluginFactory(id: 'ok'),
          _FakePluginFactory(id: 'broken', throwsOnActivate: true),
        ],
        metrics: metrics,
      );

      await registry.activateAll();
      expect(metrics.totalOf(ZetaMetric.pluginActivated), 1);
      expect(metrics.totalOf(ZetaMetric.pluginActivationFailed), 1);
      expect(metrics.lastValueOf(ZetaMetric.pluginActiveCount), 1);
      expect(metrics.lastValueOf(ZetaMetric.pluginActivationGeneration), 1);

      await registry.close();
      expect(metrics.totalOf(ZetaMetric.pluginClosed), 1);
      expect(metrics.lastValueOf(ZetaMetric.pluginActiveCount), 0);

      final text = metrics.snapshot().map((series) => '$series').join('\n');
      expect(text, isNot(contains('activation exploded')));
    });
  });
}

final class _FakeContribution extends ZetaPluginContribution {
  const _FakeContribution(this.owner);

  final String owner;

  @override
  String get contributionKind => 'fake.contribution';
}

/// 句柄关闭需要跨越一次 event loop，用来暴露"close 提前返回"。
final class _SlowClosingPluginFactory implements ZetaSynchronousPluginFactory {
  _SlowClosingPluginFactory({required String id})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  int closedHandles = 0;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) =>
      _SlowClosingHandle(this);
}

final class _SlowClosingHandle implements ZetaPluginHandle {
  _SlowClosingHandle(this.owner);

  final _SlowClosingPluginFactory owner;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _FakeContribution(owner.descriptor.id),
  ];

  @override
  Future<void> close() async {
    await Future<void>.delayed(Duration.zero);
    owner.closedHandles += 1;
  }
}

/// 贡献 getter 直接抛异常的坏插件。
final class _BadContributionPluginFactory implements ZetaPluginFactory {
  _BadContributionPluginFactory({required String id})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  int closedHandles = 0;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      _BadContributionHandle(this);
}

final class _BadContributionHandle implements ZetaPluginHandle {
  _BadContributionHandle(this.owner);

  final _BadContributionPluginFactory owner;

  @override
  List<ZetaPluginContribution> get contributions =>
      throw StateError('contributions exploded');

  @override
  Future<void> close() async => owner.closedHandles += 1;
}

/// 统计 `contributions` getter 被读了几次。
final class _CountingContributionPluginFactory implements ZetaPluginFactory {
  _CountingContributionPluginFactory({required String id})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  int contributionReads = 0;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      _CountingContributionHandle(this);
}

final class _CountingContributionHandle implements ZetaPluginHandle {
  _CountingContributionHandle(this.owner);

  final _CountingContributionPluginFactory owner;

  @override
  List<ZetaPluginContribution> get contributions {
    owner.contributionReads += 1;
    return <ZetaPluginContribution>[_FakeContribution(owner.descriptor.id)];
  }

  @override
  Future<void> close() async {}
}

/// 激活会一直挂起，直到测试显式 [release]，用来构造关闭/激活竞态。
final class _GatedPluginFactory implements ZetaPluginFactory {
  _GatedPluginFactory({required String id})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  final Completer<void> _gate = Completer<void>();
  int closedHandles = 0;

  void release() {
    if (!_gate.isCompleted) {
      _gate.complete();
    }
  }

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async {
    await _gate.future;
    return _GatedPluginHandle(this);
  }
}

final class _GatedPluginHandle implements ZetaPluginHandle {
  _GatedPluginHandle(this.owner);

  final _GatedPluginFactory owner;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _FakeContribution(owner.descriptor.id),
  ];

  @override
  Future<void> close() async => owner.closedHandles += 1;
}

final class _AsyncOnlyPluginFactory implements ZetaPluginFactory {
  _AsyncOnlyPluginFactory({required String id})
    : descriptor = ZetaPluginDescriptor(
        id: id,
        apiVersion: ZetaPluginApiVersion.current,
      );

  @override
  final ZetaPluginDescriptor descriptor;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async {
    return _FakePluginHandle(
      owner: descriptor.id,
      log: <String>[],
      throwsOnClose: false,
    );
  }
}

final class _FakePluginFactory implements ZetaSynchronousPluginFactory {
  _FakePluginFactory({
    required String id,
    List<String> dependsOn = const <String>[],
    ZetaPluginApiVersion apiVersion = ZetaPluginApiVersion.current,
    bool essential = false,
    this.throwsOnActivate = false,
    this.throwsOnClose = false,
    List<String>? log,
  }) : descriptor = ZetaPluginDescriptor(
         id: id,
         apiVersion: apiVersion,
         dependsOn: dependsOn,
         essential: essential,
       ),
       _log = log ?? <String>[];

  @override
  final ZetaPluginDescriptor descriptor;

  final bool throwsOnActivate;
  final bool throwsOnClose;
  final List<String> _log;

  ZetaPluginContext? receivedContext;

  @override
  Future<ZetaPluginHandle> activate(ZetaPluginContext context) async =>
      activateSynchronously(context);

  @override
  ZetaPluginHandle activateSynchronously(ZetaPluginContext context) {
    receivedContext = context;
    if (throwsOnActivate) {
      throw StateError('activation exploded');
    }
    _log.add('activate:${descriptor.id}');
    return _FakePluginHandle(
      owner: descriptor.id,
      log: _log,
      throwsOnClose: throwsOnClose,
    );
  }
}

final class _FakePluginHandle implements ZetaPluginHandle {
  _FakePluginHandle({
    required this.owner,
    required this.log,
    required this.throwsOnClose,
  });

  final String owner;
  final List<String> log;
  final bool throwsOnClose;

  @override
  List<ZetaPluginContribution> get contributions => <ZetaPluginContribution>[
    _FakeContribution(owner),
  ];

  @override
  Future<void> close() async {
    if (throwsOnClose) {
      throw StateError('close exploded');
    }
    log.add('close:$owner');
  }
}

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

    test('激活代数每次递增', () async {
      final registry = ZetaPluginRegistry(
        factories: <ZetaPluginFactory>[_FakePluginFactory(id: 'a')],
      );

      final first = await registry.activateAll();
      final second = await registry.activateAll();

      expect(first.generation, 1);
      expect(second.generation, 2);
      expect(registry.activationGeneration, 2);
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

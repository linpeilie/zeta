import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/features/agent/application/agent_provider_idle_reaper.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/ui/features/ide/view_models/active_agent_provider_controller.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';
import '../presentation/harness/agent_pane_test_harness.dart';

/// 04-目标态与步骤.md §S6：接上回收器。
///
/// - AC4：session scope 空闲达到 TTL（硬编码 10 分钟）被回收；再次发送自动
///   重建新实例并正常完成。
/// - AC5：pin 期间（turn 正在跑）推进任意时长都不回收——由 S5 的 pin 计数保证，
///   回收器只是照着读，不重新发明判据。
/// - AC7：global scope 永不参与回收，全局功能路径不受影响。
///
/// 第一组直接对着 registry + reaper 钉住扫描/回收决策本身（不经过 VM，隔离
/// 变量）；第二组用完整的 VM turn 生命周期钉住 AC4 端到端链路（回收 →
/// 下次 sendMessage 自动重建 → 新实例 → turn 正常完成）。
void main() {
  group('AgentProviderIdleReaper · 扫描与回收决策（S6）', () {
    test('达到 TTL 且未 pin 的 session scope 会被回收', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final lease = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      await lease.release();
      expect(harness.registry.debugProviderCount, 1);

      harness.reaper.start();
      harness.advanceClock(const Duration(minutes: 10));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.registry.debugProviderCount, 0);
    });

    test('未到 TTL 不回收', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final lease = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      await lease.release();

      harness.reaper.start();
      harness.advanceClock(const Duration(minutes: 9, seconds: 59));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.registry.debugProviderCount, 1);
    });

    test('AC5：pin 期间即使远超 TTL 也不回收', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final lease = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      final pin = lease.pin();
      await lease.release();

      harness.reaper.start();
      harness.advanceClock(const Duration(hours: 1));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.registry.debugProviderCount, 1, reason: 'pin 未释放，不该被回收');

      await pin.release();
      harness.fireTick();
      await harness.pumpAsync();
      expect(
        harness.registry.debugProviderCount,
        0,
        reason: 'pin 释放后下一次扫描应该回收',
      );
    });

    test('AC7：global scope 永不参与回收，即使远超 TTL 且未 pin', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final lease = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
      );
      await lease.release();

      harness.reaper.start();
      harness.advanceClock(const Duration(days: 1));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.registry.debugProviderCount, 1);
    });

    test('两个 session scope 各自独立：只回收空闲超过 TTL 的那个', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final leaseA = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      await leaseA.release();

      harness.advanceClock(const Duration(minutes: 5));

      final leaseB = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-b'),
      );
      await leaseB.release();

      harness.reaper.start();
      // entry-a 此刻空闲 11 分钟（超过 TTL），entry-b 只空闲 6 分钟（未到）。
      harness.advanceClock(const Duration(minutes: 6));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.remainingSessionScopeIds(), <String>['entry-b']);
    });

    test('start()/stop() 幂等；stop 之后扫描不再触发', () async {
      final harness = _ScanHarness();
      addTearDown(harness.dispose);

      final lease = await harness.registry.acquire(
        AgentProviderConfig.defaultCodex,
        scope: const AgentProviderRuntimeScopeKey.session('entry-a'),
      );
      await lease.release();

      harness.reaper.start();
      harness.reaper.start();
      expect(harness.timerFactory.cancelled, isFalse);
      expect(harness.timerFactory.lastDuration, const Duration(seconds: 60));

      harness.reaper.stop();
      expect(harness.timerFactory.cancelled, isTrue);
      // 重复 stop 是安全的空操作。
      harness.reaper.stop();

      harness.advanceClock(const Duration(minutes: 10));
      harness.fireTick();
      await harness.pumpAsync();

      // stop() 之后 Timer 已 cancel，fireTick 是空操作——即便空闲已经远超
      // TTL，registry 里的实例也不会被回收。
      expect(harness.registry.debugProviderCount, 1);
    });
  });

  group('AgentProviderIdleReaper · 端到端 turn 生命周期（AC4）', () {
    test('turn 完成后空闲达到 TTL 被回收；再次发送自动重建新实例并正常完成', () async {
      final harness = _TurnHarness();
      addTearDown(harness.dispose);

      await harness.viewModel.sendMessage('hello');
      harness.scheduler.drainFrames();
      harness.completeCurrentTurn();
      await harness.pumpAsync();

      expect(harness.factory.created, hasLength(1));
      expect(harness.registry.debugProviderCount, 1);

      harness.reaper.start();
      harness.advanceClock(const Duration(minutes: 10));
      harness.fireTick();
      await harness.pumpAsync();

      expect(harness.registry.debugProviderCount, 0, reason: '空闲达到 TTL，应该被回收');

      await harness.viewModel.sendMessage('again');
      harness.scheduler.drainFrames();
      harness.completeCurrentTurn();
      await harness.pumpAsync();

      expect(harness.factory.created, hasLength(2));
      expect(
        identical(harness.factory.created[0], harness.factory.created[1]),
        isFalse,
        reason: '回收后再次发送应该拿到一个全新的 provider 实例',
      );
      expect(
        harness.viewModel.messages.map((message) => message.text),
        containsAllInOrder(<String>['hello', 'again']),
      );
    });
  });
}

/// 只测扫描/回收决策本身，不经过 VM。
final class _ScanHarness {
  _ScanHarness() {
    registry = AgentProviderRuntimeRegistry(
      providerFactory: factory,
      clock: () => _now,
      timerFactory: timerFactory.call,
    );
    reaper = AgentProviderIdleReaper(registry: registry);
  }

  DateTime _now = DateTime(2026, 8, 8, 9);
  final _MultiInstanceProviderFactory factory = _MultiInstanceProviderFactory();
  final _FakePeriodicTimerFactory timerFactory = _FakePeriodicTimerFactory();
  late final AgentProviderRuntimeRegistry registry;
  late final AgentProviderIdleReaper reaper;

  void advanceClock(Duration duration) => _now = _now.add(duration);

  void fireTick() => timerFactory.fire();

  /// `_sweep` 对每个候选 `await invalidateScope`；多跑几个 microtask 循环，
  /// 确保 dispose 链路落定后再断言。
  Future<void> pumpAsync() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
  }

  List<String> remainingSessionScopeIds() {
    final ids =
        registry
            .snapshotEntries()
            .map((entry) => entry.scope)
            .whereType<AgentProviderRuntimeSessionScope>()
            .map((scope) => scope.id)
            .toList()
          ..sort();
    return ids;
  }

  Future<void> dispose() async {
    reaper.stop();
    await registry.close();
  }
}

/// 端到端钉住 AC4：完整的 VM turn 生命周期 + 回收器协作。
final class _TurnHarness {
  _TurnHarness() {
    registry = AgentProviderRuntimeRegistry(
      providerFactory: factory,
      clock: () => _now,
      timerFactory: timerFactory.call,
    );
    controller = ActiveAgentProviderController(
      configStore: MemoryAgentProviderConfigStore(),
      runtimeRegistry: registry,
      scope: const AgentProviderRuntimeScopeKey.session('entry-1'),
    );
    viewModel = AgentConversationViewModel(
      providerController: controller,
      uiFrameScheduler: scheduler,
    )..updateWorkspace(projectPath: '/repo', contextFilePath: null);
    reaper = AgentProviderIdleReaper(registry: registry);
  }

  DateTime _now = DateTime(2026, 8, 8, 9);
  final _MultiInstanceProviderFactory factory = _MultiInstanceProviderFactory();
  final _FakePeriodicTimerFactory timerFactory = _FakePeriodicTimerFactory();
  final FakeAgentFrameScheduler scheduler = FakeAgentFrameScheduler();
  late final AgentProviderRuntimeRegistry registry;
  late final ActiveAgentProviderController controller;
  late final AgentConversationViewModel viewModel;
  late final AgentProviderIdleReaper reaper;

  void advanceClock(Duration duration) => _now = _now.add(duration);

  void fireTick() => timerFactory.fire();

  void completeCurrentTurn() {
    factory.created.last.emitEvent(
      const AgentTurnCompletedEvent(sessionId: 'session-1', turnId: 'turn-1'),
    );
  }

  Future<void> pumpAsync() async {
    for (var i = 0; i < 5; i++) {
      await Future<void>.delayed(Duration.zero);
    }
    scheduler.drainFrames();
  }

  Future<void> dispose() async {
    reaper.stop();
    viewModel.dispose();
    controller.dispose();
    await registry.close();
  }
}

/// 周期定时器工厂替身：不真的等待，测试手动 [fire] 驱动一次扫描。
final class _FakePeriodicTimerFactory {
  void Function(Timer timer)? _callback;
  bool cancelled = false;
  Duration? lastDuration;

  Timer call(Duration duration, void Function(Timer timer) callback) {
    lastDuration = duration;
    cancelled = false;
    _callback = callback;
    return _FakeTimer(this);
  }

  /// 和真实 [Timer.periodic] 一样：`cancel()` 之后不会再触发回调。
  void fire() {
    if (cancelled) {
      return;
    }
    _callback?.call(_FakeTimer(this));
  }
}

final class _FakeTimer implements Timer {
  _FakeTimer(this._factory);

  final _FakePeriodicTimerFactory _factory;

  @override
  void cancel() => _factory.cancelled = true;

  @override
  bool get isActive => !_factory.cancelled;

  @override
  int get tick => 0;
}

/// 与 [AgentPaneFakeProviderFactory] 不同：每次 create 返回**新**实例，用于
/// 证明回收后重建拿到的是可区分的对象（对齐
/// agent_thread_workspace_controller_test.dart 里同名类的写法）。
final class _MultiInstanceProviderFactory implements AgentProviderFactory {
  final List<AgentPaneFakeProvider> created = <AgentPaneFakeProvider>[];

  @override
  AgentProvider create(AgentProviderConfig config) {
    final provider = AgentPaneFakeProvider();
    created.add(provider);
    return provider;
  }
}

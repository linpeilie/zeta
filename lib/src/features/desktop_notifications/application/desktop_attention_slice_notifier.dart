import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_intent.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_reducer.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// Desktop Attention effect 的执行端口。
///
/// 实现住在 `app` 组合层（它要碰系统通知中心、任务栏指示器与设置订阅），切片本身
/// 只描述要做什么。
abstract interface class DesktopAttentionSliceEffectRunner {
  /// 装配运行期订阅。
  ///
  /// 读一次通知设置并订阅其变化、初始化系统通知中心，然后把初始设置与冷启动带
  /// 进来的通知 payload 回流给 notifier。**不在 `build()` 里做**：它要等调用方
  /// 先把 target activator 绑上，否则冷启动那条激活会找不到落点。
  Future<void> initialize();

  Future<void> run(DesktopAttentionSliceEffect effect);

  /// 释放 runner 独占的资源（设置订阅、通知服务句柄）。
  void close();
}

/// runner 工厂：拿到 notifier 本身，因此 runner 能直接回流结果。
///
/// 用工厂而不是「runner provider + 反向 `ref.read` notifier」：后者会被 Riverpod
/// 判定成 `CircularDependencyError`（工程规范 §3.0）。
typedef DesktopAttentionSliceEffectRunnerFactory =
    DesktopAttentionSliceEffectRunner Function(
      DesktopAttentionSliceNotifier notifier,
    );

/// 组合根必须覆盖的 effect runner 工厂。
///
/// fail-closed：没被覆盖就抛错，而不是静默退化成一个什么都不做的 runner——那会让
/// 「通知没发出去」变成一个没人发现的哑 failure。
final desktopAttentionSliceEffectRunnerFactoryProvider =
    Provider<DesktopAttentionSliceEffectRunnerFactory>(
      (ref) => throw StateError(
        'desktopAttentionSliceEffectRunnerFactoryProvider was read before the '
        'composition root overrode it',
      ),
      name: 'desktopAttentionSliceEffectRunnerFactory',
    );

/// Desktop Attention 的唯一状态 owner。
///
/// **不是 autoDispose。** 未读提醒与系统通知的生命周期跟 app session 走，不能由
/// 「当前有没有 Widget 在看」决定（工程规范 §3.0）。
final desktopAttentionSliceProvider =
    NotifierProvider<DesktopAttentionSliceNotifier, DesktopAttentionSliceState>(
      DesktopAttentionSliceNotifier.new,
      name: 'desktopAttentionSlice',
    );

final class DesktopAttentionSliceNotifier
    extends Notifier<DesktopAttentionSliceState> {
  late DesktopAttentionSliceEffectRunner _effectRunner;

  /// 已提交的切片状态：这是唯一 owner，[state] 只是它的广播通道。
  ///
  /// 两者分开的理由和 IDE Session 那份一样：runner 会在 `run(effect)` 里回流结果
  /// 形成嵌套 dispatch（中间态不该广播），而可见性变化由 `IdeHome` 在 Widget 生命
  /// 周期回调里推进——那时向 Riverpod 写 state 会撞上 "Tried to modify a provider
  /// while the widget tree was building"。因此归约结果先落在这里，广播排到
  /// microtask；命令入口的调用方读 [state] 永远拿到已提交值。
  late DesktopAttentionSliceState _working;

  bool _closed = false;
  bool _publishScheduled = false;

  @override
  DesktopAttentionSliceState build() {
    // 工厂由组合根一次性覆盖，容器存活期内不再变化。
    _effectRunner = ref.watch(desktopAttentionSliceEffectRunnerFactoryProvider)(
      this,
    );
    _working = DesktopAttentionSliceState();
    ref.onDispose(_handleDispose);
    return _working;
  }

  @override
  DesktopAttentionSliceState get state => _working;

  int get unreadCount => _working.unreadCount;

  bool get isClosed => _closed;

  /// 装配运行期订阅；调用方必须先绑好 target activator。
  Future<void> initialize() => _effectRunner.initialize();

  Future<void> dispatch(DesktopAttentionSliceIntent intent) async {
    if (_closed) {
      return;
    }
    final before = _working;
    final transition = desktopAttentionSliceReduce(before, intent);
    if (!identical(transition.state, before) && transition.state != before) {
      _working = transition.state;
      _schedulePublish();
    }
    for (final effect in transition.effects) {
      if (_closed) {
        return;
      }
      await _effectRunner.run(effect);
    }
  }

  Future<void> initialized(AgentNotificationSettings settings) =>
      dispatch(DesktopAttentionInitialized(settings));

  Future<void> settingsChanged(AgentNotificationSettings settings) =>
      dispatch(DesktopAttentionSettingsChanged(settings));

  Future<void> updateVisibility(DesktopAttentionVisibility visibility) =>
      dispatch(DesktopAttentionVisibilityChanged(visibility));

  Future<void> handleAttention(AgentWorkspaceAttention attention) =>
      dispatch(DesktopAttentionReceived(attention));

  Future<void> markThreadRead(String providerId, String threadId) =>
      dispatch(DesktopAttentionThreadRead(providerId, threadId));

  Future<void> removeIdentity(String identity) =>
      dispatch(DesktopAttentionIdentityRemoved(identity));

  Future<void> handleActivation(String? payload) {
    final normalized = payload?.trim();
    if (normalized == null || normalized.isEmpty) {
      return Future<void>.value();
    }
    return dispatch(DesktopAttentionNotificationActivated(normalized));
  }

  void _handleDispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _effectRunner.close();
  }

  /// 把已提交状态广播给 Riverpod，同一 microtask 内的多次提交合并成一次。
  void _schedulePublish() {
    if (_publishScheduled || _closed) {
      return;
    }
    _publishScheduled = true;
    scheduleMicrotask(() {
      _publishScheduled = false;
      if (_closed) {
        return;
      }
      state = _working;
    });
  }
}

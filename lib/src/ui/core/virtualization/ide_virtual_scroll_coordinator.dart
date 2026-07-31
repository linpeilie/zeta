/// 虚拟列表滚动意图状态机（followEnd / free）。
///
/// 通用层实现，不依赖 Agent feature。layout correction 与 programmatic
/// reveal 不得改变用户模式；流式 follow 使用 frame-coalesced 无动画 reveal。
library;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

/// 用户可见的滚动意图模式。
enum IdeVirtualScrollMode {
  /// 保持视口贴齐列表末尾（流式输出跟随）。
  followEnd,

  /// 用户自由浏览；流式更新不得抢回底部。
  free,
}

/// 滚动条 / 视口当前 metrics 的只读快照。
@immutable
final class IdeVirtualScrollMetricsSnapshot {
  /// 创建 metrics 快照。
  const IdeVirtualScrollMetricsSnapshot({
    required this.pixels,
    required this.maxScrollExtent,
    required this.viewportDimension,
  });

  /// 当前滚动位置。
  final double pixels;

  /// 最大可滚动范围。
  final double maxScrollExtent;

  /// 视口主轴尺寸。
  final double viewportDimension;

  /// 距底部的距离：`maxScrollExtent - pixels`。
  double get endDistance {
    final distance = maxScrollExtent - pixels;
    if (distance.isNaN || distance.isInfinite) {
      return 0;
    }
    return distance < 0 ? 0 : distance;
  }

  /// 是否在 [threshold] 内视为贴底。
  bool isWithinEnd(double threshold) => endDistance <= threshold;
}

/// 实际执行 jump / animate / cancel 的驱动抽象，便于单元测试注入 fake。
abstract interface class IdeVirtualScrollDriver {
  /// 是否已挂载可滚动位置。
  bool get hasClients;

  /// 当前 pixels；无 client 时为 0。
  double get pixels;

  /// 当前 maxScrollExtent；无 client 时为 0。
  double get maxScrollExtent;

  /// 无动画跳到 [offset]。
  void jumpTo(double offset);

  /// 动画滚动到 [offset]。
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  });

  /// 取消进行中的显式动画。
  void cancelAnimation();
}

/// Flutter [ScrollController] 适配。
final class IdeScrollControllerDriver implements IdeVirtualScrollDriver {
  /// 创建适配器。
  IdeScrollControllerDriver(this.controller);

  /// 底层 controller。
  final ScrollController controller;

  @override
  bool get hasClients => controller.hasClients;

  @override
  double get pixels => hasClients ? controller.position.pixels : 0;

  @override
  double get maxScrollExtent =>
      hasClients ? controller.position.maxScrollExtent : 0;

  @override
  void jumpTo(double offset) {
    if (!hasClients) {
      return;
    }
    final target = offset.clamp(0.0, controller.position.maxScrollExtent);
    controller.jumpTo(target);
  }

  @override
  Future<void> animateTo(
    double offset, {
    required Duration duration,
    required Curve curve,
  }) async {
    if (!hasClients) {
      return;
    }
    final target = offset.clamp(0.0, controller.position.maxScrollExtent);
    await controller.animateTo(target, duration: duration, curve: curve);
  }

  @override
  void cancelAnimation() {
    if (!hasClients) {
      return;
    }
    // 以当前 pixels jump 打断 animateTo。
    final position = controller.position;
    position.jumpTo(position.pixels);
  }
}

/// 用户离底部超过该值则退出 followEnd（logical px）。
const double kIdeExitFollowEndThreshold = 48;

/// 用户滚回底部该范围内则重新进入 followEnd（logical px）。
const double kIdeEnterFollowEndThreshold = 8;

/// follow end settled 判定：连续帧 end distance 上限（logical px）。
const double kIdeFollowEndSettledEpsilon = 1;

/// 显式“滚到底部”按钮默认动画时长。
const Duration kIdeScrollToEndAnimationDuration = Duration(milliseconds: 180);

/// 虚拟列表滚动意图协调器。
///
/// - 初始 [IdeVirtualScrollMode.followEnd]
/// - 仅用户来源滚动可切换 free/follow
/// - correction / programmatic reveal 不改模式
/// - follow 下流式 tick 合并到同一帧一次 reveal
final class IdeVirtualScrollCoordinator {
  /// 创建协调器。
  ///
  /// [scheduleFrame] 默认使用 [SchedulerBinding.addPostFrameCallback]；
  /// 测试可注入同步/可控调度器。
  IdeVirtualScrollCoordinator({
    IdeVirtualScrollDriver? driver,
    void Function(VoidCallback callback)? scheduleFrame,
    this.exitFollowEndThreshold = kIdeExitFollowEndThreshold,
    this.enterFollowEndThreshold = kIdeEnterFollowEndThreshold,
    this.settledEpsilon = kIdeFollowEndSettledEpsilon,
    this.explicitAnimationDuration = kIdeScrollToEndAnimationDuration,
    this.explicitAnimationCurve = Curves.easeOut,
  }) : _scheduleFrame =
           scheduleFrame ??
           ((callback) {
             SchedulerBinding.instance.addPostFrameCallback((_) => callback());
           }) {
    if (driver != null) {
      attachDriver(driver);
    }
  }

  final void Function(VoidCallback callback) _scheduleFrame;

  /// 退出 follow 的 end-distance 阈值。
  final double exitFollowEndThreshold;

  /// 进入 follow 的 end-distance 阈值。
  final double enterFollowEndThreshold;

  /// settled 判定 epsilon。
  final double settledEpsilon;

  /// 显式滚到底部动画时长。
  final Duration explicitAnimationDuration;

  /// 显式滚到底部动画曲线。
  final Curve explicitAnimationCurve;

  IdeVirtualScrollDriver? _driver;
  IdeVirtualScrollMode _mode = IdeVirtualScrollMode.followEnd;
  int _programmaticDepth = 0;
  bool _pendingFollowEnd = false;
  bool _followEndScheduled = false;
  bool _explicitAnimating = false;
  int _settledFrameCount = 0;
  String? _lastItemId;
  int _revealCount = 0;
  int _coalescedFollowEndRequestCount = 0;

  /// 模式变化时回调（测试与 UI 可选监听）；不在 layout 同步路径强制调用。
  VoidCallback? onModeChanged;

  /// 当前模式。
  IdeVirtualScrollMode get mode => _mode;

  /// 是否处于 programmatic 抑制区间。
  bool get isProgrammatic => _programmaticDepth > 0;

  /// 是否有待执行的 follow-end reveal。
  bool get pendingFollowEnd => _pendingFollowEnd;

  /// 是否正在执行用户点击触发的显式动画。
  bool get isExplicitAnimating => _explicitAnimating;

  /// 最近一次 reveal 使用的 last item ID。
  String? get lastItemId => _lastItemId;

  /// 已执行的 reveal 次数（含 jump 与 animate 完成）。
  int get revealCount => _revealCount;

  /// 自上次 reveal 调度以来合并的内容变化请求数（诊断）。
  int get coalescedFollowEndRequestCount => _coalescedFollowEndRequestCount;

  /// free 且离底部超过 exit 阈值时显示“滚到底部”按钮。
  bool shouldShowScrollToEndButton(IdeVirtualScrollMetricsSnapshot metrics) {
    return _mode == IdeVirtualScrollMode.free &&
        metrics.endDistance > exitFollowEndThreshold;
  }

  /// 绑定或更换 scroll driver。
  void attachDriver(IdeVirtualScrollDriver? driver) {
    _driver = driver;
  }

  /// 开始程序化滚动（reveal / jump）；期间 metrics 变化不改模式。
  void beginProgrammaticScroll() {
    _programmaticDepth += 1;
  }

  /// 结束程序化滚动。
  void endProgrammaticScroll() {
    if (_programmaticDepth > 0) {
      _programmaticDepth -= 1;
    }
  }

  /// 布局锚点 correction 回调：明确不改变模式。
  void onAnchorCorrection() {
    // correction 不是用户意图；保持当前 mode。
  }

  /// 程序化 reveal 过程中的 metrics 变化：不改变模式。
  void onProgrammaticReveal() {
    // 同 beginProgrammaticScroll 语义的便捷入口，保留 API 对称性。
  }

  /// 用户滚动后根据 end distance 更新模式。
  ///
  /// 必须在确认来源为用户输入后调用。
  /// 用户输入始终取消显式“滚到底部”动画；其余 programmatic
  ///（如 streaming jump）期间忽略模式切换。
  void onUserScroll(IdeVirtualScrollMetricsSnapshot metrics) {
    // 先取消显式动画（即使仍在 programmatic 包装内）。
    if (_explicitAnimating) {
      cancelExplicitAnimation();
    }
    if (isProgrammatic) {
      return;
    }

    final endDistance = metrics.endDistance;
    if (_mode == IdeVirtualScrollMode.followEnd &&
        endDistance > exitFollowEndThreshold) {
      _setMode(IdeVirtualScrollMode.free);
      _pendingFollowEnd = false;
      _settledFrameCount = 0;
      return;
    }
    if (_mode == IdeVirtualScrollMode.free &&
        endDistance <= enterFollowEndThreshold) {
      _setMode(IdeVirtualScrollMode.followEnd);
      _settledFrameCount = 0;
    }
  }

  /// 通知协调器内容变化可能移动底部（如 streaming 合并发布）。
  ///
  /// free：忽略。followEnd：合并到本帧一次 reveal。
  void notifyContentChanged({String? lastItemId}) {
    if (lastItemId != null) {
      _lastItemId = lastItemId;
    }
    if (_mode != IdeVirtualScrollMode.followEnd) {
      return;
    }
    _pendingFollowEnd = true;
    _coalescedFollowEndRequestCount += 1;
    _scheduleCoalescedReveal();
  }

  /// 用户点击“滚到底部”：进入 followEnd，并可用短动画 reveal。
  Future<void> requestFollowEnd({
    String? lastItemId,
    bool animated = true,
  }) async {
    if (lastItemId != null) {
      _lastItemId = lastItemId;
    }
    _setMode(IdeVirtualScrollMode.followEnd);
    _pendingFollowEnd = false;
    _settledFrameCount = 0;
    await _revealEnd(animated: animated, explicit: animated);
  }

  /// 取消用户触发的显式动画，并保持当前 mode。
  void cancelExplicitAnimation() {
    if (!_explicitAnimating) {
      return;
    }
    _explicitAnimating = false;
    _driver?.cancelAnimation();
  }

  /// 在 mutation 后更新 last item ID；若处于 followEnd 则排队 reveal。
  void updateLastItemId(String? lastItemId, {bool revealIfFollowing = true}) {
    _lastItemId = lastItemId;
    if (revealIfFollowing && _mode == IdeVirtualScrollMode.followEnd) {
      _pendingFollowEnd = true;
      _scheduleCoalescedReveal();
    }
  }

  /// 报告一帧 layout 后的 end distance，用于 settled 计数。
  void onFrameSettled(IdeVirtualScrollMetricsSnapshot metrics) {
    if (_mode != IdeVirtualScrollMode.followEnd) {
      _settledFrameCount = 0;
      return;
    }
    if (metrics.endDistance <= settledEpsilon) {
      _settledFrameCount += 1;
    } else {
      _settledFrameCount = 0;
      _pendingFollowEnd = true;
      _scheduleCoalescedReveal();
    }
  }

  /// 是否已连续两帧贴底。
  bool get isFollowEndSettled =>
      _mode == IdeVirtualScrollMode.followEnd && _settledFrameCount >= 2;

  void _scheduleCoalescedReveal() {
    if (_followEndScheduled) {
      return;
    }
    _followEndScheduled = true;
    _scheduleFrame(() {
      _followEndScheduled = false;
      if (!_pendingFollowEnd || _mode != IdeVirtualScrollMode.followEnd) {
        return;
      }
      _pendingFollowEnd = false;
      _coalescedFollowEndRequestCount = 0;
      // 流式 follow 强制无动画，避免连续请求与显式动画互相覆盖。
      _unawaited(_revealEnd(animated: false, explicit: false));
    });
  }

  Future<void> _revealEnd({
    required bool animated,
    required bool explicit,
  }) async {
    final driver = _driver;
    if (driver == null || !driver.hasClients) {
      // 无 client 时仍计数，便于测试验证 coalesce 后会触发 reveal 意图。
      _revealCount += 1;
      return;
    }

    beginProgrammaticScroll();
    try {
      final target = driver.maxScrollExtent;
      if (animated && explicit) {
        _explicitAnimating = true;
        try {
          await driver.animateTo(
            target,
            duration: explicitAnimationDuration,
            curve: explicitAnimationCurve,
          );
        } finally {
          _explicitAnimating = false;
        }
      } else {
        driver.jumpTo(target);
      }
      _revealCount += 1;
    } finally {
      endProgrammaticScroll();
    }
  }

  void _setMode(IdeVirtualScrollMode next) {
    if (_mode == next) {
      return;
    }
    _mode = next;
    onModeChanged?.call();
  }
}

void _unawaited(Future<void> future) {
  future.then((_) {}, onError: (_) {});
}

import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/widgets.dart';

import '../ide_motion.dart';

/// 为桌面 pointer scroll 提供目标累加动画的 [ScrollController]。
///
/// 触控拖拽仍由 Flutter 原生 drag activity 处理；只有鼠标滚轮、触控板滚动等
/// 进入 [ScrollPosition.pointerScroll] 的离散增量会被平滑。连续输入始终基于
/// 上一次目标累加，避免反复从当前像素计算而丢失滚动距离。
final class IdeSmoothScrollController extends ScrollController {
  /// 创建平滑滚动控制器。
  IdeSmoothScrollController({
    super.initialScrollOffset,
    super.keepScrollOffset,
    super.debugLabel,
    this.pointerScrollDuration = IdeMotion.durationFast,
    this.pointerScrollCurve = IdeMotion.curveScroll,
    this.smoothScrollingEnabled = false,
  });

  /// 单次 pointer scroll 的过渡时长。
  final Duration pointerScrollDuration;

  /// pointer scroll 使用的缓动。
  final Curve pointerScrollCurve;

  /// 是否启用平滑滚动；系统要求减少动态效果时应设为 false。
  bool smoothScrollingEnabled;

  @override
  ScrollPosition createScrollPosition(
    ScrollPhysics physics,
    ScrollContext context,
    ScrollPosition? oldPosition,
  ) {
    return _IdeSmoothScrollPosition(
      physics: physics,
      context: context,
      initialPixels: initialScrollOffset,
      keepScrollOffset: keepScrollOffset,
      oldPosition: oldPosition,
      debugLabel: debugLabel,
      duration: pointerScrollDuration,
      curve: pointerScrollCurve,
      enabled: () => smoothScrollingEnabled,
    );
  }
}

final class _IdeSmoothScrollPosition extends ScrollPositionWithSingleContext {
  _IdeSmoothScrollPosition({
    required super.physics,
    required super.context,
    required this.duration,
    required this.curve,
    required this._enabled,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  final Duration duration;
  final Curve curve;
  final bool Function() _enabled;

  double? _pointerTargetPixels;
  int _animationGeneration = 0;

  @override
  void pointerScroll(double delta) {
    final tickerModeEnabled = TickerMode.getValuesNotifier(
      context.storageContext,
    ).value.enabled;
    if (!_enabled() || !tickerModeEnabled || duration == Duration.zero) {
      _resetPointerAnimationTarget();
      // 全局/页面级 ticker 暂停时 driven activity 不会推进；回退到 Flutter
      // 原生即时滚动，避免滚轮失效而 scrollbar 拖拽仍可用的不一致状态。
      super.pointerScroll(delta);
      return;
    }
    if (delta == 0) {
      return;
    }

    final base = _pointerTargetPixels ?? pixels;
    final target = math.min(
      math.max(base + delta, minScrollExtent),
      maxScrollExtent,
    );
    if (target == pixels && target == base) {
      goBallistic(0);
      return;
    }

    _pointerTargetPixels = target;
    final generation = ++_animationGeneration;

    // 先结束上一条 driven activity，使每次 pointer 输入都产生明确的用户方向
    // 通知；新的动画从当前像素继续追赶累计目标。
    goIdle();
    updateUserScrollDirection(
      -delta > 0 ? ScrollDirection.forward : ScrollDirection.reverse,
    );
    unawaited(
      animateTo(target, duration: duration, curve: curve).whenComplete(() {
        if (_animationGeneration == generation) {
          _pointerTargetPixels = null;
        }
      }),
    );
  }

  @override
  void applyUserOffset(double delta) {
    _resetPointerAnimationTarget();
    super.applyUserOffset(delta);
  }

  @override
  void jumpTo(double value) {
    _resetPointerAnimationTarget();
    super.jumpTo(value);
  }

  @override
  void correctBy(double correction) {
    final target = _pointerTargetPixels;
    if (target != null) {
      _pointerTargetPixels = target + correction;
    }
    super.correctBy(correction);
  }

  void _resetPointerAnimationTarget() {
    _animationGeneration += 1;
    _pointerTargetPixels = null;
  }
}

import 'package:flutter/widgets.dart';

import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';

/// 呼吸感骨架骨块：用于冷加载占位，替代不定进度条。
///
/// 脉冲周期取 [IdeMotion.durationLoadingPulse]；系统开启「减少动态效果」时
/// 停在固定半透明态，避免持续动画。高频重绘限制在 [RepaintBoundary] 内。
class IdeSkeletonBone extends StatefulWidget {
  const IdeSkeletonBone({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = IdeRadius.allSmall,
    this.semanticsLabel,
  });

  /// 骨块宽度；`null` 时在横轴上尽量撑满父约束。
  final double? width;

  /// 骨块高度。
  final double height;

  /// 圆角，默认 [IdeRadius.allSmall]。
  final BorderRadius borderRadius;

  /// 可选语义标签（例如「正在加载」）；多数占位块可留空，由外层统一标注。
  final String? semanticsLabel;

  @override
  State<IdeSkeletonBone> createState() => _IdeSkeletonBoneState();
}

class _IdeSkeletonBoneState extends State<IdeSkeletonBone>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: IdeMotion.durationLoadingPulse,
      value: 1,
    );
    _opacity = Tween<double>(begin: 0.45, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: IdeMotion.curveDefault),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncAnimation();
  }

  void _syncAnimation() {
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 0.72;
      return;
    }
    if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: colors.hoverSurface,
        borderRadius: widget.borderRadius,
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );
    // 减少动态效果时用静态透明度，与 IdeTabs loading 一致。
    final bone = _reduceMotion
        ? Opacity(opacity: 0.72, child: box)
        : FadeTransition(opacity: _opacity, child: box);

    Widget child = RepaintBoundary(child: bone);
    if (widget.width == null) {
      child = SizedBox(width: double.infinity, child: child);
    }
    final label = widget.semanticsLabel;
    if (label != null) {
      return Semantics(label: label, child: child);
    }
    return child;
  }
}

/// 单行骨架线，默认高度贴近 caption / body 行。
class IdeSkeletonLine extends StatelessWidget {
  const IdeSkeletonLine({
    super.key,
    this.width,
    this.height = 12,
    this.borderRadius = IdeRadius.allSmall,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return IdeSkeletonBone(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

/// 块级骨架，用于卡片、图表区等较大占位。
class IdeSkeletonBlock extends StatelessWidget {
  const IdeSkeletonBlock({
    super.key,
    this.width,
    this.height = 80,
    this.borderRadius = IdeRadius.allMedium,
  });

  final double? width;
  final double height;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    return IdeSkeletonBone(
      width: width,
      height: height,
      borderRadius: borderRadius,
    );
  }
}

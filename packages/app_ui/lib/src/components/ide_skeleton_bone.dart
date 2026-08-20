import 'package:app_ui/app_ui.dart';

/// A reduced-motion-aware pulsing skeleton placeholder.
class IdeSkeletonBone extends StatefulWidget {
  /// Creates a skeleton bone.
  const IdeSkeletonBone({
    this.width,
    this.height = 12,
    this.borderRadius,
    this.semanticsLabel,
    super.key,
  });

  /// Optional width; null expands to available width.
  final double? width;

  /// Bone height.
  final double height;

  /// Optional corner radius.
  final BorderRadius? borderRadius;

  /// Optional live-region loading announcement.
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
    _controller = AnimationController(vsync: this, value: 1);
    _opacity = Tween<double>(begin: 0.45, end: 1).animate(_controller);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _controller.duration = context.appMotion.loadingPulse;
    _reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (_reduceMotion) {
      _controller
        ..stop()
        ..value = 0.72;
    } else if (!_controller.isAnimating) {
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
    final box = DecoratedBox(
      decoration: BoxDecoration(
        color: context.appColors.surfaceElevated,
        borderRadius: widget.borderRadius ?? context.appRadii.allSmall,
      ),
      child: SizedBox(width: widget.width, height: widget.height),
    );
    final animated = _reduceMotion
        ? Opacity(opacity: 0.72, child: box)
        : FadeTransition(opacity: _opacity, child: box);
    Widget child = RepaintBoundary(child: animated);
    if (widget.width == null) {
      child = SizedBox(width: double.infinity, child: child);
    }
    return widget.semanticsLabel == null
        ? ExcludeSemantics(child: child)
        : Semantics(
            label: widget.semanticsLabel,
            liveRegion: true,
            child: child,
          );
  }
}

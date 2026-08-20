import 'package:app_ui/app_ui.dart';

/// A caller-supplied short label with an optional reduced-motion-aware pulse.
class IdePulsingLabel extends StatefulWidget {
  /// Creates a pulsing label.
  const IdePulsingLabel({
    required this.label,
    required this.active,
    super.key,
  });

  /// Visible caller-supplied copy.
  final String label;

  /// Whether the loading pulse is active.
  final bool active;

  @override
  State<IdePulsingLabel> createState() => _IdePulsingLabelState();
}

class _IdePulsingLabelState extends State<IdePulsingLabel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  bool _reduceMotion = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const AppMotion().loadingPulse,
      value: 1,
    );
    _opacity = Tween<double>(begin: 0.55, end: 1).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const AppMotion().defaultCurve,
      ),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _syncAnimation();
  }

  @override
  void didUpdateWidget(covariant IdePulsingLabel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.active != widget.active) _syncAnimation();
  }

  void _syncAnimation() {
    if (widget.active && !_reduceMotion) {
      _controller.repeat(reverse: true);
      return;
    }
    _controller
      ..stop()
      ..value = 1;
  }

  @override
  Widget build(BuildContext context) {
    final label = Text(
      widget.label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
    if (!widget.active) return label;
    if (_reduceMotion) {
      return Opacity(
        key: const ValueKey<String>('ide-tab-loading-reduced-motion'),
        opacity: 0.72,
        child: label,
      );
    }
    return FadeTransition(
      key: const ValueKey<String>('ide-tab-loading'),
      opacity: _opacity,
      child: label,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }
}

import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';

/// A focusable non-Material surface for complex desktop row content.
class PaneInteractiveSurface extends StatefulWidget {
  /// Creates an interactive surface.
  const PaneInteractiveSurface({
    required this.child,
    this.onPressed,
    this.padding,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.expandToConstraints = true,
    this.borderRadius,
    this.backgroundColor,
    this.hoverBackgroundColor,
    this.pressedBackgroundColor,
    this.selectedBackgroundColor,
    this.selectedHoverBackgroundColor,
    this.borderColor,
    this.focusBorderColor,
    this.selectedBorderColor,
    this.selected = false,
    this.enabled = true,
    this.button = true,
    this.semanticLabel,
    this.focusNode,
    this.autofocus = false,
    this.onHoverChanged,
    this.onFocusChanged,
    super.key,
  });

  /// Surface content.
  final Widget child;

  /// Activation callback.
  final VoidCallback? onPressed;

  /// Content inset.
  final EdgeInsetsGeometry? padding;

  /// Optional width.
  final double? width;

  /// Optional height.
  final double? height;

  /// Content alignment.
  final AlignmentGeometry alignment;

  /// Whether alignment may expand to parent constraints.
  final bool expandToConstraints;

  /// Optional corner radius.
  final BorderRadiusGeometry? borderRadius;

  /// Resting surface color.
  final Color? backgroundColor;

  /// Hover surface color.
  final Color? hoverBackgroundColor;

  /// Pressed surface color.
  final Color? pressedBackgroundColor;

  /// Selected surface color.
  final Color? selectedBackgroundColor;

  /// Selected hover surface color.
  final Color? selectedHoverBackgroundColor;

  /// Resting border color.
  final Color? borderColor;

  /// Focus border color.
  final Color? focusBorderColor;

  /// Selected border color.
  final Color? selectedBorderColor;

  /// Whether the surface is selected.
  final bool selected;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Whether semantics expose a button role.
  final bool button;

  /// Optional accessible name.
  final String? semanticLabel;

  /// Optional externally owned focus node.
  final FocusNode? focusNode;

  /// Whether to request focus initially.
  final bool autofocus;

  /// Reports hover changes.
  final ValueChanged<bool>? onHoverChanged;

  /// Reports focus changes.
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<PaneInteractiveSurface> createState() => _PaneInteractiveSurfaceState();
}

class _PaneInteractiveSurfaceState extends State<PaneInteractiveSurface> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onPressed != null;

  void _activate() {
    if (_interactive) widget.onPressed?.call();
  }

  void _setHover(bool value) {
    if (_hovered == value) return;
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  void _setFocus(bool value) {
    if (_focused == value) return;
    setState(() => _focused = value);
    widget.onFocusChanged?.call(value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final radius = widget.borderRadius ?? context.appRadii.allSmall;
    final background = switch ((widget.selected, _hovered, _pressed)) {
      (_, _, true) => widget.pressedBackgroundColor ?? colors.pressedSurface,
      (true, true, false) =>
        widget.selectedHoverBackgroundColor ?? colors.selectedHoverSurface,
      (true, false, false) =>
        widget.selectedBackgroundColor ?? colors.selectedSurface,
      (false, true, false) =>
        widget.hoverBackgroundColor ?? colors.hoverSurface,
      _ => widget.backgroundColor ?? Colors.transparent,
    };
    final border = _focused
        ? widget.focusBorderColor ?? colors.focusRing
        : widget.selected
        ? widget.selectedBorderColor ?? colors.accent
        : widget.borderColor ?? Colors.transparent;
    final duration = context.appMotion.resolveFor(
      context,
      context.appMotion.normal,
    );
    final container = AnimatedContainer(
      duration: duration,
      curve: context.appMotion.defaultCurve,
      width: widget.width,
      height: widget.height,
      alignment: widget.expandToConstraints ? widget.alignment : null,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: background,
        borderRadius: radius,
        border: Border.all(color: border),
      ),
      child: widget.expandToConstraints
          ? widget.child
          : Align(
              alignment: widget.alignment,
              widthFactor: 1,
              heightFactor: 1,
              child: widget.child,
            ),
    );

    return Semantics(
      button: widget.button,
      enabled: _interactive,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        focusNode: widget.focusNode,
        autofocus: widget.autofocus,
        enabled: _interactive,
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : SystemMouseCursors.basic,
        onShowHoverHighlight: _setHover,
        onShowFocusHighlight: _setFocus,
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _activate();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _interactive ? _activate : null,
          onTapDown: _interactive ? (_) => _setPressed(true) : null,
          onTapUp: _interactive ? (_) => _setPressed(false) : null,
          onTapCancel: _interactive ? () => _setPressed(false) : null,
          child: container,
        ),
      ),
    );
  }
}

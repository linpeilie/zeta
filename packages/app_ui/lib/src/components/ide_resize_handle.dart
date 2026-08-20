import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';

/// Axis controlled by [IdeResizeHandle].
enum IdeResizeHandleAxis {
  /// Changes horizontal size through left/right movement.
  horizontal,

  /// Changes vertical size through up/down movement.
  vertical,
}

/// A pointer- and keyboard-operable pane resize separator.
class IdeResizeHandle extends StatefulWidget {
  /// Creates a resize handle.
  const IdeResizeHandle({
    required this.axis,
    required this.onDragUpdate,
    this.thickness,
    this.keyboardStep = 8,
    this.semanticLabel,
    this.onDragStart,
    this.onDragEnd,
    this.onDragCancel,
    super.key,
  });

  /// Resize axis.
  final IdeResizeHandleAxis axis;

  /// Pointer update callback.
  final GestureDragUpdateCallback onDragUpdate;

  /// Optional hit-area thickness.
  final double? thickness;

  /// Logical-pixel delta applied for each keyboard activation.
  final double keyboardStep;

  /// Optional accessible name.
  final String? semanticLabel;

  /// Pointer drag-start callback.
  final GestureDragStartCallback? onDragStart;

  /// Pointer drag-end callback.
  final GestureDragEndCallback? onDragEnd;

  /// Pointer cancellation callback.
  final GestureDragCancelCallback? onDragCancel;

  @override
  State<IdeResizeHandle> createState() => _IdeResizeHandleState();
}

class _IdeResizeHandleState extends State<IdeResizeHandle> {
  bool _hovered = false;

  bool get _horizontal => widget.axis == IdeResizeHandleAxis.horizontal;

  void _keyboardResize(double direction) {
    final delta = _horizontal
        ? Offset(widget.keyboardStep * direction, 0)
        : Offset(0, widget.keyboardStep * direction);
    widget.onDragUpdate(
      DragUpdateDetails(delta: delta, globalPosition: Offset.zero),
    );
  }

  @override
  Widget build(BuildContext context) {
    final thickness = widget.thickness ?? context.appSpacing.xs;
    final cursor = _horizontal
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;
    final decreaseKey = _horizontal
        ? LogicalKeyboardKey.arrowLeft
        : LogicalKeyboardKey.arrowUp;
    final increaseKey = _horizontal
        ? LogicalKeyboardKey.arrowRight
        : LogicalKeyboardKey.arrowDown;
    return Semantics(
      label: widget.semanticLabel,
      focusable: true,
      child: FocusableActionDetector(
        mouseCursor: cursor,
        shortcuts: <ShortcutActivator, Intent>{
          SingleActivator(decreaseKey): const _ResizeIntent(-1),
          SingleActivator(increaseKey): const _ResizeIntent(1),
        },
        actions: <Type, Action<Intent>>{
          _ResizeIntent: CallbackAction<_ResizeIntent>(
            onInvoke: (intent) {
              _keyboardResize(intent.direction);
              return null;
            },
          ),
        },
        child: MouseRegion(
          cursor: cursor,
          onEnter: (_) => setState(() => _hovered = true),
          onExit: (_) => setState(() => _hovered = false),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _horizontal ? widget.onDragStart : null,
            onHorizontalDragUpdate: _horizontal ? widget.onDragUpdate : null,
            onHorizontalDragEnd: _horizontal ? widget.onDragEnd : null,
            onHorizontalDragCancel: _horizontal ? widget.onDragCancel : null,
            onVerticalDragStart: _horizontal ? null : widget.onDragStart,
            onVerticalDragUpdate: _horizontal ? null : widget.onDragUpdate,
            onVerticalDragEnd: _horizontal ? null : widget.onDragEnd,
            onVerticalDragCancel: _horizontal ? null : widget.onDragCancel,
            child: SizedBox(
              width: _horizontal ? thickness : null,
              height: _horizontal ? null : thickness,
              child: ColoredBox(
                color: context.appColors.frame,
                child: Center(
                  child: AnimatedContainer(
                    duration: context.appMotion.resolveFor(
                      context,
                      context.appMotion.fast,
                    ),
                    curve: context.appMotion.defaultCurve,
                    width: _horizontal ? 2 : double.infinity,
                    height: _horizontal ? double.infinity : 2,
                    color: _hovered
                        ? context.appColors.accent.withValues(alpha: 0.7)
                        : Colors.transparent,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ResizeIntent extends Intent {
  const _ResizeIntent(this.direction);

  final double direction;
}

import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';

enum IdeResizeHandleAxis { horizontal, vertical }

/// 统一 IDE 分栏拖拽条。
class IdeResizeHandle extends StatefulWidget {
  const IdeResizeHandle({
    required this.axis,
    required this.onDragUpdate,
    super.key,
    this.thickness = IdeSpacing.space8,
    this.semanticLabel,
  });

  final IdeResizeHandleAxis axis;
  final GestureDragUpdateCallback onDragUpdate;
  final double thickness;
  final String? semanticLabel;

  @override
  State<IdeResizeHandle> createState() => _IdeResizeHandleState();
}

class _IdeResizeHandleState extends State<IdeResizeHandle> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() {
      _hovered = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final cursor = widget.axis == IdeResizeHandleAxis.horizontal
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;

    return Semantics(
      label: widget.semanticLabel,
      child: MouseRegion(
        cursor: cursor,
        onEnter: (_) => _setHovered(true),
        onExit: (_) => _setHovered(false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragUpdate: widget.axis == IdeResizeHandleAxis.horizontal
              ? widget.onDragUpdate
              : null,
          onVerticalDragUpdate: widget.axis == IdeResizeHandleAxis.vertical
              ? widget.onDragUpdate
              : null,
          child: SizedBox(
            width: widget.axis == IdeResizeHandleAxis.horizontal
                ? widget.thickness
                : null,
            height: widget.axis == IdeResizeHandleAxis.vertical
                ? widget.thickness
                : null,
            child: AnimatedContainer(
              duration: IdeMotion.fast,
              curve: IdeMotion.curveDefault,
              color: _hovered ? colors.borderSubtle : colors.frame,
            ),
          ),
        ),
      ),
    );
  }
}

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
    final isHorizontal = widget.axis == IdeResizeHandleAxis.horizontal;
    final cursor = isHorizontal
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
          onHorizontalDragUpdate: isHorizontal ? widget.onDragUpdate : null,
          onVerticalDragUpdate: !isHorizontal ? widget.onDragUpdate : null,
          child: SizedBox(
            width: isHorizontal ? widget.thickness : null,
            height: !isHorizontal ? widget.thickness : null,
            child: ColoredBox(
              color: colors.frame,
              // hover 时在命中区中央显示 2px accent 细线，提示可拖拽。
              child: Center(
                child: AnimatedContainer(
                  duration: IdeMotion.fast,
                  curve: IdeMotion.curveDefault,
                  width: isHorizontal ? 2 : double.infinity,
                  height: isHorizontal ? double.infinity : 2,
                  color: _hovered
                      ? colors.accent.withValues(alpha: 0.7)
                      : Colors.transparent,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

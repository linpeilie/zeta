import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_motion.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';

Color resolvePanelSurfaceColor(BuildContext context, {Color? baseColor}) {
  return baseColor ?? IdeColors.of(context).surface;
}

Color resolvePanelBorderColor(BuildContext context) {
  return IdeColors.of(context).border;
}

Color resolveMutedForegroundColor(BuildContext context) {
  return IdeColors.of(context).textSecondary;
}

/// 统一 runtime 中的紧凑 tooltip。
class IdeTooltip extends StatelessWidget {
  const IdeTooltip({
    required this.message,
    required this.child,
    super.key,
    this.waitDuration,
  });

  final String message;
  final Widget child;
  final Duration? waitDuration;

  @override
  Widget build(BuildContext context) {
    if (message.trim().isEmpty) {
      return child;
    }
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return sf.Tooltip(
      waitDuration: waitDuration ?? const Duration(milliseconds: 500),
      tooltip: (context) => sf.TooltipContainer(
        backgroundColor: colors.surfaceOverlay,
        borderRadius: IdeRadius.allSmall,
        surfaceOpacity: 1,
        surfaceBlur: 0,
        child: Text(
          message,
          style: textStyles.bodySmall.copyWith(
            color: colors.textPrimary,
            fontWeight: FontWeight.w500,
            height: 1.15,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// 紧凑 loading 指示器。
///
/// runtime 迁移后统一使用 shadcn 的线性进度条，避免继续依赖 Material
/// CircularProgressIndicator。
class IdeLoadingIndicator extends StatelessWidget {
  const IdeLoadingIndicator({
    super.key,
    this.width = 20,
    this.height = 10,
    this.barHeight = 3,
    this.semanticsLabel = 'Loading',
  });

  final double width;
  final double height;
  final double barHeight;
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    final radius = BorderRadius.circular(barHeight);
    return Semantics(
      label: semanticsLabel,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: sf.ComponentTheme<sf.ProgressTheme>(
            data: sf.ProgressTheme(
              minHeight: barHeight,
              borderRadius: radius,
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.secondary.withValues(
                alpha: 0.78,
              ),
            ),
            child: const sf.Progress(),
          ),
        ),
      ),
    );
  }
}

/// 非 Material 的交互表面。
///
/// 用于文件树行、时间线折叠行等复杂组合场景，保留 hover/focus/pressed/
/// selected 反馈，同时允许内部继续放嵌套点击区。
class PaneInteractiveSurface extends StatefulWidget {
  const PaneInteractiveSurface({
    required this.child,
    super.key,
    this.onPressed,
    this.padding,
    this.width,
    this.height,
    this.alignment = Alignment.center,
    this.borderRadius,
    this.backgroundColor,
    this.hoverBackgroundColor,
    this.pressedBackgroundColor,
    this.selectedBackgroundColor,
    this.borderColor,
    this.focusBorderColor,
    this.selectedBorderColor,
    this.selected = false,
    this.enabled = true,
    this.button = true,
    this.semanticLabel,
    this.onHoverChanged,
    this.onFocusChanged,
  });

  final Widget child;
  final VoidCallback? onPressed;
  final EdgeInsetsGeometry? padding;
  final double? width;
  final double? height;
  final AlignmentGeometry alignment;
  final BorderRadiusGeometry? borderRadius;
  final Color? backgroundColor;
  final Color? hoverBackgroundColor;
  final Color? pressedBackgroundColor;
  final Color? selectedBackgroundColor;
  final Color? borderColor;
  final Color? focusBorderColor;
  final Color? selectedBorderColor;
  final bool selected;
  final bool enabled;
  final bool button;
  final String? semanticLabel;
  final ValueChanged<bool>? onHoverChanged;
  final ValueChanged<bool>? onFocusChanged;

  @override
  State<PaneInteractiveSurface> createState() => _PaneInteractiveSurfaceState();
}

class _PaneInteractiveSurfaceState extends State<PaneInteractiveSurface> {
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  bool get _interactive => widget.enabled && widget.onPressed != null;

  void _setHovered(bool value) {
    if (_hovered == value) {
      return;
    }
    setState(() {
      _hovered = value;
    });
    widget.onHoverChanged?.call(value);
  }

  void _setFocused(bool value) {
    if (_focused == value) {
      return;
    }
    setState(() {
      _focused = value;
    });
    widget.onFocusChanged?.call(value);
  }

  void _setPressed(bool value) {
    if (_pressed == value) {
      return;
    }
    setState(() {
      _pressed = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    final colorScheme = theme.colorScheme;
    final colors = IdeColors.of(context);
    final radius = widget.borderRadius ?? IdeRadius.allSmall;
    final baseBackground = widget.backgroundColor ?? Colors.transparent;
    final hoverBackground =
        widget.hoverBackgroundColor ??
        colors.border.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.18 : 0.3,
        );
    final pressedBackground =
        widget.pressedBackgroundColor ??
        colors.border.withValues(
          alpha: theme.brightness == Brightness.dark ? 0.28 : 0.4,
        );
    final selectedBackground =
        widget.selectedBackgroundColor ?? colors.primaryMuted;
    final resolvedBackground = switch ((_pressed, _hovered, widget.selected)) {
      (true, _, true) => colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.24 : 0.16,
      ),
      (false, true, true) => colorScheme.primary.withValues(
        alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14,
      ),
      (_, _, true) => selectedBackground,
      (true, _, false) => pressedBackground,
      (false, true, false) => hoverBackground,
      _ => baseBackground,
    };
    final resolvedBorderColor = _focused
        ? (widget.focusBorderColor ?? colorScheme.ring.withValues(alpha: 0.7))
        : widget.selected
        ? (widget.selectedBorderColor ?? widget.borderColor)
        : widget.borderColor;

    return Semantics(
      button: widget.button && _interactive,
      selected: widget.selected,
      label: widget.semanticLabel,
      child: FocusableActionDetector(
        enabled: _interactive,
        mouseCursor: _interactive
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onPressed?.call();
              return null;
            },
          ),
        },
        onShowFocusHighlight: _setFocused,
        child: MouseRegion(
          cursor: _interactive ? SystemMouseCursors.click : MouseCursor.defer,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: _interactive ? widget.onPressed : null,
            onTapDown: _interactive ? (_) => _setPressed(true) : null,
            onTapUp: _interactive ? (_) => _setPressed(false) : null,
            onTapCancel: _interactive ? () => _setPressed(false) : null,
            child: AnimatedContainer(
              duration: IdeMotion.durationNormal,
              curve: IdeMotion.curveDefault,
              width: widget.width,
              height: widget.height,
              alignment: widget.alignment,
              padding: widget.padding,
              decoration: BoxDecoration(
                color: resolvedBackground,
                borderRadius: radius,
                border: resolvedBorderColor == null
                    ? null
                    : Border.all(color: resolvedBorderColor),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
  }
}

class PanelCard extends StatelessWidget {
  const PanelCard({
    required this.child,
    super.key,
    this.color,
    this.showBorder = true,
    this.borderColor,
    this.borderRadius,
    this.boxShadow,
    this.clipBehavior = Clip.antiAlias,
  });

  final Widget child;

  /// 面板背景色；为 null 时按当前主题解析。
  final Color? color;
  final bool showBorder;
  final Color? borderColor;
  final BorderRadiusGeometry? borderRadius;
  final List<BoxShadow>? boxShadow;
  final Clip clipBehavior;

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    final resolvedRadius = borderRadius ?? IdeRadius.allMedium;
    final surfaceColor = resolvePanelSurfaceColor(
      context,
      baseColor: color ?? theme.colorScheme.card,
    );
    // 同一平面的常规面板只靠表面色与边界建立分组；投影仅由浮层显式传入。
    final defaultBoxShadow = boxShadow ?? const <BoxShadow>[];
    return Container(
      clipBehavior: clipBehavior,
      decoration: BoxDecoration(
        color: surfaceColor,
        borderRadius: resolvedRadius,
        boxShadow: defaultBoxShadow,
      ),
      foregroundDecoration: showBorder
          ? BoxDecoration(
              border: Border.all(
                color: borderColor ?? resolvePanelBorderColor(context),
              ),
              borderRadius: resolvedRadius,
            )
          : null,
      child: child,
    );
  }
}

class Pane extends StatelessWidget {
  const Pane({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
    this.titleContent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? titleContent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final trailingWidget = trailing;
    const borderRadius = IdeRadius.allMedium;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: resolvePanelSurfaceColor(
          context,
          baseColor: theme.colorScheme.card,
        ),
        borderRadius: borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 38,
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: resolvePanelBorderColor(
                    context,
                  ).withValues(alpha: 0.6),
                  width: 1,
                ),
              ),
            ),
            padding: const EdgeInsets.only(
              left: IdeSpacing.space12,
              right: IdeSpacing.space6,
            ),
            child: Row(
              children: [
                Expanded(
                  child:
                      titleContent ??
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: textStyles.titleSmall.copyWith(
                              fontWeight: FontWeight.w700,
                              letterSpacing: 0.2,
                              color: colors.textPrimary,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyles.caption.copyWith(
                                color: resolveMutedForegroundColor(context),
                              ),
                            ),
                        ],
                      ),
                ),
                if (trailingWidget case final Widget w) w,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Center(
      child: Padding(
        padding: IdeSpacing.all16,
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: textStyles.bodySmall.copyWith(
            color: resolveMutedForegroundColor(context),
          ),
        ),
      ),
    );
  }
}

class StateLabel extends StatelessWidget {
  const StateLabel({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Container(
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: IdeRadius.allSmall,
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: textStyles.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

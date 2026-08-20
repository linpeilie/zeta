import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';

/// A standalone tab-styled desktop action or status label.
class IdeTab extends StatelessWidget {
  /// Creates a standalone tab.
  const IdeTab({
    required this.label,
    this.leadingIcon,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.selected = false,
    this.enabled = true,
    this.controlSize = AppControlSize.compact,
    this.onPressed,
    this.semanticLabel,
    this.focusNode,
    super.key,
  });

  /// Visible short label.
  final String label;

  /// Optional leading glyph.
  final IconData? leadingIcon;

  /// Optional trailing glyph.
  final IconData? trailingIcon;

  /// Whether the tab is selected.
  final bool selected;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Control density.
  final AppControlSize controlSize;

  /// Activation callback; null renders a read-only label.
  final VoidCallback? onPressed;

  /// Optional accessible name.
  final String? semanticLabel;

  /// Optional externally owned focus node.
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final paddingY = math.max<double>(
      0,
      context.appMetrics.controlPaddingYFor(controlSize) - 1,
    );
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.textPrimary
        : colors.textSecondary;
    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: context.appMetrics.controlMinHeightFor(controlSize),
      ),
      child: PaneInteractiveSurface(
        focusNode: focusNode,
        onPressed: enabled ? onPressed : null,
        enabled: enabled,
        selected: selected,
        button: onPressed != null,
        semanticLabel: semanticLabel ?? label,
        expandToConstraints: false,
        padding: EdgeInsets.symmetric(
          horizontal: context.appSpacing.sm,
          vertical: paddingY,
        ),
        borderRadius: context.appRadii.allSmall,
        backgroundColor: colors.surfaceElevated,
        hoverBackgroundColor: colors.hoverSurface,
        pressedBackgroundColor: colors.pressedSurface,
        selectedBackgroundColor: colors.frame,
        borderColor: colors.borderSubtle,
        selectedBorderColor: colors.border,
        child: AnimatedDefaultTextStyle(
          duration: context.appMotion.resolveFor(
            context,
            context.appMotion.normal,
          ),
          curve: context.appMotion.defaultCurve,
          style: context.appTypography.bodySmall.copyWith(
            color: foreground,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              if (leadingIcon case final icon?) ...<Widget>[
                IdeIconBox(icon, color: foreground),
                SizedBox(width: context.appSpacing.xxs),
              ],
              Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
              if (trailingIcon case final icon?) ...<Widget>[
                SizedBox(width: context.appSpacing.xxs),
                IdeIconBox.custom(
                  child: AnimatedRotation(
                    turns: selected && icon == Icons.keyboard_arrow_down_rounded
                        ? 0.5
                        : 0,
                    duration: context.appMotion.resolveFor(
                      context,
                      context.appMotion.normal,
                    ),
                    curve: context.appMotion.defaultCurve,
                    child: Icon(icon, color: foreground),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 统一 IDE 紧凑胶囊标签 / 选择器。
class IdeChip extends StatelessWidget {
  const IdeChip({
    required this.label,
    super.key,
    this.leadingIcon,
    this.trailingIcon = Icons.keyboard_arrow_down_rounded,
    this.selected = false,
    this.enabled = true,
    this.onPressed,
    this.semanticLabel,
  });

  final String label;
  final IconData? leadingIcon;
  final IconData? trailingIcon;
  final bool selected;
  final bool enabled;
  final VoidCallback? onPressed;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accentForeground
        : colors.textSecondary;
    final pillRadius = BorderRadius.circular(100);
    final isDark = colors.frame.computeLuminance() < 0.5;

    final background = selected
        ? colors.primaryMuted
        : (isDark ? const Color(0x1F2B303B) : const Color(0x0C000000));
    final borderColor = selected
        ? colors.accent.withValues(alpha: 0.4)
        : colors.border.withValues(alpha: 0.5);
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          Icon(leadingIcon, size: 12, color: foreground),
          const SizedBox(width: IdeSpacing.space4),
        ],
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: textStyles.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 10.5,
            color: foreground.withValues(alpha: enabled ? 0.9 : 1),
          ),
        ),
        if (trailingIcon != null) ...[
          const SizedBox(width: IdeSpacing.space2),
          Icon(trailingIcon, size: 12, color: foreground),
        ],
      ],
    );

    if (onPressed == null) {
      return DecoratedBox(
        decoration: BoxDecoration(
          color: background,
          borderRadius: pillRadius,
          border: Border.all(color: borderColor),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IdeSpacing.space10,
            vertical: 4,
          ),
          child: content,
        ),
      );
    }

    return PaneInteractiveSurface(
      onPressed: enabled ? onPressed : null,
      enabled: enabled,
      selected: selected,
      button: true,
      semanticLabel: semanticLabel,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space10,
        vertical: 4,
      ),
      borderRadius: pillRadius,
      backgroundColor: background,
      selectedBackgroundColor: background,
      borderColor: borderColor,
      selectedBorderColor: borderColor,
      child: content,
    );
  }
}

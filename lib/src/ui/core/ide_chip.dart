import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

/// 统一 IDE 紧凑胶囊标签 / 选择器。
///
/// 这里继续保留项目自绘，而不直接改用 `sf.Chip`，以维持 Graphite 当前
/// 的紧凑密度、边框层次与选择态表现。
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
    final theme = sf.Theme.of(context);
    final foreground = !enabled
        ? colors.textTertiary
        : selected
        ? colors.accentForeground
        : colors.textSecondary;
    const pillRadius = IdeRadius.pill;
    final isDark = theme.brightness == Brightness.dark;

    final background = selected
        ? colors.primaryMuted
        : colors.border.withValues(alpha: isDark ? 0.32 : 0.45);
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

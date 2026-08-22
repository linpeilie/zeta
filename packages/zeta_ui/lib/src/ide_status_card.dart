import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

enum IdeStatusCardTone { neutral, info, warning, error, success }

/// 统一 IDE 中的语义状态卡片。
class IdeStatusCard extends StatelessWidget {
  const IdeStatusCard({
    required this.tone,
    required this.title,
    super.key,
    this.leading,
    this.body,
    this.footer,
    this.margin = const EdgeInsets.only(bottom: IdeSpacing.space12),
    this.padding = IdeSpacing.cardPadding,
  });

  final IdeStatusCardTone tone;
  final String title;
  final Widget? leading;
  final Widget? body;
  final Widget? footer;
  final EdgeInsetsGeometry margin;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final accent = _toneColor(colors);
    final neutral = tone == IdeStatusCardTone.neutral;

    return Padding(
      padding: margin,
      child: PanelCard(
        color: neutral ? colors.controlSurface : accent.withValues(alpha: 0.08),
        showBorder: true,
        borderColor: neutral
            ? colors.borderSubtle
            : accent.withValues(
                alpha: tone == IdeStatusCardTone.warning ? 0.35 : 0.26,
              ),
        borderRadius: IdeRadius.allMedium,
        child: Padding(
          padding: padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leading ?? Icon(_toneIcon(), size: 16, color: accent),
                  const SizedBox(width: IdeSpacing.space8),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.titleSmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
              if (body != null)
                Padding(
                  padding: const EdgeInsets.only(top: IdeSpacing.space6),
                  child: body!,
                ),
              if (footer != null)
                Padding(
                  padding: const EdgeInsets.only(top: IdeSpacing.space10),
                  child: footer!,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Color _toneColor(IdeColors colors) {
    return switch (tone) {
      IdeStatusCardTone.neutral => colors.textTertiary,
      IdeStatusCardTone.info => colors.info,
      IdeStatusCardTone.warning => colors.warning,
      IdeStatusCardTone.error => colors.error,
      IdeStatusCardTone.success => colors.success,
    };
  }

  IconData _toneIcon() {
    return switch (tone) {
      IdeStatusCardTone.neutral => Icons.info_outline_rounded,
      IdeStatusCardTone.info => Icons.info_outline_rounded,
      IdeStatusCardTone.warning => Icons.warning_amber_rounded,
      IdeStatusCardTone.error => Icons.error_outline_rounded,
      IdeStatusCardTone.success => Icons.check_circle_outline_rounded,
    };
  }
}

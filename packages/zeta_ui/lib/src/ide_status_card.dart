import 'package:flutter/material.dart';

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_icon_box.dart';
import 'ide_spacing.dart';
import 'ide_text_styles.dart';
import 'pane_widgets.dart';

enum IdeStatusCardTone { neutral, info, warning, error, success }

/// 状态卡片的信息密度。
enum IdeStatusCardDensity {
  /// 面板内的常规状态卡片。
  regular,

  /// 列表或弹层顶部的紧凑状态横幅。
  compact,
}

/// 统一 IDE 中的语义状态卡片。
class IdeStatusCard extends StatelessWidget {
  const IdeStatusCard({
    required this.tone,
    required this.title,
    super.key,
    this.leading,
    this.body,
    this.footer,
    this.density = IdeStatusCardDensity.regular,
    this.titleMaxLines = 1,
    EdgeInsetsGeometry? margin,
    EdgeInsetsGeometry? padding,
  }) : assert(titleMaxLines > 0),
       margin =
           margin ??
           (density == IdeStatusCardDensity.compact
               ? EdgeInsets.zero
               : const EdgeInsets.only(bottom: IdeSpacing.space12)),
       padding =
           padding ??
           (density == IdeStatusCardDensity.compact
               ? const EdgeInsets.symmetric(
                   horizontal: IdeSpacing.space10,
                   vertical: IdeSpacing.space6,
                 )
               : IdeSpacing.cardPadding);

  final IdeStatusCardTone tone;
  final String title;
  final Widget? leading;
  final Widget? body;
  final Widget? footer;

  /// 卡片密度；紧凑档默认不带外边距。
  final IdeStatusCardDensity density;

  /// 标题最多显示的行数。
  final int titleMaxLines;

  /// 外边距；构造时未传则按 [density] 选择默认值。
  final EdgeInsetsGeometry margin;

  /// 内容内边距；构造时未传则按 [density] 选择默认值。
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final accent = _toneColor(colors);
    final neutral = tone == IdeStatusCardTone.neutral;
    final compact = density == IdeStatusCardDensity.compact;
    final titleStyle = compact
        ? textStyles.bodySmall.copyWith(
            color: accent,
            fontWeight: FontWeight.w600,
          )
        : textStyles.titleSmall.copyWith(fontWeight: FontWeight.w700);
    final defaultLeading = compact
        ? IdeIconBox(
            _toneIcon(),
            style: textStyles.bodySmall,
            size: 14,
            color: accent,
          )
        : Icon(_toneIcon(), size: 16, color: accent);
    final content = Padding(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              leading ?? defaultLeading,
              SizedBox(width: compact ? IdeSpacing.space6 : IdeSpacing.space8),
              Expanded(
                child: Text(
                  title,
                  maxLines: titleMaxLines,
                  overflow: TextOverflow.ellipsis,
                  style: titleStyle,
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
    );

    return Padding(
      padding: margin,
      child: PanelCard(
        color: neutral
            ? colors.controlSurface
            : accent.withValues(
                alpha: compact ? _compactBannerBackgroundAlpha : 0.08,
              ),
        showBorder: !compact,
        borderColor: neutral
            ? colors.borderSubtle
            : accent.withValues(
                alpha: tone == IdeStatusCardTone.warning ? 0.35 : 0.26,
              ),
        borderRadius: compact ? BorderRadius.zero : IdeRadius.allMedium,
        child: compact
            ? ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 30),
                child: content,
              )
            : content,
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

const double _compactBannerBackgroundAlpha = 0.1;

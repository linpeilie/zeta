import 'package:flutter/widgets.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';

/// 统一设置项说明与控件的对齐方式。
///
/// 排版上刻意拉开主标题与描述的对比：标题走 `titleSmall`（w600 + textPrimary），
/// 描述压到 `textTertiary`。两者字号同为 12/11，层级完全靠字重与明度表达，
/// 这样即使整页去掉卡片容器，每一项的「标题—说明」结构依然一眼可读。
class IdeSettingsRow extends StatelessWidget {
  const IdeSettingsRow({
    required this.label,
    required this.control,
    super.key,
    this.description,
    this.showDivider = true,
    this.padding,
  });

  final String label;
  final String? description;
  final Widget control;
  final bool showDivider;

  /// 行内边距；为 null 时使用 [IdeSpacing.settingsRowPadding]。
  ///
  /// 平铺（无卡片）场景传 [IdeSpacing.settingsRowPaddingFlat]，把横向对齐
  /// 交给页面级 padding。
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < IdeMetrics.stackedRowBreakpoint;
        final labelContent = Column(
          key: const ValueKey('ide-settings-row-label'),
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(label, style: styles.titleSmall),
            if (description case final String descriptionText) ...[
              const SizedBox(height: IdeSpacing.space4),
              Text(
                descriptionText,
                style: styles.bodySmall.copyWith(color: colors.textTertiary),
              ),
            ],
          ],
        );

        return DecoratedBox(
          decoration: BoxDecoration(
            border: showDivider
                ? Border(bottom: BorderSide(color: colors.borderSubtle))
                : null,
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: IdeMetrics.settingsRowMinHeight,
            ),
            child: Padding(
              padding: padding ?? IdeSpacing.settingsRowPadding,
              child: stacked
                  ? Column(
                      key: const ValueKey('ide-settings-row-stacked'),
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        labelContent,
                        const SizedBox(height: IdeSpacing.space8),
                        Align(alignment: Alignment.centerRight, child: control),
                      ],
                    )
                  : Row(
                      key: const ValueKey('ide-settings-row-inline'),
                      children: [
                        Expanded(child: labelContent),
                        const SizedBox(width: IdeSpacing.space16),
                        Flexible(child: control),
                      ],
                    ),
            ),
          ),
        );
      },
    );
  }
}

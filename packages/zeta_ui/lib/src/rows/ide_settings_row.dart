import 'package:flutter/widgets.dart';

import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import 'ide_row_divider.dart';

/// 统一设置项说明与控件的对齐方式。
///
/// 排版上从三个维度同时拉开主标题与描述的对比：标题走 `titleSmall`
/// （12 / w600 / textPrimary），描述压到 `meta` 档（10 / w400 / textTertiary）
/// 并把行高收到 1.25。字号、字重、明度三档一起降，扫视时视线才会稳稳落在
/// 主标题上，描述退成「需要时才读」的第二层——即使整页去掉卡片容器，每一项的
/// 「标题—说明」结构依然一眼可读。
///
/// 行底分隔线走 [IdeRowDivider] 并按 [padding] 的左值缩进：线的起点与主标题
/// 左边缘严格对齐，不再从行的外沿贯穿过来——有内边距的卡片场景下，那种满幅线
/// 会把「行」的边界画到比内容更靠外的地方，读起来像表格框而不是列表。
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
    final styles = IdeTextStyles.of(context);
    final resolvedPadding = padding ?? IdeSpacing.settingsRowPadding;
    // 分隔线起点直接取行内边距的左值：主标题就是被这个值推到当前位置的，
    // 两者共用同一个数，缩进对齐才是「构造保证」而不是「碰巧相等」。
    final dividerIndent = resolvedPadding
        .resolve(Directionality.of(context))
        .left;
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
              // 行高收紧到 1.25：描述常是一到两行的短句，1.35 会让它散开成
              // 独立段落，反而和主标题争夺「这是一块」的视觉归属。
              Text(descriptionText, style: styles.meta.copyWith(height: 1.25)),
            ],
          ],
        );

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: IdeMetrics.settingsRowMinHeight,
              ),
              child: Padding(
                padding: resolvedPadding,
                child: stacked
                    ? Column(
                        key: const ValueKey('ide-settings-row-stacked'),
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          labelContent,
                          const SizedBox(height: IdeSpacing.space8),
                          Align(
                            alignment: Alignment.centerRight,
                            child: control,
                          ),
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
            // 右端不缩进：左缩进表达「这条线属于下面那些内容」，右端贯通到底
            // 才能让连续几行读起来还是一叠，而不是几条断开的短线。
            if (showDivider) IdeRowDivider(indent: dividerIndent),
          ],
        );
      },
    );
  }
}

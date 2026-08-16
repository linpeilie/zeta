import 'package:flutter/widgets.dart';

import '../ide_spacing.dart';
import '../ide_text_styles.dart';
import 'ide_row_divider.dart';

/// 无卡片的行分组：眉标题 + 平铺行 +（可选的）行间细分割线。
///
/// 去掉 `IdeSurface.pane` 后，分组感由三样东西承担：一个明显弱于行标题的
/// 眉标题（`groupTitle`，9/w700/textSecondary）、行之间的 `borderSubtle` 细线，
/// 以及分组之间 [IdeSpacing.space32] 的留白。眉标题刻意不用 `sectionTitle`
/// ——那一档（13/w600/textPrimary）会和行标题（12/w600/textPrimary）打架，
/// 反而削弱「行标题才是主标题」的层级。
///
/// 标题自带上下内边距（[IdeSpacing.settingsGroupTitlePadding]），所以分组的
/// 纵向节奏完全由本组件闭合，调用方只需在分组之间放一段间隙。
///
/// [dividers] 按行的密度选：`IdeSettingsRow` 那种 52px 的复合设置项需要线来
/// 划清「一项到哪儿为止」；`IdeKeyValueRow` 那种 28px 的密集数据行不需要——
/// 那个行距下逐行画线会立刻退化成表格框，靠留白已经足够分行。
class IdeRowGroup extends StatelessWidget {
  const IdeRowGroup({
    required this.title,
    required this.children,
    super.key,
    this.dividers = true,
  });

  /// 眉标题。
  final String title;

  /// 组内的行。
  final List<Widget> children;

  /// 是否在行与行之间插入 [IdeRowDivider]。
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final styles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: IdeSpacing.settingsGroupTitlePadding,
          child: Text(title, style: styles.groupTitle),
        ),
        for (var index = 0; index < children.length; index++) ...[
          if (dividers && index > 0) const IdeRowDivider(),
          children[index],
        ],
      ],
    );
  }
}

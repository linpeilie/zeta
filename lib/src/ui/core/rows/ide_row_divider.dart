import 'package:flutter/widgets.dart';

import '../ide_colors.dart';

/// 连续 Row 之间的统一细分隔线。
class IdeRowDivider extends StatelessWidget {
  const IdeRowDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IdeColors.of(context).borderSubtle,
      child: const SizedBox(height: 1),
    );
  }
}

/// 并排列之间的统一细分隔线（[IdeRowDivider] 的纵向版本）。
///
/// 高度由父级约束决定，通常放在固定高度的 `SizedBox` 里。
class IdeColumnDivider extends StatelessWidget {
  const IdeColumnDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: IdeColors.of(context).borderSubtle,
      child: const SizedBox(width: 1),
    );
  }
}

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

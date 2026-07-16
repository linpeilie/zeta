import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';

/// 工作台页面中承载搜索、筛选和紧凑操作的连续工具栏。
class IdeToolbar extends StatelessWidget {
  const IdeToolbar({required this.child, super.key});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.symmetric(
          horizontal: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: IdeMetrics.toolbarHeight),
        child: Padding(padding: IdeSpacing.toolbarPadding, child: child),
      ),
    );
  }
}

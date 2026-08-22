import 'package:flutter/widgets.dart';

import '../ide_metrics.dart';
import '../ide_spacing.dart';

/// 为工作台页面提供响应式边距、滚动和可读内容宽度。
class IdePageBody extends StatelessWidget {
  const IdePageBody({
    required this.child,
    super.key,
    this.maxWidth = IdeMetrics.settingsContentMaxWidth,
  });

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < IdeMetrics.mediumBreakpoint;
        return SingleChildScrollView(
          padding: compact
              ? IdeSpacing.pagePaddingCompact
              : IdeSpacing.pagePadding,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxWidth: maxWidth),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

import 'package:app_ui/app_ui.dart';

/// Distributes metrics evenly on wide layouts and scrolls them horizontally
/// on narrow layouts.
class CompactMetricBar extends StatelessWidget {
  /// Creates a compact metric bar.
  const CompactMetricBar({required this.items, super.key});

  /// Metrics in display order.
  final List<CompactMetricItem> items;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();

    final metrics = context.appMetrics;
    return LayoutBuilder(
      builder: (context, constraints) {
        final evenlyDistributed =
            constraints.hasBoundedWidth &&
            constraints.maxWidth >= metrics.metricBarEqualWidthBreakpoint;
        final dividerWidth = (items.length - 1).toDouble();
        final itemWidth = evenlyDistributed
            ? (constraints.maxWidth - dividerWidth) / items.length
            : metrics.metricBarItemWidth;
        return SingleChildScrollView(
          key: const ValueKey<String>('compact-metric-bar-scroll-view'),
          scrollDirection: Axis.horizontal,
          child: Row(
            children: <Widget>[
              for (var index = 0; index < items.length; index++) ...<Widget>[
                SizedBox(
                  key: ValueKey<String>('compact-metric-item-$index'),
                  width: itemWidth,
                  child: _MetricContent(item: items[index]),
                ),
                if (index < items.length - 1)
                  SizedBox(
                    height: metrics.metricBarDividerHeight,
                    child: const IdeColumnDivider(),
                  ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _MetricContent extends StatelessWidget {
  const _MetricContent({required this.item});

  final CompactMetricItem item;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final spacing = context.appSpacing;
    final typography = context.appTypography;
    final tone = item.tone ?? colors.accent;
    final interactive = item.onPressed != null;
    return PaneInteractiveSurface(
      onPressed: item.onPressed,
      button: interactive,
      semanticLabel: interactive ? item.semanticLabel ?? item.label : null,
      padding: EdgeInsets.all(spacing.sm),
      borderRadius: BorderRadius.zero,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              if (item.icon case final icon?) ...<Widget>[
                Icon(icon, size: typography.toolbarLabel.fontSize, color: tone),
                SizedBox(width: spacing.s6),
              ],
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: typography.toolbarLabel,
                ),
              ),
            ],
          ),
          SizedBox(height: spacing.xxs),
          Text(
            item.value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: typography.metricValue.copyWith(color: tone),
          ),
          if (item.detail case final detail?) ...<Widget>[
            SizedBox(height: spacing.xxxs),
            Text(
              detail,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.meta,
            ),
          ],
        ],
      ),
    );
  }
}

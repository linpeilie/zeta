import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_metrics.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';

/// 统一设置项说明与控件的对齐方式。
class IdeSettingsRow extends StatelessWidget {
  const IdeSettingsRow({
    required this.label,
    required this.control,
    super.key,
    this.description,
    this.showDivider = true,
  });

  final String label;
  final String? description;
  final Widget control;
  final bool showDivider;

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
            Text(label, style: styles.rowTitle),
            if (description case final String descriptionText) ...[
              const SizedBox(height: IdeSpacing.space2),
              Text(
                descriptionText,
                style: styles.bodySmall.copyWith(color: colors.textSecondary),
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
              padding: IdeSpacing.settingsRowPadding,
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

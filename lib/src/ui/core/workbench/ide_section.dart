import 'package:flutter/material.dart';

import '../ide_colors.dart';
import '../ide_spacing.dart';
import '../ide_text_styles.dart';

/// 使用统一标题层级组织页面内容，但不额外创建卡片表面。
class IdeSection extends StatelessWidget {
  const IdeSection({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: styles.sectionTitle),
                  if (subtitle case final String subtitleText)
                    Text(
                      subtitleText,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: styles.meta.copyWith(color: colors.textSecondary),
                    ),
                ],
              ),
            ),
            if (trailing case final Widget trailingWidget) ...[
              const SizedBox(width: IdeSpacing.space8),
              trailingWidget,
            ],
          ],
        ),
        const SizedBox(height: IdeSpacing.space8),
        child,
      ],
    );
  }
}

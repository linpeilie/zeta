import 'package:flutter/material.dart';

import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';

class PanelCard extends StatelessWidget {
  const PanelCard({required this.child, super.key, this.color});

  final Widget child;

  /// 面板背景色；为 null 时按当前主题解析。
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: color ?? colors.panel,
        borderRadius: BorderRadius.circular(idePanelRadius),
      ),
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: colors.border),
        borderRadius: BorderRadius.circular(idePanelRadius),
      ),
      child: child,
    );
  }
}

class Pane extends StatelessWidget {
  const Pane({
    required this.title,
    required this.child,
    super.key,
    this.subtitle,
    this.trailing,
    this.titleContent,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? titleContent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(color: colors.panel),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: 36,
            padding: const EdgeInsets.only(left: 10, right: 6),
            child: Row(
              children: [
                Expanded(
                  child:
                      titleContent ??
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: colors.mutedText,
                                fontSize: 10,
                              ),
                            ),
                        ],
                      ),
                ),
                ?trailing,
              ],
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class EmptyState extends StatelessWidget {
  const EmptyState({required this.text, super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(color: colors.mutedText, fontSize: 12),
        ),
      ),
    );
  }
}

class StateLabel extends StatelessWidget {
  const StateLabel({required this.text, required this.color, super.key});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 22,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

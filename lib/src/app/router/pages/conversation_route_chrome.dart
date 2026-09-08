import 'package:flutter/material.dart';

import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// 冷开会话骨架：标题同步可得时立刻画出，转圈超过约 100ms 才出现。
class ConversationSkeletonPage extends StatelessWidget {
  const ConversationSkeletonPage({
    required this.title,
    required this.showSpinner,
    super.key,
  });

  final String title;
  final bool showSpinner;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeSurface.canvas(
      key: const ValueKey<String>('conversation-skeleton'),
      child: ColoredBox(
        color: colors.canvasSurface,
        child: Center(
          child: Padding(
            padding: IdeSpacing.all16,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: textStyles.bodyMedium,
                ),
                if (showSpinner) ...[
                  const SizedBox(height: IdeSpacing.space12),
                  IdeBusySpinner(
                    key: const ValueKey<String>('conversation-open-spinner'),
                    size: 20,
                    color: colors.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// reconcile 失败后的错误态；回落由调用方导航。
class ConversationOpenFailedPage extends StatelessWidget {
  const ConversationOpenFailedPage({required this.onBack, super.key});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return IdeSurface.canvas(
      key: const ValueKey<String>('conversation-open-failed'),
      child: Center(
        child: Padding(
          padding: IdeSpacing.all16,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              EmptyState(text: context.l10n.conversationOpenFailed),
              const SizedBox(height: IdeSpacing.space12),
              IdeButton(
                key: const ValueKey<String>('conversation-open-failed-back'),
                label: context.l10n.conversationOpenFailedBack,
                onPressed: onBack,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

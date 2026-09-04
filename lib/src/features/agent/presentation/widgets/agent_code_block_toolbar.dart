import 'dart:async';

import 'package:flutter/material.dart';
import 'package:zeta_markdown/zeta_markdown.dart';
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// 代码块工具栏：语言标签 + 行数 + 复制。
///
/// 作为**顶层函数**传给 `MarkdownWidget.codeBlockToolbarBuilder`——必须是稳定
/// 引用，每帧新建闭包会让缓存的 block 行失去复用价值（同 `onTapLink` 那条约定）。
Widget? agentCodeBlockToolbar(
  BuildContext context,
  MarkdownCodeBlockToolbarData data,
) {
  return _AgentCodeBlockToolbar(
    language: data.language,
    lineCount: data.lineCount,
    onCopy: data.onCopy,
  );
}

/// 「已复制」是有态反馈，所以工具栏本体必须自持状态。
///
/// builder 每帧都会被调用，状态放在闭包里会被下一帧抹掉。
class _AgentCodeBlockToolbar extends StatefulWidget {
  const _AgentCodeBlockToolbar({
    required this.language,
    required this.lineCount,
    required this.onCopy,
  });

  final String? language;
  final int lineCount;
  final VoidCallback onCopy;

  @override
  State<_AgentCodeBlockToolbar> createState() => _AgentCodeBlockToolbarState();
}

class _AgentCodeBlockToolbarState extends State<_AgentCodeBlockToolbar> {
  static const _feedbackDuration = Duration(milliseconds: 1500);

  Timer? _resetTimer;
  bool _copied = false;

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }

  void _handleCopy() {
    widget.onCopy();
    setState(() => _copied = true);
    _resetTimer?.cancel();
    _resetTimer = Timer(_feedbackDuration, () {
      if (!mounted) {
        return;
      }
      setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final l10n = context.l10n;
    final metaStyle = textStyles.meta.copyWith(color: colors.textTertiary);
    final language = widget.language?.trim();

    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        if (language != null && language.isNotEmpty) ...<Widget>[
          Text(language, style: metaStyle),
          const SizedBox(width: IdeSpacing.space8),
        ],
        if (widget.lineCount > 0) ...<Widget>[
          Text(l10n.agentLineCount('${widget.lineCount}'), style: metaStyle),
          const SizedBox(width: IdeSpacing.space6),
        ],
        // 必须给定高度：代码块所在的行会把无界高度直接传下来（markdown 子树在
        // sliver 里就是无界的），按钮不设上界会被拉伸成整屏高。
        SizedBox.square(
          dimension: IdeMetrics.controlMinHeightFor(IdeControlSize.compact),
          child: IdeIconButton(
            icon: _copied ? Icons.check_rounded : Icons.copy_rounded,
            // 图标在「已复制」状态下变化，无障碍名称保持稳定的动作语义。
            semanticLabel: l10n.shadcnMenuCopy,
            variant: IdeButtonVariant.ghost,
            onPressed: _handleCopy,
          ),
        ),
      ],
    );
  }
}

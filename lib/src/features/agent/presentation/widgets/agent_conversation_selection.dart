import 'package:flutter/material.dart';

import 'package:zeta_markdown/zeta_markdown.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/app/edit_menu_bridge.dart';

/// 整条对话时间线的官方选区：高亮由 [RenderParagraph] 绘制，⌘C 走
/// [SelectableRegion]，不依赖单条消息的 FocusNode。
class AgentConversationSelectionArea extends StatefulWidget {
  const AgentConversationSelectionArea({required this.child, super.key});

  final Widget child;

  @override
  State<AgentConversationSelectionArea> createState() =>
      _AgentConversationSelectionAreaState();
}

class _AgentConversationSelectionAreaState
    extends State<AgentConversationSelectionArea> {
  final FocusNode _focusNode = FocusNode(
    debugLabel: 'agent-conversation-selection',
  );

  @override
  void initState() {
    super.initState();
    EditMenuBridge.instance.setCopyHandler(_copyIfFocused);
  }

  @override
  void dispose() {
    EditMenuBridge.instance.setCopyHandler(null);
    _focusNode.dispose();
    super.dispose();
  }

  void _copyIfFocused() {
    if (!_focusNode.hasFocus) {
      return;
    }
    final context = _focusNode.context;
    if (context == null) {
      return;
    }
    Actions.maybeInvoke(context, CopySelectionTextIntent.copy);
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return TextSelectionTheme(
      data: TextSelectionTheme.of(context).copyWith(
        selectionColor: colors.primaryMuted,
        selectionHandleColor: colors.accent,
        cursorColor: colors.accent,
      ),
      child: SelectionArea(
        focusNode: _focusNode,
        contextMenuBuilder: _contextMenuBuilder,
        child: MarkdownSelectionScrollIsolation(child: widget.child),
      ),
    );
  }

  Widget _contextMenuBuilder(
    BuildContext context,
    SelectableRegionState selectableRegionState,
  ) {
    final items = selectableRegionState.contextMenuButtonItems
        .where((item) => item.type != ContextMenuButtonType.selectAll)
        .toList(growable: false);
    if (items.isEmpty) {
      return const SizedBox.shrink();
    }
    return AdaptiveTextSelectionToolbar.buttonItems(
      anchors: selectableRegionState.contextMenuAnchors,
      buttonItems: items,
    );
  }
}

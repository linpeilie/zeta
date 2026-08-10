part of '../agent_pane.dart';

/// 会话内对话导航轨：短横线对应各用户回合，点击跳转、滚动同步当前项。
///
/// 低对比度折叠态；悬停用 [IdeTooltip] 展示提问摘要。不持久化任何正文。
class _AgentConversationNavigationRail extends StatefulWidget {
  const _AgentConversationNavigationRail({
    required this.entries,
    required this.activeTurnId,
    required this.onSelectTurn,
    super.key,
    this.compact = false,
  });

  final List<AgentConversationNavigationEntry> entries;
  final String? activeTurnId;
  final ValueChanged<AgentConversationNavigationEntry> onSelectTurn;

  /// 窄视口时进一步压缩点击区，避免遮挡正文。
  final bool compact;

  @override
  State<_AgentConversationNavigationRail> createState() =>
      _AgentConversationNavigationRailState();
}

class _AgentConversationNavigationRailState
    extends State<_AgentConversationNavigationRail> {
  late final FocusNode _focusNode;
  int _focusedIndex = 0;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(debugLabel: 'AgentConversationNavigationRail')
      ..addListener(_handleFocusChange);
    _syncFocusedIndex();
  }

  @override
  void didUpdateWidget(covariant _AgentConversationNavigationRail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.activeTurnId != widget.activeTurnId ||
        oldWidget.entries.length != widget.entries.length) {
      _syncFocusedIndex();
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_handleFocusChange)
      ..dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncFocusedIndex() {
    final activeId = widget.activeTurnId;
    if (activeId == null || widget.entries.isEmpty) {
      _focusedIndex = 0;
      return;
    }
    final index = widget.entries.indexWhere(
      (entry) => entry.turnId == activeId,
    );
    if (index >= 0) {
      _focusedIndex = index;
    } else {
      _focusedIndex = _focusedIndex.clamp(0, widget.entries.length - 1);
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final entries = widget.entries;
    if (entries.isEmpty) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown ||
        key == LogicalKeyboardKey.arrowRight) {
      setState(() {
        _focusedIndex = (_focusedIndex + 1).clamp(0, entries.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp ||
        key == LogicalKeyboardKey.arrowLeft) {
      setState(() {
        _focusedIndex = (_focusedIndex - 1).clamp(0, entries.length - 1);
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      setState(() => _focusedIndex = 0);
      widget.onSelectTurn(entries.first);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      setState(() => _focusedIndex = entries.length - 1);
      widget.onSelectTurn(entries.last);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) {
      final index = _focusedIndex.clamp(0, entries.length - 1);
      widget.onSelectTurn(entries[index]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final tickWidth = widget.compact ? 10.0 : 14.0;
    final gap = widget.compact ? IdeSpacing.space4 : IdeSpacing.space6;

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Semantics(
        container: true,
        label: '对话导航',
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              vertical: IdeSpacing.space12,
              horizontal: IdeSpacing.space2,
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 360),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var index = 0; index < widget.entries.length; index++)
                      Padding(
                        padding: EdgeInsets.only(
                          bottom: index == widget.entries.length - 1 ? 0 : gap,
                        ),
                        child: _AgentConversationNavigationTick(
                          entry: widget.entries[index],
                          selected:
                              widget.entries[index].turnId ==
                              widget.activeTurnId,
                          focused:
                              _focusNode.hasFocus && _focusedIndex == index,
                          tickWidth: tickWidth,
                          onPressed: () {
                            setState(() => _focusedIndex = index);
                            widget.onSelectTurn(widget.entries[index]);
                          },
                          trackColor: colors.border.withValues(alpha: 0.45),
                          activeColor: colors.textSecondary.withValues(
                            alpha: 0.92,
                          ),
                          streamingColor: colors.accent.withValues(alpha: 0.85),
                          failedColor: colors.error.withValues(alpha: 0.8),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentConversationNavigationTick extends StatelessWidget {
  const _AgentConversationNavigationTick({
    required this.entry,
    required this.selected,
    required this.focused,
    required this.tickWidth,
    required this.onPressed,
    required this.trackColor,
    required this.activeColor,
    required this.streamingColor,
    required this.failedColor,
  });

  final AgentConversationNavigationEntry entry;
  final bool selected;
  final bool focused;
  final double tickWidth;
  final VoidCallback onPressed;
  final Color trackColor;
  final Color activeColor;
  final Color streamingColor;
  final Color failedColor;

  @override
  Widget build(BuildContext context) {
    final color = switch (entry.status) {
      AgentConversationNavigationStatus.failed => failedColor,
      AgentConversationNavigationStatus.streaming => streamingColor,
      _ => selected ? activeColor : trackColor,
    };
    final height = selected ? 3.0 : 2.0;
    final width = selected ? tickWidth + 4 : tickWidth;
    final tooltip = buildAgentConversationNavigationTooltip(entry);

    return IdeTooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 280),
      child: PaneInteractiveSurface(
        onPressed: onPressed,
        button: true,
        semanticLabel: '第 ${entry.ordinal} 个回合：${entry.label}',
        borderRadius: IdeRadius.allSmall,
        hoverBackgroundColor: trackColor.withValues(alpha: 0.2),
        padding: const EdgeInsets.symmetric(
          horizontal: IdeSpacing.space4,
          vertical: IdeSpacing.space4,
        ),
        child: AnimatedContainer(
          duration: IdeMotion.durationFast,
          curve: IdeMotion.curveScroll,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: IdeRadius.allSmall,
            border: focused
                ? Border.all(
                    color: activeColor.withValues(alpha: 0.55),
                    width: 1,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

part of '../agent_pane.dart';

/// 默认「长」短横线宽度（偶数下标）。
const double _kNavTickWidthLong = 12;

/// 默认「短」短横线宽度（奇数下标）。
const double _kNavTickWidthShort = 6;

/// 选中 / hover 强调态短横线宽度。
const double _kNavTickWidthEmphasized = 16;

/// 会话内对话导航轨：短横线对应各用户回合，点击跳转、滚动同步当前项。
///
/// 宽度节奏：默认长短长短（12 / 6）；选中或 hover 时该线拉到 16。
///
/// 强调色策略：
/// - 无 hover：当前查看回合更深色；
/// - hover 某短线：更深色切到该线；
/// - 短线之间切换用 [IdeMotion] 过渡尺寸与颜色，避免跳变。
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

  /// 指针悬停的短线下标；null 表示未悬停，强调回落到当前查看回合。
  int? _hoveredIndex;

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
      // 条目数量变化时钳制 hover，避免越界强调。
      final hovered = _hoveredIndex;
      if (hovered != null && widget.entries.isNotEmpty) {
        final next = hovered.clamp(0, widget.entries.length - 1);
        if (next != hovered) {
          _hoveredIndex = next;
        }
      } else if (widget.entries.isEmpty) {
        _hoveredIndex = null;
      }
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
    } else if (widget.entries.isNotEmpty) {
      _focusedIndex = _focusedIndex.clamp(0, widget.entries.length - 1);
    }
  }

  /// 视觉强调下标：hover 优先，否则为当前查看回合。
  int? get _emphasizedIndex {
    final entries = widget.entries;
    if (entries.isEmpty) {
      return null;
    }
    final hovered = _hoveredIndex;
    if (hovered != null) {
      return hovered.clamp(0, entries.length - 1);
    }
    final activeId = widget.activeTurnId;
    if (activeId == null) {
      return null;
    }
    final activeIndex = entries.indexWhere((e) => e.turnId == activeId);
    return activeIndex >= 0 ? activeIndex : null;
  }

  void _setHoveredIndex(int? index) {
    if (_hoveredIndex == index) {
      return;
    }
    setState(() {
      _hoveredIndex = index;
    });
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
    final gap = widget.compact ? IdeSpacing.space4 : IdeSpacing.space6;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final emphasizeDuration = reduceMotion
        ? Duration.zero
        : IdeMotion.durationNormal;
    final emphasizedIndex = _emphasizedIndex;
    final trackColor = colors.border.withValues(alpha: 0.42);
    final deepColor = colors.textSecondary.withValues(alpha: 0.94);
    final streamingColor = colors.accent.withValues(alpha: 0.85);
    final failedColor = colors.error.withValues(alpha: 0.8);

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Semantics(
        container: true,
        label: '对话导航',
        child: Material(
          type: MaterialType.transparency,
          // 整轨 onExit 清 hover，避免短线间隙短暂回落到 active 造成闪烁。
          child: MouseRegion(
            onExit: (_) => _setHoveredIndex(null),
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
                    // 左对齐：贴 AgentPanel 左侧，长短交替时左侧齐平、强调向右延伸。
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (
                        var index = 0;
                        index < widget.entries.length;
                        index++
                      )
                        _AgentConversationNavigationTick(
                          entry: widget.entries[index],
                          emphasized: emphasizedIndex == index,
                          isActiveView:
                              widget.entries[index].turnId ==
                              widget.activeTurnId,
                          focused:
                              _focusNode.hasFocus && _focusedIndex == index,
                          // 默认长短长短：偶数为长 12、奇数为短 6。
                          restingWidth: index.isEven
                              ? _kNavTickWidthLong
                              : _kNavTickWidthShort,
                          // 间隙并入 hit 区，hover 在相邻短线间连续滑动。
                          bottomGap: index == widget.entries.length - 1
                              ? 0
                              : gap,
                          animationDuration: emphasizeDuration,
                          onPressed: () {
                            setState(() => _focusedIndex = index);
                            widget.onSelectTurn(widget.entries[index]);
                          },
                          onHoverChanged: (hovered) {
                            // 只在 enter 时更新；leave 不立刻清空，避免短线间隙
                            // 闪回 active。整轨 MouseRegion.onExit 负责复位。
                            if (hovered) {
                              _setHoveredIndex(index);
                            }
                          },
                          trackColor: trackColor,
                          deepColor: deepColor,
                          streamingColor: streamingColor,
                          failedColor: failedColor,
                        ),
                    ],
                  ),
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
    required this.emphasized,
    required this.isActiveView,
    required this.focused,
    required this.restingWidth,
    required this.bottomGap,
    required this.animationDuration,
    required this.onPressed,
    required this.onHoverChanged,
    required this.trackColor,
    required this.deepColor,
    required this.streamingColor,
    required this.failedColor,
  });

  final AgentConversationNavigationEntry entry;

  /// 当前视觉强调（hover 项或无 hover 时的查看中回合）。
  final bool emphasized;

  /// 是否为滚动同步的当前查看回合（无障碍 / 语义用）。
  final bool isActiveView;
  final bool focused;

  /// 非强调态宽度（长短交替：12 或 6）。
  final double restingWidth;
  final double bottomGap;
  final Duration animationDuration;
  final VoidCallback onPressed;
  final ValueChanged<bool> onHoverChanged;
  final Color trackColor;
  final Color deepColor;
  final Color streamingColor;
  final Color failedColor;

  Color get _baseStatusColor {
    return switch (entry.status) {
      AgentConversationNavigationStatus.failed => failedColor,
      AgentConversationNavigationStatus.streaming => streamingColor,
      _ => deepColor,
    };
  }

  @override
  Widget build(BuildContext context) {
    // 强调：更深/状态色 + 宽度 16；非强调：低对比 + 长短交替 12/6。
    final color = emphasized
        ? _baseStatusColor
        : trackColor.withValues(alpha: 0.45);
    final height = emphasized ? 3.0 : 2.0;
    final width = emphasized ? _kNavTickWidthEmphasized : restingWidth;
    final tooltip = buildAgentConversationNavigationTooltip(entry);

    return IdeTooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 280),
      child: PaneInteractiveSurface(
        onPressed: onPressed,
        onHoverChanged: onHoverChanged,
        button: true,
        // 轨在左侧：短线左缘对齐，变宽时向右伸展。
        alignment: Alignment.centerLeft,
        semanticLabel:
            '第 ${entry.ordinal} 个回合：${entry.label}'
            '${isActiveView ? '，当前查看' : ''}',
        borderRadius: IdeRadius.allSmall,
        hoverBackgroundColor: trackColor.withValues(alpha: 0.18),
        // 点击区按强调态最大宽度预留，避免长短切换时 hit 框抖动。
        width: _kNavTickWidthEmphasized + IdeSpacing.space4 * 2,
        padding: EdgeInsets.only(
          left: IdeSpacing.space4,
          right: IdeSpacing.space4,
          top: IdeSpacing.space4,
          bottom: IdeSpacing.space4 + bottomGap,
        ),
        child: AnimatedContainer(
          duration: animationDuration,
          curve: IdeMotion.curveDefault,
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: color,
            borderRadius: IdeRadius.allSmall,
            border: focused
                ? Border.all(color: deepColor.withValues(alpha: 0.55), width: 1)
                : null,
          ),
        ),
      ),
    );
  }
}

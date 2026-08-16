part of '../agent_pane.dart';

/// 默认「长」短横线宽度（偶数下标）。
const double _kNavTickWidthLong = 12;

/// 默认「短」短横线宽度（奇数下标）。
const double _kNavTickWidthShort = 6;

/// 选中 / hover 强调态短横线宽度。
const double _kNavTickWidthEmphasized = 16;

/// hover 预览卡最大宽度。
const double _kNavPreviewCardMaxWidth = 260;

/// 会话内对话导航轨：短横线对应各用户回合，点击跳转、滚动同步当前项。
///
/// 宽度节奏：默认长短长短（12 / 6）；选中或 hover 时该线拉到 16。
///
/// 强调色策略：
/// - 无 hover：当前查看回合更深色；
/// - hover 某短线：更深色切到该线，并在轨**右侧**以叠层展示预览 Card；
/// - 预览卡用 [Stack]/[Positioned] 脱离纵向布局，**不改变轨自身高度**；
/// - 短线之间切换用 [IdeMotion] 过渡尺寸与颜色，避免跳变。
///
/// 低对比度折叠态；不持久化任何正文。
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

  /// 估算第 [index] 条短线中心相对 ticks 列顶部的 y（含外层 vertical padding 前）。
  double _tickCenterY({required int index, required double gap}) {
    // 与 tick 布局一致：top pad + 线高(用 resting 2) + bottom pad(+gap)。
    const topPad = IdeSpacing.space4;
    const line = 2.0;
    const bottomPad = IdeSpacing.space4;
    final slotWithoutGap = topPad + line + bottomPad;
    var y = 0.0;
    for (var i = 0; i < index; i++) {
      y += slotWithoutGap + gap;
    }
    return y + topPad + line / 2;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final gap = widget.compact ? IdeSpacing.space4 : IdeSpacing.space6;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final emphasizeDuration = reduceMotion
        ? Duration.zero
        : IdeMotion.durationNormal;
    final cardDuration = reduceMotion
        ? Duration.zero
        : IdeMotion.durationNormal;
    final emphasizedIndex = _emphasizedIndex;
    final hoveredIndex = _hoveredIndex;
    final trackColor = colors.border.withValues(alpha: 0.42);
    final deepColor = colors.textSecondary.withValues(alpha: 0.94);
    final streamingColor = colors.accent.withValues(alpha: 0.85);
    final failedColor = colors.error.withValues(alpha: 0.8);
    final brightness = Theme.of(context).brightness;
    // 与 tick 固定 hit 宽一致，供卡片横向定位（不撑高）。
    const tickColumnWidth = _kNavTickWidthEmphasized + IdeSpacing.space4 * 2;
    AgentConversationNavigationEntry? hoveredEntry;
    if (hoveredIndex != null &&
        hoveredIndex >= 0 &&
        hoveredIndex < widget.entries.length) {
      hoveredEntry = widget.entries[hoveredIndex];
    }

    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _handleKey,
      child: Semantics(
        container: true,
        label: context.l10n.agentNavConversation,
        child: Material(
          type: MaterialType.transparency,
          // 整轨 + 预览卡同一 MouseRegion，移入卡片不丢失 hover。
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
                  // Stack：高度只由短线列决定；预览卡 Positioned 叠在右侧，
                  // 不进入纵向 flex，避免 hover 改变轨高导致整轨上移。
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // hover 时仅横向扩宽命中区，便于指针移入右侧卡片；
                      // 高度必须为 0，避免 SizedBox 在无 height 时吃满纵向约束。
                      if (hoveredEntry != null)
                        const SizedBox(
                          width:
                              tickColumnWidth +
                              IdeSpacing.space8 +
                              _kNavPreviewCardMaxWidth,
                          height: 0,
                        ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
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
                              restingWidth: index.isEven
                                  ? _kNavTickWidthLong
                                  : _kNavTickWidthShort,
                              bottomGap: index == widget.entries.length - 1
                                  ? 0
                                  : gap,
                              animationDuration: emphasizeDuration,
                              onPressed: () {
                                setState(() => _focusedIndex = index);
                                widget.onSelectTurn(widget.entries[index]);
                              },
                              onHoverChanged: (hovered) {
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
                      if (hoveredEntry != null)
                        Positioned(
                          left: tickColumnWidth + IdeSpacing.space8,
                          top: math.max(
                            0,
                            _tickCenterY(index: hoveredIndex!, gap: gap) - 28,
                          ),
                          child: AnimatedSwitcher(
                            duration: cardDuration,
                            switchInCurve: IdeMotion.curvePopup,
                            switchOutCurve: IdeMotion.curveDefault,
                            transitionBuilder: (child, animation) {
                              final fade = CurvedAnimation(
                                parent: animation,
                                curve: IdeMotion.curveDefault,
                              );
                              final slide =
                                  Tween<Offset>(
                                    begin: const Offset(-0.06, 0),
                                    end: Offset.zero,
                                  ).animate(
                                    CurvedAnimation(
                                      parent: animation,
                                      curve: IdeMotion.curvePopup,
                                    ),
                                  );
                              return FadeTransition(
                                opacity: fade,
                                child: SlideTransition(
                                  position: slide,
                                  child: child,
                                ),
                              );
                            },
                            child: _AgentConversationNavigationPreviewCard(
                              key: ValueKey<String>(
                                'nav-preview-${hoveredEntry.turnId}',
                              ),
                              entry: hoveredEntry,
                              brightness: brightness,
                              onTap: () {
                                setState(() {
                                  _focusedIndex = hoveredIndex;
                                });
                                widget.onSelectTurn(hoveredEntry!);
                              },
                            ),
                          ),
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
    final color = emphasized
        ? _baseStatusColor
        : trackColor.withValues(alpha: 0.45);
    const height = 2.0;
    final width = emphasized ? _kNavTickWidthEmphasized : restingWidth;

    return PaneInteractiveSurface(
      onPressed: onPressed,
      onHoverChanged: onHoverChanged,
      button: true,
      alignment: Alignment.centerLeft,
      semanticLabel:
          '第 ${entry.ordinal} 个回合：${entry.label}'
          '${isActiveView ? '，当前查看' : ''}',
      borderRadius: IdeRadius.allSmall,
      // 导航短线以线色/线宽表达 hover；不刷 surface 底，避免 bottomGap
      // 区域出现整块异色 hover 条。
      hoverBackgroundColor: Colors.transparent,
      pressedBackgroundColor: Colors.transparent,
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
    );
  }
}

/// 导航轨右侧 hover 预览卡：回合序号、提问摘要、状态与 token / 时间。
class _AgentConversationNavigationPreviewCard extends StatelessWidget {
  const _AgentConversationNavigationPreviewCard({
    required this.entry,
    required this.brightness,
    required this.onTap,
    super.key,
  });

  final AgentConversationNavigationEntry entry;
  final Brightness brightness;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final status = _navStatusPresentation(entry.status, colors, context.l10n);
    final tokenLabel = agentConversationNavigationTokenLabel(entry.tokenUsage);

    return ConstrainedBox(
      constraints: const BoxConstraints(
        minWidth: 180,
        maxWidth: _kNavPreviewCardMaxWidth,
      ),
      child: PaneInteractiveSurface(
        onPressed: onTap,
        button: true,
        borderRadius: IdeRadius.allMedium,
        semanticLabel: buildAgentConversationNavigationTooltip(entry),
        child: PanelCard(
          color: colors.surfaceElevated,
          borderRadius: IdeRadius.allMedium,
          boxShadow: IdeEffects.overlayShadow(brightness),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              IdeSpacing.space12,
              IdeSpacing.space10,
              IdeSpacing.space12,
              IdeSpacing.space12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 顶行：序号 + 状态徽章
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        '第 ${entry.ordinal} 个回合',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.meta.copyWith(
                          color: colors.textTertiary,
                          fontWeight: FontWeight.w500,
                          letterSpacing: 0.2,
                        ),
                      ),
                    ),
                    const SizedBox(width: IdeSpacing.space8),
                    _NavStatusBadge(
                      label: status.label,
                      foreground: status.foreground,
                      background: status.background,
                    ),
                  ],
                ),
                const SizedBox(height: IdeSpacing.space8),
                // 提问摘要
                Text(
                  entry.label,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodyMedium.copyWith(
                    color: colors.textPrimary,
                    fontWeight: FontWeight.w600,
                    height: 1.35,
                  ),
                ),
                if (tokenLabel != null || entry.startedAt != null) ...[
                  const SizedBox(height: IdeSpacing.space10),
                  Container(
                    height: 1,
                    color: colors.borderSubtle.withValues(alpha: 0.7),
                  ),
                  const SizedBox(height: IdeSpacing.space8),
                  Wrap(
                    spacing: IdeSpacing.space6,
                    runSpacing: IdeSpacing.space4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (tokenLabel != null)
                        _NavMetaChip(
                          icon: Icons.toll_outlined,
                          label: tokenLabel,
                          color: colors.textSecondary,
                        ),
                      if (entry.startedAt != null)
                        _NavMetaChip(
                          icon: Icons.schedule_rounded,
                          label: _formatNavTime(entry.startedAt!),
                          color: colors.textTertiary,
                        ),
                    ],
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

class _NavStatusBadge extends StatelessWidget {
  const _NavStatusBadge({
    required this.label,
    required this.foreground,
    required this.background,
  });

  final String label;
  final Color foreground;
  final Color background;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space6,
        vertical: IdeSpacing.space2,
      ),
      decoration: BoxDecoration(
        color: background,
        borderRadius: IdeRadius.pill,
      ),
      child: Text(
        label,
        style: textStyles.meta.copyWith(
          color: foreground,
          fontWeight: FontWeight.w600,
          height: 1.1,
        ),
      ),
    );
  }
}

class _NavMetaChip extends StatelessWidget {
  const _NavMetaChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: color.withValues(alpha: 0.9)),
        const SizedBox(width: IdeSpacing.space2),
        Text(
          label,
          style: textStyles.meta.copyWith(
            color: color,
            fontWeight: FontWeight.w500,
            height: 1.1,
          ),
        ),
      ],
    );
  }
}

({String label, Color foreground, Color background}) _navStatusPresentation(
  AgentConversationNavigationStatus status,
  IdeColors colors,
  AppLocalizations l10n,
) {
  return switch (status) {
    AgentConversationNavigationStatus.streaming => (
      label: l10n.agentStatusStreaming,
      foreground: colors.accent,
      background: colors.accent.withValues(alpha: 0.14),
    ),
    AgentConversationNavigationStatus.completed => (
      label: l10n.agentStatusCompleted,
      foreground: colors.success,
      background: colors.success.withValues(alpha: 0.14),
    ),
    AgentConversationNavigationStatus.failed => (
      label: l10n.agentStatusFailed,
      foreground: colors.error,
      background: colors.error.withValues(alpha: 0.14),
    ),
    AgentConversationNavigationStatus.interrupted => (
      label: l10n.agentStatusInterrupted,
      foreground: colors.warning,
      background: colors.warning.withValues(alpha: 0.14),
    ),
    AgentConversationNavigationStatus.unknown => (
      label: l10n.agentStatusUnknown,
      foreground: colors.textSecondary,
      background: colors.border.withValues(alpha: 0.2),
    ),
  };
}

String _formatNavTime(DateTime time) {
  final local = time.toLocal();
  final hh = local.hour.toString().padLeft(2, '0');
  final mm = local.minute.toString().padLeft(2, '0');
  return '$hh:$mm';
}

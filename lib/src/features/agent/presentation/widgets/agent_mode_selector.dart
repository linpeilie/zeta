part of '../agent_pane.dart';

const double _agentModeSelectorPopoverPreferredWidth = 240;
const double _agentModeSelectorPopoverMaxHeight = 280;
const double _agentModeSelectorLabelMaxWidth = 156;

/// 模式选择器的 Provider 中立展示状态。
enum AgentModeSelectorStatus {
  /// 当前 Provider 不提供模式选择能力，控件不渲染。
  unavailable,

  /// 正在探测模式目录。
  loading,

  /// 模式目录可用。
  ready,

  /// 模式目录探测失败。
  error,
}

/// Agent Composer 使用的紧凑对话模式选择器。
///
/// 组件只消费领域层预设与选择意图，不持有 Thread 或 Provider 状态。调用方可通过
/// [contextId] 标识当前上下文；上下文变化时已打开的旧弹层会自动关闭。
class AgentModeSelector extends StatefulWidget {
  const AgentModeSelector({
    required this.status,
    this.presets = const <AgentConversationModePreset>[],
    this.selectedMode,
    this.appliesToNextTurn = false,
    this.statusMessage,
    this.contextId,
    this.onChanged,
    super.key,
  });

  /// 当前目录展示状态。
  final AgentModeSelectorStatus status;

  /// Provider 返回的模式预设快照。
  final List<AgentConversationModePreset> presets;

  /// 当前为下一新 turn 选择的模式。
  final AgentConversationModeId? selectedMode;

  /// 当前选择是否只影响下一新 turn。
  final bool appliesToNextTurn;

  /// loading/error 等状态的补充说明。
  final String? statusMessage;

  /// Provider/Thread 等外部上下文的稳定标识。
  final Object? contextId;

  /// 用户选择新的可用模式时触发。
  final ValueChanged<AgentConversationModeId>? onChanged;

  @override
  State<AgentModeSelector> createState() => _AgentModeSelectorState();
}

class _AgentModeSelectorState extends State<AgentModeSelector> {
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'agent-mode-selector-trigger',
  );
  IdePopoverHandle<void>? _popoverEntry;

  bool get _canOpen =>
      widget.status == AgentModeSelectorStatus.ready &&
      widget.onChanged != null &&
      widget.presets.any((preset) => preset.isSelectable);

  @override
  void didUpdateWidget(covariant AgentModeSelector oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldDismiss =
        _popoverEntry != null &&
        (!_canOpen ||
            oldWidget.contextId != widget.contextId ||
            oldWidget.status != widget.status ||
            oldWidget.selectedMode != widget.selectedMode ||
            !listEquals(oldWidget.presets, widget.presets));
    if (!shouldDismiss) {
      return;
    }
    final entry = _popoverEntry;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_popoverEntry, entry)) {
        entry?.dismiss();
      }
    });
  }

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _togglePopover() {
    final entry = _popoverEntry;
    if (entry != null) {
      entry.dismiss();
      return;
    }
    _showPopover();
  }

  void _showPopover() {
    if (_popoverEntry != null || !_canOpen) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final viewport = mediaQuery.size;
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final triggerHeight = renderBox?.size.height ?? 28;
    final spaceAbove = origin.dy;
    final spaceBelow = viewport.height - origin.dy - triggerHeight;
    final openAbove = spaceAbove > spaceBelow && spaceBelow < 180;
    final availableHeight =
        (openAbove ? spaceAbove : spaceBelow) -
        IdeSpacing.space6 -
        IdeSpacing.space12;
    final width = math.max(
      1.0,
      math.min(
        _agentModeSelectorPopoverPreferredWidth,
        viewport.width - IdeSpacing.space12 * 2,
      ),
    );
    final maxHeight = math.max(
      1.0,
      math.min(_agentModeSelectorPopoverMaxHeight, availableHeight),
    );
    final reduceMotion = mediaQuery.disableAnimations;

    final entry = showIdePopover<void>(
      context: context,
      alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
      anchorAlignment: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      heightConstraint: IdePopoverConstraint.flexible,
      offset: Offset(0, openAbove ? -IdeSpacing.space6 : IdeSpacing.space6),
      margin: const EdgeInsets.all(IdeSpacing.space12),
      allowInvertVertical: false,
      showDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      dismissDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      builder: (context) => _AgentModeSelectorPopover(
        width: width,
        maxHeight: maxHeight,
        presets: widget.presets,
        selectedMode: widget.selectedMode,
        onSelect: _selectPreset,
        onDismiss: () => _popoverEntry?.dismiss(),
      ),
    );
    _popoverEntry = entry;
    setState(() {});
    entry.future.whenComplete(() {
      if (!mounted || !identical(_popoverEntry, entry)) {
        return;
      }
      _popoverEntry = null;
      setState(() {});
      _triggerFocusNode.requestFocus();
    });
  }

  void _selectPreset(AgentConversationModePreset preset) {
    if (!preset.isSelectable) {
      return;
    }
    if (preset.id != widget.selectedMode) {
      widget.onChanged?.call(preset.id);
    }
    _popoverEntry?.dismiss();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.status == AgentModeSelectorStatus.unavailable) {
      return const SizedBox.shrink();
    }

    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final display = _agentModeSelectorDisplay(widget);
    final isLoading = widget.status == AgentModeSelectorStatus.loading;
    final open = _popoverEntry != null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final availableLabelWidth = constraints.hasBoundedWidth
            ? math.max(
                24.0,
                math.min(
                  _agentModeSelectorLabelMaxWidth,
                  constraints.maxWidth - 54,
                ),
              )
            : _agentModeSelectorLabelMaxWidth;
        return _ComposerSelectorTrigger(
          surfaceKey: const ValueKey('agent-mode-selector'),
          tooltip: display.tooltip,
          semanticLabel: display.semanticLabel,
          open: open,
          focusNode: _triggerFocusNode,
          onPressed: _canOpen ? _togglePopover : null,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Semantics(
                label: '对话模式图标',
                excludeSemantics: true,
                child: Icon(
                  Icons.alt_route_rounded,
                  size: 13,
                  color: colors.textTertiary,
                ),
              ),
              const SizedBox(width: IdeSpacing.space4),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: availableLabelWidth),
                child: Text(
                  display.visibleLabel,
                  key: const ValueKey('agent-mode-selector-label'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              const SizedBox(width: IdeSpacing.space4),
              if (isLoading)
                SizedBox(
                  key: const ValueKey('agent-mode-selector-loading'),
                  width: 12,
                  height: 12,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: colors.textTertiary,
                  ),
                )
              else
                AnimatedRotation(
                  turns: open ? 0.5 : 0,
                  duration: MediaQuery.disableAnimationsOf(context)
                      ? Duration.zero
                      : IdeMotion.durationNormal,
                  curve: IdeMotion.curveDefault,
                  child: Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 13,
                    color: colors.textTertiary,
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _AgentModeSelectorPopover extends StatefulWidget {
  const _AgentModeSelectorPopover({
    required this.width,
    required this.maxHeight,
    required this.presets,
    required this.selectedMode,
    required this.onSelect,
    required this.onDismiss,
  });

  final double width;
  final double maxHeight;
  final List<AgentConversationModePreset> presets;
  final AgentConversationModeId? selectedMode;
  final ValueChanged<AgentConversationModePreset> onSelect;
  final VoidCallback onDismiss;

  @override
  State<_AgentModeSelectorPopover> createState() =>
      _AgentModeSelectorPopoverState();
}

class _AgentModeSelectorPopoverState extends State<_AgentModeSelectorPopover> {
  final Map<AgentConversationModeId, FocusNode> _focusNodes =
      <AgentConversationModeId, FocusNode>{};
  AgentConversationModeId? _focusedMode;

  @override
  void initState() {
    super.initState();
    final selectable = widget.presets
        .where((preset) => preset.isSelectable)
        .toList(growable: false);
    _focusedMode = selectable.any((preset) => preset.id == widget.selectedMode)
        ? widget.selectedMode
        : selectable.firstOrNull?.id;
    for (final preset in widget.presets) {
      _focusNodes[preset.id] = FocusNode(
        debugLabel: 'agent-mode-option-${preset.id.rawValue}',
        canRequestFocus: preset.isSelectable && preset.id == _focusedMode,
        onKeyEvent: (node, event) => _handleOptionKey(preset.id, event),
      );
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNodes[_focusedMode]?.requestFocus();
      }
    });
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  KeyEventResult _handleOptionKey(
    AgentConversationModeId currentMode,
    KeyEvent event,
  ) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape) {
      widget.onDismiss();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveFocus(currentMode, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveFocus(currentMode, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveFocus(currentMode, 0, toEnd: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveFocus(currentMode, 0, toEnd: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveFocus(
    AgentConversationModeId currentMode,
    int delta, {
    bool? toEnd,
  }) {
    final selectable = widget.presets
        .where((preset) => preset.isSelectable)
        .toList(growable: false);
    if (selectable.isEmpty) {
      return;
    }
    final currentIndex = selectable.indexWhere(
      (preset) => preset.id == currentMode,
    );
    final targetIndex = toEnd == null
        ? (currentIndex + delta).clamp(0, selectable.length - 1)
        : toEnd
        ? selectable.length - 1
        : 0;
    final targetMode = selectable[targetIndex].id;
    final targetNode = _focusNodes[targetMode];
    if (targetNode == null) {
      return;
    }
    targetNode.canRequestFocus = true;
    targetNode.requestFocus();
    if (currentMode != targetMode) {
      _focusNodes[currentMode]?.canRequestFocus = false;
    }
    _focusedMode = targetMode;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final unknownMode =
        widget.selectedMode?.kind == AgentConversationModeKind.unknown;

    return _ComposerSelectorPanel(
      child: Semantics(
        label: '对话模式选项',
        container: true,
        child: SizedBox(
          key: const ValueKey('agent-mode-selector-popover'),
          width: widget.width,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: widget.maxHeight),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space6),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (unknownMode) ...[
                    Padding(
                      key: const ValueKey('agent-mode-unknown-notice'),
                      padding: const EdgeInsets.fromLTRB(
                        IdeSpacing.space10,
                        IdeSpacing.space6,
                        IdeSpacing.space10,
                        IdeSpacing.space8,
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            Icons.info_outline_rounded,
                            size: 14,
                            color: colors.warning,
                          ),
                          const SizedBox(width: IdeSpacing.space6),
                          Expanded(
                            child: Text(
                              '当前为只读的自定义模式，可选择内置模式覆盖。',
                              style: textStyles.bodySmall.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    Container(height: 1, color: colors.borderSubtle),
                    const SizedBox(height: IdeSpacing.space4),
                  ],
                  for (final preset in widget.presets)
                    _AgentModeSelectorOption(
                      key: ValueKey<String>(
                        'agent-mode-option-${preset.id.rawValue}',
                      ),
                      preset: preset,
                      selected: preset.id == widget.selectedMode,
                      focusNode: _focusNodes[preset.id]!,
                      onPressed: preset.isSelectable
                          ? () => widget.onSelect(preset)
                          : null,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _AgentModeSelectorOption extends StatelessWidget {
  const _AgentModeSelectorOption({
    required this.preset,
    required this.selected,
    required this.focusNode,
    required this.onPressed,
    super.key,
  });

  final AgentConversationModePreset preset;
  final bool selected;
  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final label = _agentModePresetLabel(preset);
    final availability = preset.isSelectable ? '可选择' : '不可选择';

    return PaneInteractiveSurface(
      focusNode: focusNode,
      onPressed: onPressed,
      enabled: onPressed != null,
      selected: selected,
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space10,
        vertical: IdeSpacing.space8,
      ),
      borderRadius: IdeRadius.allSmall,
      backgroundColor: Colors.transparent,
      hoverBackgroundColor: colors.hoverSurface,
      selectedBackgroundColor: colors.selectedSurface,
      focusBorderColor: colors.focusRing,
      semanticLabel: '$label，${selected ? '已选择' : availability}',
      child: Row(
        children: [
          SizedBox(
            width: 16,
            child: selected
                ? Icon(Icons.check_rounded, size: 14, color: colors.accent)
                : null,
          ),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              label,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodyMedium.copyWith(
                color: preset.isSelectable
                    ? colors.textPrimary
                    : colors.textTertiary,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

typedef _AgentModeSelectorDisplay = ({
  String visibleLabel,
  String tooltip,
  String semanticLabel,
});

_AgentModeSelectorDisplay _agentModeSelectorDisplay(AgentModeSelector widget) {
  final statusMessage = widget.statusMessage?.trim();
  switch (widget.status) {
    case AgentModeSelectorStatus.unavailable:
      return (visibleLabel: '', tooltip: '', semanticLabel: '');
    case AgentModeSelectorStatus.loading:
      return (
        visibleLabel: 'Mode…',
        tooltip: statusMessage == null || statusMessage.isEmpty
            ? '正在加载对话模式'
            : statusMessage,
        semanticLabel: 'Mode…，对话模式，正在加载',
      );
    case AgentModeSelectorStatus.error:
      final detail = statusMessage == null || statusMessage.isEmpty
          ? '当前 Provider 无法加载对话模式'
          : statusMessage;
      return (
        visibleLabel: 'Mode unavailable',
        tooltip: detail,
        semanticLabel: 'Mode unavailable，对话模式，$detail',
      );
    case AgentModeSelectorStatus.ready:
      final selectedMode = widget.selectedMode;
      final selectedPreset = _agentModePresetFor(widget.presets, selectedMode);
      final unknownMode =
          selectedMode?.kind == AgentConversationModeKind.unknown;
      final baseLabel = unknownMode
          ? 'Custom mode'
          : selectedPreset == null
          ? _agentModeFallbackLabel(selectedMode)
          : _agentModePresetLabel(selectedPreset);
      final visibleLabel = widget.appliesToNextTurn
          ? '$baseLabel · 下一回合'
          : baseLabel;
      final semanticSuffix = unknownMode
          ? '，当前模式只读'
          : widget.appliesToNextTurn
          ? '，下一回合生效'
          : '';
      final tooltip = unknownMode
          ? '当前模式由 Provider 设置；可选择内置模式覆盖'
          : widget.appliesToNextTurn
          ? '$baseLabel\n将在下一回合生效'
          : baseLabel;
      return (
        visibleLabel: visibleLabel,
        tooltip: tooltip,
        semanticLabel: '$baseLabel，对话模式$semanticSuffix',
      );
  }
}

AgentConversationModePreset? _agentModePresetFor(
  List<AgentConversationModePreset> presets,
  AgentConversationModeId? modeId,
) {
  if (modeId == null) {
    return null;
  }
  for (final preset in presets) {
    if (preset.id == modeId) {
      return preset;
    }
  }
  return null;
}

String _agentModePresetLabel(AgentConversationModePreset preset) {
  final displayName = preset.displayName.trim();
  final baseLabel = displayName.isEmpty
      ? _agentModeFallbackLabel(preset.id)
      : displayName;
  final effort = preset.suggestedReasoningEffort?.trim();
  if (effort == null || effort.isEmpty) {
    return baseLabel;
  }
  return '$baseLabel · ${_agentModeEffortLabel(effort)}';
}

String _agentModeFallbackLabel(AgentConversationModeId? modeId) {
  return switch (modeId?.kind) {
    AgentConversationModeKind.defaultMode => 'Default',
    AgentConversationModeKind.plan => 'Plan',
    AgentConversationModeKind.unknown => 'Custom mode',
    null => 'Mode',
  };
}

String _agentModeEffortLabel(String effort) {
  final normalized = effort.trim().toLowerCase();
  return switch (normalized) {
    'low' => 'Low',
    'medium' => 'Medium',
    'high' => 'High',
    'xhigh' => 'XHigh',
    _ when normalized.isEmpty => effort,
    _ => '${normalized[0].toUpperCase()}${normalized.substring(1)}',
  };
}

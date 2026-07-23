part of '../agent_pane.dart';

const double _composerSelectorPopoverPreferredWidth = 288;
const double _composerSelectorPopoverMaxHeight = 360;
const double _composerSelectorRowHeight = 32;

/// Composer 中统一的模型配置入口与 Popover 协调器。
class _AgentModelConfig extends StatefulWidget {
  const _AgentModelConfig({
    required this.state,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectFastEnabled,
    required this.onResolveCompatibility,
    required this.onRetrySave,
    required this.onPopoverClosed,
  });

  final AgentModelConfigUiState state;
  final Future<bool> Function(String modelId) onSelectModel;
  final Future<bool> Function(String? effort) onSelectReasoningEffort;
  final Future<bool> Function(bool enabled) onSelectFastEnabled;
  final Future<bool> Function() onResolveCompatibility;
  final Future<bool> Function() onRetrySave;
  final VoidCallback onPopoverClosed;

  @override
  State<_AgentModelConfig> createState() => _AgentModelConfigState();
}

class _AgentModelConfigState extends State<_AgentModelConfig> {
  late final ValueNotifier<AgentModelConfigUiState> _popoverState;
  final FocusNode _triggerFocusNode = FocusNode(
    debugLabel: 'agent-model-config-trigger',
  );
  IdePopoverHandle<void>? _popoverEntry;
  String? _desiredExpandedModelId;
  int _runtimeSyncRevision = 0;

  @override
  void initState() {
    super.initState();
    _popoverState = ValueNotifier<AgentModelConfigUiState>(
      widget.state.copyWith(expandedModelId: null),
    );
  }

  @override
  void didUpdateWidget(covariant _AgentModelConfig oldWidget) {
    super.didUpdateWidget(oldWidget);
    var expandedModelId = _desiredExpandedModelId;
    if (widget.state.saveError != null &&
        !identical(widget.state.saveError, oldWidget.state.saveError)) {
      expandedModelId = widget.state.selectedModelId;
    } else if (oldWidget.state.saveError != null &&
        widget.state.saveError == null &&
        widget.state.selectedModelId != oldWidget.state.selectedModelId) {
      // 重试会重新应用失败快照；配置卡随恢复后的目标模型一起移动。
      expandedModelId = widget.state.selectedModelId;
    } else if (expandedModelId != null &&
        !widget.state.models.any((model) => model.id == expandedModelId)) {
      expandedModelId = null;
    }
    _desiredExpandedModelId = expandedModelId;
    final syncRevision = ++_runtimeSyncRevision;
    // Composer 可能正处于 LayoutBuilder 的 build 阶段；延后一帧通知 overlay，
    // 避免 ValueListenableBuilder 在祖先之外被同步标脏。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && syncRevision == _runtimeSyncRevision) {
        _popoverState.value = widget.state.copyWith(
          expandedModelId: _popoverEntry == null
              ? null
              : _desiredExpandedModelId,
        );
      }
    });
  }

  @override
  void dispose() {
    _popoverEntry?.dismiss();
    _triggerFocusNode.dispose();
    _popoverState.dispose();
    super.dispose();
  }

  void _togglePopover() {
    if (_popoverEntry != null) {
      _popoverEntry!.dismiss();
      return;
    }
    _showPopover();
  }

  void _showPopover() {
    if (_popoverEntry != null || widget.state.models.isEmpty) {
      return;
    }
    final mediaQuery = MediaQuery.of(context);
    final viewport = mediaQuery.size;
    final renderBox = context.findRenderObject() as RenderBox?;
    final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
    final triggerHeight = renderBox?.size.height ?? 28;
    final spaceAbove = origin.dy;
    final spaceBelow = viewport.height - origin.dy - triggerHeight;
    final openAbove = spaceAbove > spaceBelow && spaceBelow < 260;
    final availablePopoverHeight =
        (openAbove ? spaceAbove : spaceBelow) -
        IdeSpacing.space6 -
        IdeSpacing.space12;
    final width = math.max(
      1.0,
      math.min(_composerSelectorPopoverPreferredWidth, viewport.width - 24),
    );
    final maxHeight = math.max(
      1.0,
      math.min(_composerSelectorPopoverMaxHeight, availablePopoverHeight),
    );
    final reduceMotion = mediaQuery.disableAnimations;

    _setPopoverState(widget.state.copyWith(expandedModelId: null));
    final entry = showIdePopover<void>(
      context: context,
      alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
      anchorAlignment: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      // 列表使用 shrink-wrap viewport；避免底层 popover 请求其 intrinsic
      // height，并由组件自身的 maxHeight 负责滚动约束。
      heightConstraint: IdePopoverConstraint.flexible,
      offset: Offset(0, openAbove ? -6 : 6),
      margin: const EdgeInsets.all(IdeSpacing.space12),
      allowInvertVertical: false,
      showDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      dismissDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      builder: (context) => _ModelConfigPopover(
        stateListenable: _popoverState,
        width: width,
        maxHeight: maxHeight,
        expansionAlignment: openAbove
            ? Alignment.bottomLeft
            : Alignment.topLeft,
        onSelectModel: _selectModel,
        onSelectReasoningEffort: _selectReasoningEffort,
        onSelectFastEnabled: _selectFastEnabled,
        onResolveCompatibility: () {
          unawaited(widget.onResolveCompatibility());
        },
        onRetrySave: () {
          unawaited(widget.onRetrySave());
        },
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
      _desiredExpandedModelId = null;
      _popoverState.value = widget.state.copyWith(expandedModelId: null);
      widget.onPopoverClosed();
      setState(() {});
      _triggerFocusNode.requestFocus();
    });
  }

  void _selectModel(AgentModelInfo model) {
    final state = _popoverState.value;
    if (!model.enabled) {
      return;
    }
    if (state.selectedModelId == model.id) {
      _setPopoverState(state.copyWith(expandedModelId: model.id));
      return;
    }
    final preference = state.effectivePreference(model);
    _setPopoverState(
      state.copyWith(
        selectedModelId: model.id,
        expandedModelId: model.id,
        selectedReasoningEffort: preference.reasoningEffort,
        selectedServiceTierId: preference.serviceTierId,
        preferences: <String, AgentModelPreference>{
          ...state.preferences,
          model.id: preference,
        },
        compatibilityConflict: null,
        saveError: null,
      ),
    );
    unawaited(_commitModelSelection(model.id));
  }

  Future<void> _commitModelSelection(String modelId) async {
    final success = await widget.onSelectModel(modelId);
    if (!mounted || success) {
      return;
    }
    // 保存失败时 ViewModel 已完成回滚；下一帧合并其确认态并恢复展开位置。
    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    _setPopoverState(
      widget.state.copyWith(expandedModelId: widget.state.selectedModelId),
    );
  }

  void _selectReasoningEffort(String effort) {
    final state = _popoverState.value;
    if (state.selectedFastEnabled && effort.toLowerCase() == 'xhigh') {
      unawaited(widget.onSelectReasoningEffort(effort));
      return;
    }
    final model = state.selectedModel;
    final preferences = Map<String, AgentModelPreference>.from(
      state.preferences,
    );
    if (model != null) {
      final current = state.effectivePreference(model);
      preferences[model.id] = AgentModelPreference(
        modelId: model.id,
        reasoningEffort: effort,
        fastEnabled: current.fastEnabled,
        serviceTierId: current.serviceTierId,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    _setPopoverState(
      state.copyWith(
        selectedReasoningEffort: effort,
        preferences: preferences,
        compatibilityConflict: null,
        saveError: null,
      ),
    );
    unawaited(widget.onSelectReasoningEffort(effort));
  }

  void _selectFastEnabled(bool enabled) {
    final state = _popoverState.value;
    if (enabled && state.selectedReasoningEffort?.toLowerCase() == 'xhigh') {
      unawaited(widget.onSelectFastEnabled(true));
      return;
    }
    final model = state.selectedModel;
    final fastTier = model == null ? null : agentFastServiceTier(model);
    final preferences = Map<String, AgentModelPreference>.from(
      state.preferences,
    );
    if (model != null) {
      final current = state.effectivePreference(model);
      preferences[model.id] = AgentModelPreference(
        modelId: model.id,
        reasoningEffort: current.reasoningEffort,
        fastEnabled: enabled,
        serviceTierId: enabled ? fastTier?.id : null,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    _setPopoverState(
      state.copyWith(
        selectedServiceTierId: enabled ? fastTier?.id : null,
        preferences: preferences,
        compatibilityConflict: null,
        saveError: null,
      ),
    );
    unawaited(widget.onSelectFastEnabled(enabled));
  }

  void _setPopoverState(AgentModelConfigUiState state) {
    _desiredExpandedModelId = state.expandedModelId;
    _popoverState.value = state;
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final displayState = _popoverEntry == null
        ? widget.state
        : _popoverState.value;
    return _ModelConfigTrigger(
      state: displayState,
      open: _popoverEntry != null,
      focusNode: _triggerFocusNode,
      onPressed: widget.state.models.isEmpty ? null : _togglePopover,
    );
  }
}

class _ModelConfigTrigger extends StatelessWidget {
  const _ModelConfigTrigger({
    required this.state,
    required this.open,
    required this.focusNode,
    required this.onPressed,
  });

  final AgentModelConfigUiState state;
  final bool open;
  final FocusNode focusNode;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final selectedModel = state.selectedModel;
    final modelLabel = selectedModel?.displayName ?? '模型';
    final effortLabel = _reasoningEffortLabel(
      state.selectedReasoningEffort,
      selectedModel?.supportedReasoningEfforts,
    );
    final tooltip = StringBuffer(modelLabel);
    if (effortLabel != null) {
      tooltip.write('\n思考程度：$effortLabel');
    }
    tooltip.write('\nFast：${state.selectedFastEnabled ? '已开启' : '已关闭'}');
    if (state.appliesNextTurn) {
      tooltip.write('\n配置将在下一回合生效');
    }

    return _ComposerSelectorTrigger(
      surfaceKey: const ValueKey('agent-model-selector'),
      tooltip: tooltip.toString(),
      semanticLabel: '$modelLabel，模型配置',
      open: open,
      focusNode: focusNode,
      onPressed: onPressed,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 只限制模型名本身；外层保持无界，避免触发器在高 DPI 下
          // 扩张到最大宽度。
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              modelLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (effortLabel != null) ...[
            const SizedBox(width: IdeSpacing.space4),
            Text(
              '· $effortLabel',
              maxLines: 1,
              style: textStyles.bodySmall.copyWith(color: colors.textTertiary),
            ),
          ],
          if (state.selectedFastEnabled) ...[
            const SizedBox(width: IdeSpacing.space4),
            Icon(
              Icons.bolt_rounded,
              key: const ValueKey('agent-model-fast-enabled'),
              size: 13,
              color: colors.warning,
            ),
          ],
          const SizedBox(width: IdeSpacing.space4),
          if (state.isRefreshing)
            SizedBox(
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
  }
}

/// Composer 选择器共用触发器：模式、模型与权限使用同一套尺寸和交互反馈。
class _ComposerSelectorTrigger extends StatelessWidget {
  const _ComposerSelectorTrigger({
    required this.surfaceKey,
    required this.tooltip,
    required this.semanticLabel,
    required this.open,
    required this.focusNode,
    required this.onPressed,
    required this.child,
  });

  final Key surfaceKey;
  final String tooltip;
  final String semanticLabel;
  final bool open;
  final FocusNode focusNode;
  final VoidCallback? onPressed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeTooltip(
      // 弹层打开后禁用 tooltip，避免延迟提示覆盖选项。
      message: tooltip,
      enabled: !open,
      child: PaneInteractiveSurface(
        key: surfaceKey,
        focusNode: focusNode,
        onPressed: onPressed,
        enabled: onPressed != null,
        selected: open,
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
        borderRadius: IdeRadius.allSmall,
        backgroundColor: Colors.transparent,
        hoverBackgroundColor: colors.border.withValues(alpha: 0.2),
        pressedBackgroundColor: colors.border.withValues(alpha: 0.32),
        selectedBackgroundColor: colors.frame.withValues(alpha: 0.72),
        focusBorderColor: colors.focusRing,
        selectedBorderColor: colors.borderSubtle,
        semanticLabel: semanticLabel,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: IdeSpacing.space2),
              child: child,
            ),
            Positioned(
              bottom: 0,
              child: AnimatedContainer(
                duration: MediaQuery.disableAnimationsOf(context)
                    ? Duration.zero
                    : IdeMotion.durationNormal,
                curve: IdeMotion.curveDefault,
                width: open ? 18 : 0,
                height: 2,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: IdeRadius.allSmall,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Composer 选择器共用弹层表面。
///
/// 使用与未展开触发器相同的面板色和小圆角，只保留细边界用于
/// 区分 overlay，避免弹层呈现为另一套重卡片视觉。
class _ComposerSelectorPanel extends StatelessWidget {
  const _ComposerSelectorPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PanelCard(
      color: colors.panel,
      borderColor: colors.borderSubtle,
      borderRadius: IdeRadius.allSmall,
      boxShadow: const <BoxShadow>[],
      child: child,
    );
  }
}

class _ModelConfigPopover extends StatefulWidget {
  const _ModelConfigPopover({
    required this.stateListenable,
    required this.width,
    required this.maxHeight,
    required this.expansionAlignment,
    required this.onSelectModel,
    required this.onSelectReasoningEffort,
    required this.onSelectFastEnabled,
    required this.onResolveCompatibility,
    required this.onRetrySave,
    required this.onDismiss,
  });

  final ValueListenable<AgentModelConfigUiState> stateListenable;
  final double width;
  final double maxHeight;
  final Alignment expansionAlignment;
  final ValueChanged<AgentModelInfo> onSelectModel;
  final ValueChanged<String> onSelectReasoningEffort;
  final ValueChanged<bool> onSelectFastEnabled;
  final VoidCallback onResolveCompatibility;
  final VoidCallback onRetrySave;
  final VoidCallback onDismiss;

  @override
  State<_ModelConfigPopover> createState() => _ModelConfigPopoverState();
}

class _ModelConfigPopoverState extends State<_ModelConfigPopover> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, FocusNode> _modelFocusNodes = <String, FocusNode>{};
  final Map<String, GlobalKey> _configKeys = <String, GlobalKey>{};
  String? _focusedModelId;
  String? _lastExpandedModelId;
  DateTime? _lastWheelScrollAt;

  @override
  void initState() {
    super.initState();
    widget.stateListenable.addListener(_handleStateChanged);
    _syncModelFocusNodes(widget.stateListenable.value);
    WidgetsBinding.instance.addPostFrameCallback((_) => _focusInitialModel());
  }

  @override
  void dispose() {
    widget.stateListenable.removeListener(_handleStateChanged);
    _scrollController.dispose();
    for (final node in _modelFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _handleStateChanged() {
    final state = widget.stateListenable.value;
    _syncModelFocusNodes(state);
    if (state.expandedModelId != _lastExpandedModelId) {
      _lastExpandedModelId = state.expandedModelId;
      _ensureExpandedConfigVisible(state.expandedModelId);
    }
  }

  void _syncModelFocusNodes(AgentModelConfigUiState state) {
    final ids = state.models.map((model) => model.id).toSet();
    final removed = _modelFocusNodes.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _modelFocusNodes.remove(id)?.dispose();
      _configKeys.remove(id);
    }
    for (final model in state.models) {
      _modelFocusNodes.putIfAbsent(
        model.id,
        () => FocusNode(
          debugLabel: 'agent-model-option-${model.id}',
          onKeyEvent: (node, event) => _handleModelKey(model.id, event),
        ),
      );
      _configKeys.putIfAbsent(
        model.id,
        () => GlobalKey(debugLabel: 'agent-model-config-${model.id}'),
      );
    }
    final enabledIds = state.models
        .where((model) => model.enabled)
        .map((model) => model.id)
        .toList(growable: false);
    if (!enabledIds.contains(_focusedModelId)) {
      _focusedModelId = enabledIds.contains(state.selectedModelId)
          ? state.selectedModelId
          : enabledIds.firstOrNull;
    }
    for (final entry in _modelFocusNodes.entries) {
      entry.value.canRequestFocus = entry.key == _focusedModelId;
    }
  }

  void _focusInitialModel() {
    if (!mounted) {
      return;
    }
    _modelFocusNodes[_focusedModelId]?.requestFocus();
  }

  KeyEventResult _handleModelKey(String modelId, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.arrowDown) {
      _moveModelFocus(modelId, 1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.arrowUp) {
      _moveModelFocus(modelId, -1);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.home) {
      _moveModelFocus(modelId, 0, toEnd: false);
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.end) {
      _moveModelFocus(modelId, 0, toEnd: true);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _moveModelFocus(String currentId, int delta, {bool? toEnd}) {
    final enabled = widget.stateListenable.value.models
        .where((model) => model.enabled)
        .toList(growable: false);
    if (enabled.isEmpty) {
      return;
    }
    final currentIndex = enabled.indexWhere((model) => model.id == currentId);
    final targetIndex = toEnd == null
        ? (currentIndex + delta).clamp(0, enabled.length - 1)
        : toEnd
        ? enabled.length - 1
        : 0;
    final targetId = enabled[targetIndex].id;
    final targetNode = _modelFocusNodes[targetId];
    if (targetNode == null) {
      return;
    }
    targetNode.canRequestFocus = true;
    targetNode.requestFocus();
    if (currentId != targetId) {
      _modelFocusNodes[currentId]?.canRequestFocus = false;
    }
    _focusedModelId = targetId;
  }

  void _ensureExpandedConfigVisible(String? modelId) {
    if (modelId == null) {
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final delay = reduceMotion
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 190);
    Future<void>.delayed(delay, () {
      if (!mounted || widget.stateListenable.value.expandedModelId != modelId) {
        return;
      }
      final lastWheelScrollAt = _lastWheelScrollAt;
      if (lastWheelScrollAt != null &&
          DateTime.now().difference(lastWheelScrollAt) <
              const Duration(milliseconds: 320)) {
        return;
      }
      final targetContext = _configKeys[modelId]?.currentContext;
      if (targetContext == null || !targetContext.mounted) {
        return;
      }
      Scrollable.ensureVisible(
        targetContext,
        duration: reduceMotion ? Duration.zero : IdeMotion.durationNormal,
        curve: Curves.easeOutCubic,
        alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Focus(
      canRequestFocus: false,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          widget.onDismiss();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        container: true,
        explicitChildNodes: true,
        label: '模型配置',
        child: ValueListenableBuilder<AgentModelConfigUiState>(
          valueListenable: widget.stateListenable,
          builder: (context, state, _) {
            return AnimatedSize(
              key: const ValueKey('agent-model-config-popover'),
              duration: reduceMotion
                  ? const Duration(milliseconds: 80)
                  : IdeMotion.durationNormal,
              curve: Curves.easeOutCubic,
              alignment: widget.expansionAlignment,
              child: SizedBox(
                width: widget.width,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: widget.maxHeight),
                  child: _ComposerSelectorPanel(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (state.appliesNextTurn)
                          _NextTurnModelConfigBanner(colors: colors),
                        if (state.selectionNotice != null)
                          _ModelSelectionNoticeBanner(
                            message: state.selectionNotice!,
                            colors: colors,
                          ),
                        _ModelListLabel(
                          refreshing: state.isRefreshing,
                          refreshError: state.refreshError,
                        ),
                        Divider(
                          height: 1,
                          thickness: 1,
                          color: colors.borderSubtle.withValues(alpha: 0.6),
                        ),
                        Flexible(
                          child: Listener(
                            onPointerSignal: (event) {
                              if (event is PointerScrollEvent) {
                                _lastWheelScrollAt = DateTime.now();
                              }
                            },
                            child: state.models.isEmpty
                                ? Padding(
                                    padding: IdeSpacing.all16,
                                    child: Center(
                                      child: Text(
                                        state.isRefreshing
                                            ? '正在加载模型…'
                                            : '暂无可用模型',
                                        style: IdeTextStyles.of(context)
                                            .bodySmall
                                            .copyWith(
                                              color: colors.textSecondary,
                                            ),
                                      ),
                                    ),
                                  )
                                : ListView.builder(
                                    key: const ValueKey('agent-model-list'),
                                    controller: _scrollController,
                                    shrinkWrap: true,
                                    padding: IdeSpacing.all4,
                                    itemCount: state.models.length,
                                    itemBuilder: (context, index) {
                                      final model = state.models[index];
                                      return RepaintBoundary(
                                        key: ValueKey<String>(model.id),
                                        child: _ModelListItem(
                                          model: model,
                                          selected:
                                              state.selectedModelId == model.id,
                                          expanded:
                                              state.expandedModelId == model.id,
                                          saving: state.savingModelIds.contains(
                                            model.id,
                                          ),
                                          state: state,
                                          focusNode:
                                              _modelFocusNodes[model.id]!,
                                          configKey: _configKeys[model.id]!,
                                          onSelect: () =>
                                              widget.onSelectModel(model),
                                          onReasoningChanged:
                                              widget.onSelectReasoningEffort,
                                          onFastChanged:
                                              widget.onSelectFastEnabled,
                                          onResolveCompatibility:
                                              widget.onResolveCompatibility,
                                          onRetrySave: widget.onRetrySave,
                                        ),
                                      );
                                    },
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _NextTurnModelConfigBanner extends StatelessWidget {
  const _NextTurnModelConfigBanner({required this.colors});

  final IdeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent-model-next-turn-banner'),
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space10),
      color: colors.info.withValues(alpha: 0.1),
      child: Row(
        children: [
          Icon(Icons.info_outline_rounded, size: 14, color: colors.info),
          const SizedBox(width: IdeSpacing.space6),
          Text(
            '配置将在下一回合生效',
            style: IdeTextStyles.of(context).bodySmall.copyWith(
              color: colors.info,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelSelectionNoticeBanner extends StatelessWidget {
  const _ModelSelectionNoticeBanner({
    required this.message,
    required this.colors,
  });

  final String message;
  final IdeColors colors;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('agent-model-auto-switch-notice'),
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space10,
        vertical: IdeSpacing.space6,
      ),
      color: colors.info.withValues(alpha: 0.1),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: colors.info,
            ),
          ),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              message,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: IdeTextStyles.of(
                context,
              ).bodySmall.copyWith(color: colors.info),
            ),
          ),
        ],
      ),
    );
  }
}

class _ModelListLabel extends StatelessWidget {
  const _ModelListLabel({required this.refreshing, required this.refreshError});

  final bool refreshing;
  final String? refreshError;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return SizedBox(
      height: 28,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
        child: Row(
          children: [
            Expanded(
              child: Text(
                '选择模型',
                style: IdeTextStyles.of(context).bodySmall.copyWith(
                  color: colors.textTertiary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (refreshing)
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 1.5,
                  color: colors.textSecondary,
                ),
              )
            else if (refreshError != null)
              IdeTooltip(
                message: refreshError!,
                child: Icon(
                  Icons.info_outline_rounded,
                  size: 14,
                  color: colors.warning,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ModelListItem extends StatelessWidget {
  const _ModelListItem({
    required this.model,
    required this.selected,
    required this.expanded,
    required this.saving,
    required this.state,
    required this.focusNode,
    required this.configKey,
    required this.onSelect,
    required this.onReasoningChanged,
    required this.onFastChanged,
    required this.onResolveCompatibility,
    required this.onRetrySave,
  });

  final AgentModelInfo model;
  final bool selected;
  final bool expanded;
  final bool saving;
  final AgentModelConfigUiState state;
  final FocusNode focusNode;
  final GlobalKey configKey;
  final VoidCallback onSelect;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<bool> onFastChanged;
  final VoidCallback onResolveCompatibility;
  final VoidCallback onRetrySave;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final row = PaneInteractiveSurface(
      key: ValueKey<String>('agent-model-option-${model.id}'),
      focusNode: focusNode,
      onPressed: model.enabled ? onSelect : null,
      enabled: model.enabled,
      selected: selected,
      height: _composerSelectorRowHeight,
      padding: const EdgeInsets.symmetric(horizontal: IdeSpacing.space8),
      borderRadius: IdeRadius.allSmall,
      selectedBackgroundColor: colors.border.withValues(alpha: 0.2),
      focusBorderColor: colors.focusRing,
      semanticLabel:
          '${model.displayName}${selected ? '，已选择' : ''}${model.enabled ? '' : '，不可用'}',
      child: Row(
        children: [
          SizedBox(
            width: 14,
            child: selected && model.enabled
                ? Icon(Icons.check_rounded, size: 14, color: colors.accent)
                : null,
          ),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              model.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(
                color: model.enabled ? colors.textPrimary : colors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          if (saving)
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: colors.textSecondary,
              ),
            )
          else if (!model.enabled)
            Icon(
              Icons.info_outline_rounded,
              size: 14,
              color: colors.textTertiary,
            ),
        ],
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeTooltip(
          message: model.enabled
              ? model.displayName
              : model.unavailableReason ?? '该模型当前不可用',
          child: row,
        ),
        _AnimatedModelExpansion(
          expanded: expanded,
          child: KeyedSubtree(
            key: configKey,
            child: _ModelInlineConfig(
              model: model,
              state: state,
              saving: saving,
              onReasoningChanged: onReasoningChanged,
              onFastChanged: onFastChanged,
              onResolveCompatibility: onResolveCompatibility,
              onRetrySave: onRetrySave,
            ),
          ),
        ),
      ],
    );
  }
}

class _AnimatedModelExpansion extends StatelessWidget {
  const _AnimatedModelExpansion({required this.expanded, required this.child});

  final bool expanded;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final duration = reduceMotion
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 180);
    return AnimatedSwitcher(
      duration: duration,
      reverseDuration: reduceMotion
          ? const Duration(milliseconds: 80)
          : IdeMotion.durationFast,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      layoutBuilder: (currentChild, previousChildren) => Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[...previousChildren, ?currentChild],
      ),
      transitionBuilder: (child, animation) {
        final faded = FadeTransition(opacity: animation, child: child);
        final entered = reduceMotion
            ? faded
            : SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0, -0.025),
                  end: Offset.zero,
                ).animate(animation),
                child: faded,
              );
        return ClipRect(
          child: SizeTransition(
            sizeFactor: animation,
            alignment: Alignment.topCenter,
            child: entered,
          ),
        );
      },
      child: expanded
          ? _ModelExpansionInteractionGate(
              key: const ValueKey('model-config-expanded'),
              duration: duration,
              child: child,
            )
          : const SizedBox.shrink(key: ValueKey('model-config-collapsed')),
    );
  }
}

class _ModelExpansionInteractionGate extends StatefulWidget {
  const _ModelExpansionInteractionGate({
    required this.duration,
    required this.child,
    super.key,
  });

  final Duration duration;
  final Widget child;

  @override
  State<_ModelExpansionInteractionGate> createState() =>
      _ModelExpansionInteractionGateState();
}

class _ModelExpansionInteractionGateState
    extends State<_ModelExpansionInteractionGate> {
  Timer? _timer;
  bool _interactive = false;

  @override
  void initState() {
    super.initState();
    _timer = Timer(widget.duration, () {
      if (mounted) {
        setState(() => _interactive = true);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(ignoring: !_interactive, child: widget.child);
  }
}

class _ModelInlineConfig extends StatelessWidget {
  const _ModelInlineConfig({
    required this.model,
    required this.state,
    required this.saving,
    required this.onReasoningChanged,
    required this.onFastChanged,
    required this.onResolveCompatibility,
    required this.onRetrySave,
  });

  final AgentModelInfo model;
  final AgentModelConfigUiState state;
  final bool saving;
  final ValueChanged<String> onReasoningChanged;
  final ValueChanged<bool> onFastChanged;
  final VoidCallback onResolveCompatibility;
  final VoidCallback onRetrySave;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final efforts = state.supportsReasoningOptions
        ? model.supportedReasoningEfforts
        : const <AgentModelReasoningEffort>[];
    final fastTier = state.supportsServiceTierSelection
        ? agentFastServiceTier(model)
        : null;
    final fastSupported = fastTier != null && fastTier.enabled;
    final fastEnabled =
        fastSupported && state.selectedServiceTierId == fastTier.id;
    final conflict = state.compatibilityConflict?.modelId == model.id
        ? state.compatibilityConflict
        : null;
    final saveError = state.saveError?.modelId == model.id
        ? state.saveError
        : null;

    return Padding(
      key: ValueKey<String>('agent-model-inline-config-${model.id}'),
      padding: const EdgeInsets.fromLTRB(
        IdeSpacing.space4,
        IdeSpacing.space2,
        IdeSpacing.space4,
        IdeSpacing.space4,
      ),
      child: PanelCard(
        color: colors.surfaceElevated,
        borderColor: colors.borderSubtle,
        borderRadius: IdeRadius.allSmall,
        boxShadow: const <BoxShadow>[],
        child: Padding(
          padding: IdeSpacing.all8,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (efforts.isEmpty)
                SizedBox(
                  height: 28,
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '该模型未提供可配置的思考程度',
                      style: textStyles.bodySmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                )
              else
                Row(
                  children: [
                    SizedBox(
                      width: 52,
                      child: Text(
                        '思考程度',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: IdeSpacing.space6),
                    Expanded(
                      child: _ReasoningSegmentControl(
                        efforts: efforts,
                        selectedEffort:
                            state.selectedReasoningEffort ??
                            efforts.first.effort,
                        onChanged: onReasoningChanged,
                      ),
                    ),
                    if (saving) ...[
                      const SizedBox(width: IdeSpacing.space6),
                      SizedBox(
                        width: 10,
                        height: 10,
                        child: CircularProgressIndicator(
                          strokeWidth: 1.4,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
              const SizedBox(height: IdeSpacing.space4),
              _FastConfigRow(
                model: model,
                enabled: fastSupported,
                value: fastEnabled,
                unavailableReason: fastTier?.unavailableReason ?? '该模型不支持 Fast',
                onChanged: onFastChanged,
              ),
              if (conflict != null) ...[
                const SizedBox(height: IdeSpacing.space8),
                _ModelConfigInlineAlert(
                  key: const ValueKey('agent-model-compatibility-alert'),
                  icon: Icons.warning_amber_rounded,
                  message: conflict.message,
                  actionLabel: conflict.actionLabel,
                  color: colors.warning,
                  onAction: onResolveCompatibility,
                ),
              ],
              if (saveError != null) ...[
                const SizedBox(height: IdeSpacing.space8),
                _ModelConfigInlineAlert(
                  key: const ValueKey('agent-model-save-error'),
                  icon: Icons.error_outline_rounded,
                  message: saveError.message,
                  actionLabel: '重试',
                  color: colors.error,
                  onAction: onRetrySave,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FastConfigRow extends StatelessWidget {
  const _FastConfigRow({
    required this.model,
    required this.enabled,
    required this.value,
    required this.unavailableReason,
    required this.onChanged,
  });

  final AgentModelInfo model;
  final bool enabled;
  final bool value;
  final String unavailableReason;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final content = SizedBox(
      height: 32,
      child: Row(
        children: [
          Icon(
            Icons.bolt_rounded,
            size: 14,
            color: value ? colors.warning : colors.textTertiary,
          ),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              'Fast',
              style: IdeTextStyles.of(context).bodyMedium.copyWith(
                color: enabled ? colors.textPrimary : colors.textTertiary,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Semantics(
            label: '${model.displayName}，Fast，${value ? '已开启' : '已关闭'}',
            child: sf.Switch(
              key: ValueKey<String>('agent-fast-switch-${model.id}'),
              value: value,
              enabled: enabled,
              onChanged: enabled ? onChanged : null,
            ),
          ),
        ],
      ),
    );
    return enabled
        ? content
        : IdeTooltip(message: unavailableReason, child: content);
  }
}

class _ModelConfigInlineAlert extends StatelessWidget {
  const _ModelConfigInlineAlert({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.color,
    required this.onAction,
    super.key,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final Color color;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: IdeSpacing.space8,
        vertical: IdeSpacing.space6,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.09),
        border: Border.all(color: color.withValues(alpha: 0.28)),
        borderRadius: IdeRadius.allSmall,
      ),
      child: Row(
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            child: Text(
              message,
              style: IdeTextStyles.of(context).bodySmall.copyWith(color: color),
            ),
          ),
          const SizedBox(width: IdeSpacing.space6),
          sf.GhostButton(
            key: ValueKey<String>('agent-model-alert-$actionLabel'),
            size: sf.ButtonSize.xSmall,
            onPressed: onAction,
            child: Text(actionLabel),
          ),
        ],
      ),
    );
  }
}

class _ReasoningSegmentControl extends StatefulWidget {
  const _ReasoningSegmentControl({
    required this.efforts,
    required this.selectedEffort,
    required this.onChanged,
  });

  final List<AgentModelReasoningEffort> efforts;
  final String selectedEffort;
  final ValueChanged<String> onChanged;

  @override
  State<_ReasoningSegmentControl> createState() =>
      _ReasoningSegmentControlState();
}

class _ReasoningSegmentControlState extends State<_ReasoningSegmentControl> {
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  @override
  void initState() {
    super.initState();
    _syncFocusNodes();
  }

  @override
  void didUpdateWidget(covariant _ReasoningSegmentControl oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncFocusNodes();
  }

  @override
  void dispose() {
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  void _syncFocusNodes() {
    final ids = widget.efforts.map((effort) => effort.effort).toSet();
    final removed = _focusNodes.keys
        .where((id) => !ids.contains(id))
        .toList(growable: false);
    for (final id in removed) {
      _focusNodes.remove(id)?.dispose();
    }
    for (final effort in widget.efforts) {
      _focusNodes.putIfAbsent(
        effort.effort,
        () => FocusNode(
          debugLabel: 'agent-reasoning-${effort.effort}',
          onKeyEvent: (node, event) => _handleKey(effort.effort, event),
        ),
      );
    }
    for (final entry in _focusNodes.entries) {
      entry.value.canRequestFocus = entry.key == widget.selectedEffort;
    }
  }

  KeyEventResult _handleKey(String effortId, KeyEvent event) {
    if (event is! KeyDownEvent ||
        (event.logicalKey != LogicalKeyboardKey.arrowLeft &&
            event.logicalKey != LogicalKeyboardKey.arrowRight)) {
      return KeyEventResult.ignored;
    }
    final index = widget.efforts.indexWhere(
      (effort) => effort.effort == effortId,
    );
    final delta = event.logicalKey == LogicalKeyboardKey.arrowLeft ? -1 : 1;
    final targetIndex = (index + delta).clamp(0, widget.efforts.length - 1);
    final target = widget.efforts[targetIndex].effort;
    if (target == effortId) {
      return KeyEventResult.handled;
    }
    final targetNode = _focusNodes[target]!;
    targetNode.canRequestFocus = true;
    targetNode.requestFocus();
    _focusNodes[effortId]?.canRequestFocus = false;
    widget.onChanged(target);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final selectedIndex = widget.efforts.indexWhere(
      (effort) => effort.effort == widget.selectedEffort,
    );
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: '思考程度',
      child: Container(
        key: const ValueKey('agent-reasoning-segment-control'),
        height: 28,
        padding: const EdgeInsets.all(IdeSpacing.space2),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border.all(color: colors.borderSubtle),
          borderRadius: IdeRadius.allMedium,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final segmentWidth = constraints.maxWidth / widget.efforts.length;
            return Stack(
              children: [
                if (selectedIndex >= 0)
                  AnimatedPositioned(
                    duration: reduceMotion
                        ? Duration.zero
                        : const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    left: segmentWidth * selectedIndex,
                    top: 0,
                    bottom: 0,
                    width: segmentWidth,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: colors.surfaceOverlay,
                        borderRadius: IdeRadius.allSmall,
                      ),
                    ),
                  ),
                Row(
                  children: [
                    for (final effort in widget.efforts)
                      Expanded(
                        child: Semantics(
                          selected: effort.effort == widget.selectedEffort,
                          inMutuallyExclusiveGroup: true,
                          label: _reasoningEffortLabel(
                            effort.effort,
                            widget.efforts,
                          ),
                          child: PaneInteractiveSurface(
                            key: ValueKey<String>(
                              'agent-reasoning-option-${effort.effort}',
                            ),
                            focusNode: _focusNodes[effort.effort],
                            height: 24,
                            onPressed: () => widget.onChanged(effort.effort),
                            selected: effort.effort == widget.selectedEffort,
                            selectedBackgroundColor: Colors.transparent,
                            hoverBackgroundColor: colors.border.withValues(
                              alpha: 0.22,
                            ),
                            pressedBackgroundColor: colors.border.withValues(
                              alpha: 0.34,
                            ),
                            borderRadius: IdeRadius.allSmall,
                            semanticLabel: null,
                            child: Center(
                              child: AnimatedDefaultTextStyle(
                                duration: reduceMotion
                                    ? Duration.zero
                                    : IdeMotion.durationFast,
                                style: IdeTextStyles.of(context).bodySmall
                                    .copyWith(
                                      color:
                                          effort.effort == widget.selectedEffort
                                          ? colors.textPrimary
                                          : colors.textSecondary,
                                      fontSize: 12,
                                      fontWeight:
                                          effort.effort == widget.selectedEffort
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                    ),
                                child: Text(
                                  _reasoningEffortLabel(
                                        effort.effort,
                                        widget.efforts,
                                      ) ??
                                      effort.effort,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

String? _reasoningEffortLabel(
  String? effort,
  List<AgentModelReasoningEffort>? options,
) {
  if (effort == null) {
    return null;
  }
  final normalized = effort.trim().toLowerCase();
  final known = switch (normalized) {
    'none' => '无',
    'minimal' => '最低',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    _ => null,
  };
  if (known != null) {
    return known;
  }
  for (final option in options ?? const <AgentModelReasoningEffort>[]) {
    if (option.effort == effort) {
      return option.description ?? effort;
    }
  }
  return effort;
}

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

    // 打开时直接展开当前已选模型的额外配置（思考程度、Fast 等），
    // 避免用户还要再点一次已选项才能看到。
    _setPopoverState(
      widget.state.copyWith(expandedModelId: widget.state.selectedModelId),
    );
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
      builder: (context) => MediaQuery(
        data: mediaQuery,
        child: _ModelConfigPopover(
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
    final refreshError = state.refreshError;
    final modelLabel =
        selectedModel?.displayName ??
        (refreshError == null
            ? context.l10n.agentModel
            : context.l10n.agentModelLoadFailed);
    final effortRaw = state.selectedReasoningEffort?.trim();
    final effortLabel = (effortRaw == null || effortRaw.isEmpty)
        ? null
        : effortRaw;
    final fastTier = selectedModel != null && state.supportsServiceTierSelection
        ? agentFastServiceTier(selectedModel)
        : null;
    final fastSupported = fastTier != null && fastTier.enabled;
    final tooltip = StringBuffer(modelLabel);
    if (effortLabel != null) {
      tooltip.write('\n${context.l10n.agentReasoningEffortValue(effortLabel)}');
    }
    if (fastSupported) {
      tooltip.write(
        '\n${context.l10n.agentFastValue(state.selectedFastEnabled ? context.l10n.agentFastOn : context.l10n.agentFastOff)}',
      );
    }
    if (state.appliesNextTurn) {
      tooltip.write('\n${context.l10n.agentConfigNextTurn}');
    }
    if (refreshError != null) {
      tooltip.write('\n$refreshError');
    }

    return _ComposerSelectorTrigger(
      surfaceKey: const ValueKey('agent-model-selector'),
      tooltip: tooltip.toString(),
      semanticLabel: refreshError == null
          ? context.l10n.agentModelConfigSemantic(modelLabel)
          : context.l10n.agentModelConfigErrorSemantic(
              modelLabel,
              refreshError,
            ),
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
              style: textStyles.identifier.copyWith(
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
          if (refreshError != null) ...[
            const SizedBox(width: IdeSpacing.space4),
            Icon(
              Icons.error_outline_rounded,
              key: const ValueKey('agent-model-refresh-error'),
              size: 13,
              color: colors.error,
            ),
          ],
          const SizedBox(width: IdeSpacing.space4),
          if (state.isRefreshing)
            IdeBusySpinner(
              size: 12,
              strokeWidth: 1.5,
              color: colors.textTertiary,
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
        semanticLabel: semanticLabel,
        child: child,
      ),
    );
  }
}

/// Composer 选择器共用弹层表面。
///
/// 与 [sf.SelectPopup] 自带卡统一：同一张 shadcn surface 卡（底色
/// `colorScheme.card`、1px muted 边框、零内边距），避免选择弹层再叠一层
/// 独立卡片造成「两层」视觉。非 SelectPopup 的 picker（skill/mention/
/// slash/model 列表）使用本表面，与 SelectPopup 路径视觉一致。
class _ComposerSelectorPanel extends StatelessWidget {
  const _ComposerSelectorPanel({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return sf.Card(
      padding: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
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
  Timer? _ensureVisibleTimer;

  @override
  void initState() {
    super.initState();
    widget.stateListenable.addListener(_handleStateChanged);
    _syncModelFocusNodes(widget.stateListenable.value);
    // 打开时若已有展开目标（通常为当前选中模型），首帧后滚入视野。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final expandedId = widget.stateListenable.value.expandedModelId;
      if (expandedId != null) {
        _lastExpandedModelId = expandedId;
        _ensureExpandedConfigVisible(expandedId);
      }
      _focusInitialModel();
    });
  }

  @override
  void dispose() {
    widget.stateListenable.removeListener(_handleStateChanged);
    _ensureVisibleTimer?.cancel();
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
    _ensureVisibleTimer?.cancel();
    _ensureVisibleTimer = null;
    if (modelId == null) {
      return;
    }
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final delay = reduceMotion
        ? const Duration(milliseconds: 80)
        : const Duration(milliseconds: 190);
    _ensureVisibleTimer = Timer(delay, () {
      _ensureVisibleTimer = null;
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
        label: context.l10n.agentModelConfig,
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
                                            ? context.l10n.agentLoadingModels
                                            : context.l10n.agentNoModels,
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
            context.l10n.agentConfigNextTurn,
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
              style: textStyles.identifier.copyWith(
                color: model.enabled ? colors.textPrimary : colors.textTertiary,
              ),
            ),
          ),
          if (saving)
            IdeBusySpinner(
              size: 12,
              strokeWidth: 1.5,
              color: colors.textSecondary,
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
              : model.unavailableReason ??
                    context.l10n.agentModelUnavailableNow,
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
    // 展示顺序统一为低→高（左→右）；Grok 等 provider 的服务端顺序可能相反。
    final efforts = state.supportsReasoningOptions
        ? orderedReasoningEffortsForDisplay(model.supportedReasoningEfforts)
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
                      context.l10n.agentNoReasoningConfig,
                      style: textStyles.bodySmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ),
                )
              else
                _ReasoningEffortSlider(
                  efforts: efforts,
                  selectedEffort:
                      state.selectedReasoningEffort ?? efforts.first.effort,
                  saving: saving,
                  onChanged: onReasoningChanged,
                ),
              // 不支持 Fast 时不展示开关，避免“禁用态”干扰扫读。
              if (fastSupported) ...[
                const SizedBox(height: IdeSpacing.space4),
                _FastConfigRow(
                  model: model,
                  value: fastEnabled,
                  onChanged: onFastChanged,
                ),
              ],
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
                  actionLabel: context.l10n.agentRetry,
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
    required this.value,
    required this.onChanged,
  });

  final AgentModelInfo model;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return SizedBox(
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
              style: IdeTextStyles.of(
                context,
              ).rowTitle.copyWith(color: colors.textPrimary),
            ),
          ),
          Semantics(
            label: context.l10n.agentFastSemantic(
              model.displayName,
              value ? context.l10n.agentFastOn : context.l10n.agentFastOff,
            ),
            child: IdeSwitch(
              key: ValueKey<String>('agent-fast-switch-${model.id}'),
              value: value,
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
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

class _ReasoningEffortSlider extends StatefulWidget {
  const _ReasoningEffortSlider({
    required this.efforts,
    required this.selectedEffort,
    required this.saving,
    required this.onChanged,
  });

  final List<AgentModelReasoningEffort> efforts;
  final String selectedEffort;
  final bool saving;
  final ValueChanged<String> onChanged;

  @override
  State<_ReasoningEffortSlider> createState() => _ReasoningEffortSliderState();
}

class _ReasoningEffortSliderState extends State<_ReasoningEffortSlider>
    with TickerProviderStateMixin {
  static const double _trackHeight = 28;
  static const double _thumbWidth = 28;
  static const double _thumbHeight = 24;
  static const double _trackBorderWidth = 1;
  static const double _thumbInset = (_trackHeight - _thumbHeight) / 2;
  static const double _thumbInnerInset = _thumbInset - _trackBorderWidth;

  late final FocusNode _focusNode;
  late final AnimationController _flowController;
  late final AnimationController _impactController;
  int? _activePointer;
  double? _dragProgress;
  bool _focused = false;
  bool _reduceMotion = false;
  bool _maximumWasActive = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      debugLabel: 'agent-reasoning-effort-slider',
      onKeyEvent: _handleKey,
    );
    _flowController = AnimationController(
      vsync: this,
      duration: IdeMotion.durationIntelligenceShimmer,
    );
    _impactController = AnimationController(
      vsync: this,
      duration: IdeMotion.durationIntelligenceImpact,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncMaximumEffect();
  }

  @override
  void didUpdateWidget(covariant _ReasoningEffortSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    final optionsChanged = !listEquals(
      oldWidget.efforts.map((effort) => effort.effort).toList(),
      widget.efforts.map((effort) => effort.effort).toList(),
    );
    if (optionsChanged) {
      _dragProgress = null;
    }
    _syncMaximumEffect();
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _flowController.dispose();
    _impactController.dispose();
    super.dispose();
  }

  int get _selectedIndex {
    final index = widget.efforts.indexWhere(
      (effort) => effort.effort == widget.selectedEffort,
    );
    return index < 0 ? 0 : index;
  }

  int get _displayIndex {
    final progress = _dragProgress;
    if (progress == null || widget.efforts.length <= 1) {
      return _selectedIndex;
    }
    return (progress * (widget.efforts.length - 1)).round().clamp(
      0,
      widget.efforts.length - 1,
    );
  }

  double get _displayProgress {
    final progress = _dragProgress;
    if (progress != null) {
      return progress;
    }
    if (widget.efforts.length <= 1) {
      return 0.5;
    }
    return _selectedIndex / (widget.efforts.length - 1);
  }

  bool get _isAtMaximum =>
      widget.efforts.length > 1 && _displayIndex == widget.efforts.length - 1;

  String get _displayLabel => widget.efforts[_displayIndex].effort;

  void _syncMaximumEffect() {
    final maximumActive = _isAtMaximum;
    final enteredMaximum = maximumActive && !_maximumWasActive;
    _maximumWasActive = maximumActive;
    final tickerEnabled = TickerMode.valuesOf(context).enabled;
    final animate = maximumActive && !_reduceMotion && tickerEnabled;

    if (animate) {
      if (!_flowController.isAnimating) {
        _flowController.repeat();
      }
      if (enteredMaximum) {
        _impactController.forward(from: 0);
      }
      return;
    }

    if (_flowController.isAnimating) {
      _flowController.stop();
    }
    if (_impactController.isAnimating) {
      _impactController.stop();
    }
    final staticPhase = maximumActive ? 0.45 : 0.0;
    if (_flowController.value != staticPhase) {
      _flowController.value = staticPhase;
    }
    // 减少动态效果时保留稳定的端点光晕，不停留在冲击波的中间帧。
    final staticImpact = maximumActive ? 1.0 : 0.0;
    if (_impactController.value != staticImpact) {
      _impactController.value = staticImpact;
    }
  }

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _step(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _step(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.home) {
      _commitIndex(0);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      _commitIndex(widget.efforts.length - 1);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _step(int delta) {
    _focusNode.requestFocus();
    final target = (_selectedIndex + delta).clamp(0, widget.efforts.length - 1);
    _commitIndex(target);
  }

  void _commitIndex(int index) {
    final target = widget.efforts[index].effort;
    if (target != widget.selectedEffort) {
      widget.onChanged(target);
    }
  }

  double _progressForPosition(double dx, double width) {
    final thumbTravel = width - _thumbWidth - _thumbInset * 2;
    if (widget.efforts.length <= 1 || thumbTravel <= 0) {
      return 0.5;
    }
    return ((dx - _thumbInset - _thumbWidth / 2) / thumbTravel).clamp(0.0, 1.0);
  }

  void _updateDrag(double progress) {
    setState(() {
      _dragProgress = progress;
    });
    _syncMaximumEffect();
  }

  void _finishDrag({required bool commit}) {
    final targetIndex = _displayIndex;
    final selectionChanged =
        widget.efforts[targetIndex].effort != widget.selectedEffort;
    setState(() {
      _dragProgress = null;
    });
    if (commit) {
      _commitIndex(targetIndex);
    }
    // 提交最高档时由外部状态接管显示，避免预览阶段已经播放的冲击波被重启。
    if (!commit || !selectionChanged) {
      _syncMaximumEffect();
    }
  }

  void _handleFocusChanged(bool focused) {
    if (_focused == focused) {
      return;
    }
    setState(() {
      _focused = focused;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final maxActive = _isAtMaximum;
    final duration = _reduceMotion ? Duration.zero : IdeMotion.durationNormal;
    final currentIndex = _displayIndex;
    final increasedValue = currentIndex < widget.efforts.length - 1
        ? widget.efforts[currentIndex + 1].effort
        : null;
    final decreasedValue = currentIndex > 0
        ? widget.efforts[currentIndex - 1].effort
        : null;

    return Semantics(
      key: const ValueKey('agent-reasoning-segment-control'),
      container: true,
      slider: true,
      label: context.l10n.agentReasoningEffort,
      value: _displayLabel,
      increasedValue: increasedValue,
      decreasedValue: decreasedValue,
      onIncrease: currentIndex < widget.efforts.length - 1
          ? () => _step(1)
          : null,
      onDecrease: currentIndex > 0 ? () => _step(-1) : null,
      excludeSemantics: true,
      child: FocusableActionDetector(
        focusNode: _focusNode,
        onFocusChange: _handleFocusChanged,
        mouseCursor: widget.efforts.length > 1
            ? (_dragProgress == null
                  ? SystemMouseCursors.grab
                  : SystemMouseCursors.grabbing)
            : SystemMouseCursors.basic,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  Icon(
                    sf.LucideIcons.brain,
                    size: 12,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: IdeSpacing.space4),
                  Text(
                    context.l10n.agentReasoningEffort,
                    style: textStyles.rowTitle.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const Spacer(),
                  AnimatedDefaultTextStyle(
                    duration: duration,
                    curve: IdeMotion.curveDefault,
                    style: textStyles.titleSmall.copyWith(
                      color: maxActive
                          ? colors.intelligenceAccent
                          : colors.textPrimary,
                    ),
                    child: Text(
                      _displayLabel,
                      key: const ValueKey('agent-reasoning-current-label'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (widget.saving) ...[
                    const SizedBox(width: IdeSpacing.space6),
                    IdeBusySpinner(
                      size: 10,
                      strokeWidth: 1.4,
                      color: colors.textSecondary,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: IdeSpacing.space4),
            LayoutBuilder(
              builder: (context, constraints) {
                final width = constraints.maxWidth;
                // 可见区域四周统一为 _thumbInset；轨道边框会压缩子布局，
                // 因此 Stack 内定位需扣除边框宽度。
                final thumbTravel = math.max(
                  0.0,
                  width - _thumbWidth - _thumbInset * 2,
                );
                final thumbLeft =
                    _thumbInnerInset + thumbTravel * _displayProgress;
                return Listener(
                  key: const ValueKey('agent-reasoning-slider-track'),
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: widget.efforts.length > 1
                      ? (event) {
                          if (_activePointer != null) {
                            return;
                          }
                          _activePointer = event.pointer;
                          _focusNode.requestFocus();
                          _updateDrag(
                            _progressForPosition(event.localPosition.dx, width),
                          );
                        }
                      : null,
                  onPointerMove: widget.efforts.length > 1
                      ? (event) {
                          if (event.pointer != _activePointer) {
                            return;
                          }
                          _updateDrag(
                            _progressForPosition(event.localPosition.dx, width),
                          );
                        }
                      : null,
                  onPointerUp: widget.efforts.length > 1
                      ? (event) {
                          if (event.pointer != _activePointer) {
                            return;
                          }
                          _activePointer = null;
                          _finishDrag(commit: true);
                        }
                      : null,
                  onPointerCancel: widget.efforts.length > 1
                      ? (event) {
                          if (event.pointer != _activePointer) {
                            return;
                          }
                          _activePointer = null;
                          _finishDrag(commit: false);
                        }
                      : null,
                  child: AnimatedContainer(
                    height: _trackHeight,
                    duration: duration,
                    curve: IdeMotion.curveDefault,
                    decoration: BoxDecoration(
                      color: colors.surface,
                      border: Border.all(
                        color: _focused
                            ? colors.focusRing
                            : colors.borderSubtle,
                      ),
                      borderRadius: IdeRadius.allMedium,
                    ),
                    child: ClipRRect(
                      borderRadius: IdeRadius.allSmall,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          AnimatedOpacity(
                            key: const ValueKey('agent-reasoning-max-effect'),
                            opacity: maxActive ? 1 : 0,
                            duration: duration,
                            curve: IdeMotion.curveDefault,
                            child: RepaintBoundary(
                              child: AnimatedBuilder(
                                key: const ValueKey(
                                  'agent-reasoning-max-flow-animation',
                                ),
                                animation: _flowController,
                                builder: (context, child) => AnimatedBuilder(
                                  key: const ValueKey(
                                    'agent-reasoning-max-impact-animation',
                                  ),
                                  animation: _impactController,
                                  builder: (context, child) => CustomPaint(
                                    key: const ValueKey(
                                      'agent-reasoning-max-paint',
                                    ),
                                    painter: _ReasoningMaxEffectPainter(
                                      color: colors.intelligenceAccent,
                                      phase: _flowController.value,
                                      impactProgress: _impactController.value,
                                      endpointInset:
                                          _thumbWidth / 2 + _thumbInnerInset,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          if (_dragProgress != null)
                            Padding(
                              key: const ValueKey(
                                'agent-reasoning-option-markers',
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: _thumbInnerInset + _thumbWidth / 2,
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  for (
                                    var index = 0;
                                    index < widget.efforts.length;
                                    index += 1
                                  )
                                    DecoratedBox(
                                      decoration: BoxDecoration(
                                        color:
                                            index == widget.efforts.length - 1
                                            ? colors.intelligenceAccent
                                            : colors.textTertiary.withValues(
                                                alpha: 0.58,
                                              ),
                                        borderRadius: IdeRadius.pill,
                                      ),
                                      child: const SizedBox.square(
                                        dimension: 4,
                                      ),
                                    ),
                                ],
                              ),
                            ),
                          Row(
                            children: [
                              for (
                                var index = 0;
                                index < widget.efforts.length;
                                index += 1
                              )
                                Expanded(
                                  child: Listener(
                                    key: ValueKey<String>(
                                      'agent-reasoning-option-'
                                      '${widget.efforts[index].effort}',
                                    ),
                                    behavior: HitTestBehavior.opaque,
                                    onPointerDown: (_) {},
                                    child: const SizedBox.expand(),
                                  ),
                                ),
                            ],
                          ),
                          AnimatedPositioned(
                            duration: _dragProgress != null
                                ? Duration.zero
                                : duration,
                            curve: IdeMotion.curveDefault,
                            left: thumbLeft,
                            top: _thumbInnerInset,
                            width: _thumbWidth,
                            height: _thumbHeight,
                            child: IgnorePointer(
                              child: DecoratedBox(
                                key: const ValueKey(
                                  'agent-reasoning-slider-thumb',
                                ),
                                decoration: BoxDecoration(
                                  color: colors.surfaceOverlay,
                                  border: Border.all(color: colors.border),
                                  borderRadius: IdeRadius.allMedium,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasoningMaxEffectPainter extends CustomPainter {
  const _ReasoningMaxEffectPainter({
    required this.color,
    required this.phase,
    required this.impactProgress,
    required this.endpointInset,
  });

  final Color color;
  final double phase;
  final double impactProgress;
  final double endpointInset;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = Offset.zero & size;
    final gradient = LinearGradient(
      colors: <Color>[
        color.withValues(alpha: 0),
        color.withValues(alpha: 0.06),
        color.withValues(alpha: 0.2),
        color.withValues(alpha: 0.46),
      ],
      stops: const <double>[0.16, 0.44, 0.74, 1],
    );
    canvas.drawRect(bounds, Paint()..shader = gradient.createShader(bounds));

    final endpoint = Offset(
      math.max(endpointInset, size.width - endpointInset),
      size.height / 2,
    );
    final glowBounds = Rect.fromCircle(
      center: endpoint,
      radius: size.height * 0.9,
    );
    final endpointGlow = RadialGradient(
      colors: <Color>[
        color.withValues(alpha: 0.42),
        color.withValues(alpha: 0.12),
        color.withValues(alpha: 0),
      ],
      stops: const <double>[0, 0.42, 1],
    );
    canvas.drawCircle(
      endpoint,
      size.height * 0.9,
      Paint()..shader = endpointGlow.createShader(glowBounds),
    );

    const particleCount = 30;
    for (var index = 0; index < particleCount; index += 1) {
      // 固定种子式的分布让每帧只改变相位，避免随机闪烁。
      final localPhase = (phase + index * 0.173) % 1;
      final convergence = math.pow(localPhase, 2.6).toDouble();
      final startX =
          size.width * (0.18 + ((index * 37) % 43) / 100) - index % 3 * 2;
      final lane = ((index * 7) % 9 - 4) / 4;
      final startY = size.height / 2 + lane * size.height * 0.36;
      final flutter =
          math.sin((phase * 2 + index * 0.31) * math.pi * 2) *
          (1 - convergence) *
          1.1;
      final x = startX + (endpoint.dx - startX) * convergence;
      final y = startY + (endpoint.dy - startY) * convergence + flutter;
      final visibility = math.sin(localPhase * math.pi);
      final pixelSize = 1.15 + (index % 4) * 0.38;
      final stretch = 1 + convergence * 1.5;

      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromCenter(
            center: Offset(x, y),
            width: pixelSize * stretch,
            height: pixelSize,
          ),
          const Radius.circular(0.7),
        ),
        Paint()
          ..color = color.withValues(
            alpha: 0.1 + visibility * (0.28 + convergence * 0.32),
          ),
      );
    }

    if (impactProgress > 0 && impactProgress < 1) {
      final expansion = Curves.easeOutCubic.transform(impactProgress);
      final fade = math.pow(1 - impactProgress, 1.7).toDouble();
      final flashRadius = size.height * (0.25 + expansion * 0.82);
      final flashBounds = Rect.fromCircle(
        center: endpoint,
        radius: flashRadius,
      );
      final flash = RadialGradient(
        colors: <Color>[
          color.withValues(alpha: 0.48 * fade),
          color.withValues(alpha: 0.14 * fade),
          color.withValues(alpha: 0),
        ],
      );
      canvas.drawCircle(
        endpoint,
        flashRadius,
        Paint()..shader = flash.createShader(flashBounds),
      );
      canvas.drawCircle(
        endpoint,
        size.height * (0.18 + expansion * 0.72),
        Paint()
          ..color = color.withValues(alpha: 0.82 * fade)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.7 + (1 - expansion) * 1.3,
      );

      final streakLength = size.width * 0.24 * (1 - impactProgress);
      final streakBounds = Rect.fromLTRB(
        endpoint.dx - streakLength,
        endpoint.dy - 0.8,
        endpoint.dx,
        endpoint.dy + 0.8,
      );
      if (streakBounds.width > 0) {
        canvas.drawRRect(
          RRect.fromRectAndRadius(streakBounds, const Radius.circular(1)),
          Paint()
            ..shader = LinearGradient(
              colors: <Color>[
                color.withValues(alpha: 0),
                color.withValues(alpha: 0.72 * fade),
              ],
            ).createShader(streakBounds),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ReasoningMaxEffectPainter oldDelegate) {
    return oldDelegate.color != color ||
        oldDelegate.phase != phase ||
        oldDelegate.impactProgress != impactProgress ||
        oldDelegate.endpointInset != endpointInset;
  }
}

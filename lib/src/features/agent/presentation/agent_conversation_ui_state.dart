import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/model_config_ui_state.dart';

/// Agent 头栏实际渲染所需的不可变状态。
@immutable
final class AgentHeaderState {
  const AgentHeaderState({
    required this.title,
    required this.threadOpenPhase,
    required this.systemNoticeLabel,
    required this.statusCapsuleLabel,
    required this.waitingOnApproval,
    required this.waitingOnUserInput,
    required this.showRunningIndicator,
    required this.runningActivityLabel,
    required this.segmentStartedAt,
    required this.turnStartedAt,
    required this.tokenUsage,
    required this.shouldOfferContextCompact,
    required this.isCompacting,
    required this.isTurnRunning,
    required this.isReadOnly,
    required this.canFork,
    required this.canRename,
    required this.canArchive,
    required this.isPlanMode,
  });

  final String title;
  final AgentThreadOpenPhase threadOpenPhase;
  final String? systemNoticeLabel;
  final String? statusCapsuleLabel;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool showRunningIndicator;
  final String? runningActivityLabel;
  final DateTime? segmentStartedAt;
  final DateTime? turnStartedAt;
  final AgentTokenUsage? tokenUsage;
  final bool shouldOfferContextCompact;
  final bool isCompacting;
  final bool isTurnRunning;
  final bool isReadOnly;
  final bool canFork;
  final bool canRename;
  final bool canArchive;
  final bool isPlanMode;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentHeaderState &&
            other.title == title &&
            other.threadOpenPhase == threadOpenPhase &&
            other.systemNoticeLabel == systemNoticeLabel &&
            other.statusCapsuleLabel == statusCapsuleLabel &&
            other.waitingOnApproval == waitingOnApproval &&
            other.waitingOnUserInput == waitingOnUserInput &&
            other.showRunningIndicator == showRunningIndicator &&
            other.runningActivityLabel == runningActivityLabel &&
            other.segmentStartedAt == segmentStartedAt &&
            other.turnStartedAt == turnStartedAt &&
            _tokenUsageEquals(other.tokenUsage, tokenUsage) &&
            other.shouldOfferContextCompact == shouldOfferContextCompact &&
            other.isCompacting == isCompacting &&
            other.isTurnRunning == isTurnRunning &&
            other.isReadOnly == isReadOnly &&
            other.canFork == canFork &&
            other.canRename == canRename &&
            other.canArchive == canArchive &&
            other.isPlanMode == isPlanMode;
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    title,
    threadOpenPhase,
    systemNoticeLabel,
    statusCapsuleLabel,
    waitingOnApproval,
    waitingOnUserInput,
    showRunningIndicator,
    runningActivityLabel,
    segmentStartedAt,
    turnStartedAt,
    _tokenUsageHash(tokenUsage),
    shouldOfferContextCompact,
    isCompacting,
    isTurnRunning,
    isReadOnly,
    canFork,
    canRename,
    canArchive,
    isPlanMode,
  ]);
}

/// Agent Composer 实际渲染所需的不可变状态。
@immutable
final class AgentComposerState {
  AgentComposerState({
    required this.canSubmitMessage,
    required this.isTurnRunning,
    required this.threadOpenPhase,
    required this.contextUsage,
    required this.isReadOnly,
    required this.unavailableProviderReason,
    required this.canAttachImages,
    required this.canMentionResources,
    required this.canUseSkills,
    required this.conversationModeStatus,
    required Iterable<AgentConversationModePreset> conversationModeOptions,
    required this.selectedConversationMode,
    required this.conversationModeAppliesToNextTurn,
    required this.conversationModeStatusMessage,
    required this.conversationModeContextId,
    required this.showModelSelection,
    required this.modelConfigState,
    required this.showPermissionPolicy,
    required this.permissionPolicyLabel,
    required Iterable<AgentPermissionOption> permissionOptions,
    required this.selectedPermissionOptionId,
    this.permissionApplyScopeHint,
    required Iterable<AgentSessionConfigOption> sessionConfigOptions,
  }) : conversationModeOptions = List<AgentConversationModePreset>.unmodifiable(
         conversationModeOptions,
       ),
       permissionOptions = List<AgentPermissionOption>.unmodifiable(
         permissionOptions,
       ),
       sessionConfigOptions = List<AgentSessionConfigOption>.unmodifiable(
         sessionConfigOptions,
       ),
       _modelConfigSignature = _modelConfigUiSignature(modelConfigState),
       _sessionConfigSignature = _sessionConfigOptionsSignature(
         sessionConfigOptions,
       );

  final bool canSubmitMessage;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentTokenUsage? contextUsage;
  final bool isReadOnly;
  final String? unavailableProviderReason;
  final bool canAttachImages;
  final bool canMentionResources;
  final bool canUseSkills;
  final AgentConversationModeLoadStatus conversationModeStatus;
  final List<AgentConversationModePreset> conversationModeOptions;
  final AgentConversationModeId? selectedConversationMode;
  final bool conversationModeAppliesToNextTurn;
  final String? conversationModeStatusMessage;
  final Object conversationModeContextId;
  final bool showModelSelection;
  final AgentModelConfigUiState modelConfigState;
  final bool showPermissionPolicy;
  final String permissionPolicyLabel;

  /// 中立权限选项目录（label 来自 adapter）。
  final List<AgentPermissionOption> permissionOptions;

  /// 当前选中的权限 option id。
  final String? selectedPermissionOptionId;

  /// apply scope 紧凑提示（如「下次会话生效」）。
  final String? permissionApplyScopeHint;
  final List<AgentSessionConfigOption> sessionConfigOptions;

  final Object _modelConfigSignature;
  final Object _sessionConfigSignature;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentComposerState &&
            other.canSubmitMessage == canSubmitMessage &&
            other.isTurnRunning == isTurnRunning &&
            other.threadOpenPhase == threadOpenPhase &&
            _tokenUsageEquals(other.contextUsage, contextUsage) &&
            other.isReadOnly == isReadOnly &&
            other.unavailableProviderReason == unavailableProviderReason &&
            other.canAttachImages == canAttachImages &&
            other.canMentionResources == canMentionResources &&
            other.canUseSkills == canUseSkills &&
            other.conversationModeStatus == conversationModeStatus &&
            listEquals(
              other.conversationModeOptions,
              conversationModeOptions,
            ) &&
            other.selectedConversationMode == selectedConversationMode &&
            other.conversationModeAppliesToNextTurn ==
                conversationModeAppliesToNextTurn &&
            other.conversationModeStatusMessage ==
                conversationModeStatusMessage &&
            other.conversationModeContextId == conversationModeContextId &&
            other.showModelSelection == showModelSelection &&
            _deepUiEquals(other._modelConfigSignature, _modelConfigSignature) &&
            other.showPermissionPolicy == showPermissionPolicy &&
            other.permissionPolicyLabel == permissionPolicyLabel &&
            listEquals(other.permissionOptions, permissionOptions) &&
            other.selectedPermissionOptionId == selectedPermissionOptionId &&
            other.permissionApplyScopeHint == permissionApplyScopeHint &&
            _deepUiEquals(
              other._sessionConfigSignature,
              _sessionConfigSignature,
            );
  }

  @override
  int get hashCode => Object.hashAll(<Object?>[
    canSubmitMessage,
    isTurnRunning,
    threadOpenPhase,
    _tokenUsageHash(contextUsage),
    isReadOnly,
    unavailableProviderReason,
    canAttachImages,
    canMentionResources,
    canUseSkills,
    conversationModeStatus,
    Object.hashAll(conversationModeOptions),
    selectedConversationMode,
    conversationModeAppliesToNextTurn,
    conversationModeStatusMessage,
    conversationModeContextId,
    showModelSelection,
    _deepUiHash(_modelConfigSignature),
    showPermissionPolicy,
    permissionPolicyLabel,
    Object.hashAll(permissionOptions),
    selectedPermissionOptionId,
    permissionApplyScopeHint,
    _deepUiHash(_sessionConfigSignature),
  ]);
}

/// Composer 上方四类待处理交互的不可变状态。
@immutable
final class AgentPendingInteractionState {
  factory AgentPendingInteractionState({
    required Iterable<AgentPermissionRequest> permissions,
    required Iterable<AgentQuestionRequest> questions,
    required Iterable<AgentPlanApprovalRequest> planApprovals,
    required AgentPlanExecutionRequest? planExecutionHandoff,
    required bool isReadOnly,
    required Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId,
    required AgentAutoApprovalReviewEvent? latestDeniedAutoReview,
  }) {
    final permissionSnapshot = List<AgentPermissionRequest>.unmodifiable(
      permissions.map(_snapshotPermissionRequest),
    );
    final questionSnapshot = List<AgentQuestionRequest>.unmodifiable(
      questions.map(_snapshotQuestionRequest),
    );
    final planApprovalSnapshot = List<AgentPlanApprovalRequest>.unmodifiable(
      planApprovals.map(_snapshotPlanApprovalRequest),
    );
    final reviewSnapshot =
        Map<String, AgentAutoApprovalReviewEvent>.unmodifiable(
          autoReviewsByTurnId.map(
            (key, value) => MapEntry(key, _snapshotAutoReview(value)),
          ),
        );
    final deniedReviewSnapshot = latestDeniedAutoReview == null
        ? null
        : _snapshotAutoReview(latestDeniedAutoReview);
    return AgentPendingInteractionState._(
      _pendingInteractionSignature(
        permissions: permissionSnapshot,
        questions: questionSnapshot,
        planApprovals: planApprovalSnapshot,
        planExecutionHandoff: planExecutionHandoff,
        isReadOnly: isReadOnly,
        autoReviewsByTurnId: reviewSnapshot,
        latestDeniedAutoReview: deniedReviewSnapshot,
      ),
      permissions: permissionSnapshot,
      questions: questionSnapshot,
      planApprovals: planApprovalSnapshot,
      planExecutionHandoff: planExecutionHandoff,
      isReadOnly: isReadOnly,
      autoReviewsByTurnId: reviewSnapshot,
      latestDeniedAutoReview: deniedReviewSnapshot,
    );
  }

  const AgentPendingInteractionState._(
    this._semanticSignature, {
    required this.permissions,
    required this.questions,
    required this.planApprovals,
    required this.planExecutionHandoff,
    required this.isReadOnly,
    required this.autoReviewsByTurnId,
    required this.latestDeniedAutoReview,
  });

  final List<AgentPermissionRequest> permissions;
  final List<AgentQuestionRequest> questions;
  final List<AgentPlanApprovalRequest> planApprovals;
  final AgentPlanExecutionRequest? planExecutionHandoff;
  final bool isReadOnly;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;

  final Object _semanticSignature;

  bool get isEmpty =>
      permissions.isEmpty &&
      questions.isEmpty &&
      planApprovals.isEmpty &&
      planExecutionHandoff == null;

  /// 权限、提问、计划审批与本地执行交接均占用底部交互区，隐藏主 Composer。
  bool get blocksComposer =>
      permissions.isNotEmpty ||
      questions.isNotEmpty ||
      planApprovals.isNotEmpty ||
      planExecutionHandoff != null;

  AgentAutoApprovalReviewEvent? autoReviewForTurn(String? turnId) =>
      turnId == null ? null : autoReviewsByTurnId[turnId];

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentPendingInteractionState &&
          _deepUiEquals(other._semanticSignature, _semanticSignature);

  @override
  int get hashCode => _deepUiHash(_semanticSignature);
}

/// 工具、计划和投影分组的不可变展开状态。
@immutable
final class AgentExpansionState {
  AgentExpansionState({
    required Iterable<String> toolCallIds,
    required Iterable<String> planMessageIds,
    required Iterable<String> activePlanTurnIds,
    required Iterable<String> commandGroupIds,
    required Iterable<String> fileEditItemIds,
  }) : toolCallIds = Set<String>.unmodifiable(toolCallIds),
       planMessageIds = Set<String>.unmodifiable(planMessageIds),
       activePlanTurnIds = Set<String>.unmodifiable(activePlanTurnIds),
       commandGroupIds = Set<String>.unmodifiable(commandGroupIds),
       fileEditItemIds = Set<String>.unmodifiable(fileEditItemIds);

  final Set<String> toolCallIds;
  final Set<String> planMessageIds;
  final Set<String> activePlanTurnIds;
  final Set<String> commandGroupIds;
  final Set<String> fileEditItemIds;

  bool isToolCallExpanded(String id) => toolCallIds.contains(id);

  bool isPlanMessageExpanded(String id) => planMessageIds.contains(id);

  bool isActivePlanExpanded(String id) => activePlanTurnIds.contains(id);

  bool isCommandGroupExpanded(String id) => commandGroupIds.contains(id);

  bool isFileEditItemExpanded(String id) => fileEditItemIds.contains(id);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentExpansionState &&
          setEquals(other.toolCallIds, toolCallIds) &&
          setEquals(other.planMessageIds, planMessageIds) &&
          setEquals(other.activePlanTurnIds, activePlanTurnIds) &&
          setEquals(other.commandGroupIds, commandGroupIds) &&
          setEquals(other.fileEditItemIds, fileEditItemIds);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(toolCallIds),
    Object.hashAllUnordered(planMessageIds),
    Object.hashAllUnordered(activePlanTurnIds),
    Object.hashAllUnordered(commandGroupIds),
    Object.hashAllUnordered(fileEditItemIds),
  );
}

/// 历史时间线绑定的不可变快照。
///
/// 该值只在 history region 发布时创建；live delta 继续直接修改稳定的
/// [AgentConversationTurnState]，不会复制历史集合。
@immutable
final class AgentConversationHistoryState {
  factory AgentConversationHistoryState({
    required AgentConversationTurnGroup? standbyTurn,
    required Iterable<AgentConversationTurnGroup> visibleTurns,
    required AgentThreadOpenPhase threadOpenPhase,
    required String providerId,
    required AgentProviderKind providerKind,
    required String providerName,
  }) {
    final standbySnapshot = standbyTurn == null
        ? null
        : _snapshotTurnGroup(standbyTurn);
    final turnSnapshots = List<AgentConversationTurnGroup>.unmodifiable(
      visibleTurns.map(_snapshotTurnGroup),
    );
    return AgentConversationHistoryState._(
      _historySignature(standbySnapshot, turnSnapshots),
      standbyTurn: standbySnapshot,
      visibleTurns: turnSnapshots,
      threadOpenPhase: threadOpenPhase,
      providerId: providerId,
      providerKind: providerKind,
      providerName: providerName,
    );
  }

  const AgentConversationHistoryState._(
    this._semanticSignature, {
    required this.standbyTurn,
    required this.visibleTurns,
    required this.threadOpenPhase,
    required this.providerId,
    required this.providerKind,
    required this.providerName,
  });

  final AgentConversationTurnGroup? standbyTurn;
  final List<AgentConversationTurnGroup> visibleTurns;
  final AgentThreadOpenPhase threadOpenPhase;
  final String providerId;
  final AgentProviderKind providerKind;
  final String providerName;

  final Object _semanticSignature;

  bool get isLoading => threadOpenPhase == AgentThreadOpenPhase.loadingHistory;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentConversationHistoryState &&
          other.threadOpenPhase == threadOpenPhase &&
          other.providerId == providerId &&
          other.providerKind == providerKind &&
          other.providerName == providerName &&
          _deepUiEquals(other._semanticSignature, _semanticSignature);

  @override
  int get hashCode => Object.hash(
    threadOpenPhase,
    providerId,
    providerKind,
    providerName,
    _deepUiHash(_semanticSignature),
  );
}

/// Typed UI state 发布端的累计只读诊断。
///
/// 仅包含调度与发布次数，不包含消息正文、Provider payload 或用户数据。
@immutable
final class AgentConversationUiStateDiagnostics {
  const AgentConversationUiStateDiagnostics({required this.publishCount});

  final int publishCount;
}

/// 将类型化 UI 更新请求发布到结构值 listenable 与一次性 effect stream。
///
/// effect stream 是无 replay 的瞬时通道，只用于当前挂载的活动 AgentPane；
/// 历史与 live turn 数据仍由 TimelineStore 保存。
final class AgentConversationUiStateStore {
  factory AgentConversationUiStateStore({
    required AgentConversationTimelineStore timeline,
    required AgentHeaderState Function() buildHeaderState,
    required AgentComposerState Function() buildComposerState,
    required AgentPendingInteractionState Function()
    buildPendingInteractionState,
    required AgentExpansionState Function() buildExpansionState,
    required AgentConversationHistoryState Function() buildHistoryState,
    required bool Function() isDisposed,
  }) {
    return AgentConversationUiStateStore._(
      timeline: timeline,
      buildHeaderState: buildHeaderState,
      buildComposerState: buildComposerState,
      buildPendingInteractionState: buildPendingInteractionState,
      buildExpansionState: buildExpansionState,
      buildHistoryState: buildHistoryState,
      isDisposed: isDisposed,
    );
  }

  AgentConversationUiStateStore._({
    required this._timeline,
    required this._buildHeaderState,
    required this._buildComposerState,
    required this._buildPendingInteractionState,
    required this._buildExpansionState,
    required this._buildHistoryState,
    required this._isDisposed,
  }) {
    _header = ValueNotifier<AgentHeaderState>(_buildHeaderState());
    _composer = ValueNotifier<AgentComposerState>(_buildComposerState());
    _pendingInteractions = ValueNotifier<AgentPendingInteractionState>(
      _buildPendingInteractionState(),
    );
    _expansion = ValueNotifier<AgentExpansionState>(_buildExpansionState());
    _history = ValueNotifier<AgentConversationHistoryState>(
      _buildHistoryState(),
    );
  }

  final AgentConversationTimelineStore _timeline;
  final AgentHeaderState Function() _buildHeaderState;
  final AgentComposerState Function() _buildComposerState;
  final AgentPendingInteractionState Function() _buildPendingInteractionState;
  final AgentExpansionState Function() _buildExpansionState;
  final AgentConversationHistoryState Function() _buildHistoryState;
  final bool Function() _isDisposed;

  late final ValueNotifier<AgentHeaderState> _header;
  late final ValueNotifier<AgentComposerState> _composer;
  late final ValueNotifier<AgentPendingInteractionState> _pendingInteractions;
  late final ValueNotifier<AgentExpansionState> _expansion;
  late final ValueNotifier<AgentConversationHistoryState> _history;
  final StreamController<AgentUiEffect> _effectController =
      StreamController<AgentUiEffect>.broadcast(sync: true);

  AgentUiUpdateRequest? _debugLastAcceptedRequest;
  int _publishCount = 0;
  bool _closed = false;

  ValueListenable<AgentHeaderState> get header => _header;

  ValueListenable<AgentComposerState> get composer => _composer;

  ValueListenable<AgentPendingInteractionState> get pendingInteractions =>
      _pendingInteractions;

  ValueListenable<AgentExpansionState> get expansion => _expansion;

  ValueListenable<AgentConversationHistoryState> get history => _history;

  /// 无 replay 的一次性 UI effect。
  Stream<AgentUiEffect> get effects => _effectController.stream;

  AgentConversationUiStateDiagnostics get diagnostics =>
      AgentConversationUiStateDiagnostics(publishCount: _publishCount);

  @visibleForTesting
  AgentUiUpdateRequest? get debugLastAcceptedRequest =>
      _debugLastAcceptedRequest;

  void publish(AgentUiUpdateRequest request) {
    if (_closed || _isDisposed() || request.isEmpty) {
      return;
    }
    _debugLastAcceptedRequest = request;
    _publishCount += 1;

    if (request.regions.contains(AgentUiRegion.liveTurnBinding)) {
      _timeline.syncLiveTurnBinding();
    }
    if (request.regions.contains(AgentUiRegion.history)) {
      _publishIfChanged(_history, _buildHistoryState());
    }
    if (request.regions.contains(AgentUiRegion.header)) {
      _publishIfChanged(_header, _buildHeaderState());
    }
    if (request.regions.contains(AgentUiRegion.composer)) {
      _publishIfChanged(_composer, _buildComposerState());
    }
    if (request.regions.contains(AgentUiRegion.pendingInteraction)) {
      _publishIfChanged(_pendingInteractions, _buildPendingInteractionState());
    }
    if (request.regions.contains(AgentUiRegion.expansion)) {
      _publishIfChanged(_expansion, _buildExpansionState());
    }
    if (request.regions.contains(AgentUiRegion.liveTurn)) {
      _timeline.liveTurnState?.markDirty();
      _timeline.liveTurnState?.flushNow();
    }
    for (final effect in request.effects) {
      _effectController.add(effect);
    }
  }

  void dispose() {
    if (_closed) {
      return;
    }
    _closed = true;
    _header.dispose();
    _composer.dispose();
    _pendingInteractions.dispose();
    _expansion.dispose();
    _history.dispose();
    unawaited(_effectController.close());
  }
}

void _publishIfChanged<T>(ValueNotifier<T> notifier, T next) {
  if (notifier.value != next) {
    notifier.value = next;
  }
}

bool _tokenUsageEquals(AgentTokenUsage? left, AgentTokenUsage? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left == null || right == null) {
    return false;
  }
  return left.inputTokens == right.inputTokens &&
      left.cachedInputTokens == right.cachedInputTokens &&
      left.outputTokens == right.outputTokens &&
      left.reasoningOutputTokens == right.reasoningOutputTokens &&
      left.totalTokens == right.totalTokens &&
      left.lastInputTokens == right.lastInputTokens &&
      left.lastCachedInputTokens == right.lastCachedInputTokens &&
      left.lastOutputTokens == right.lastOutputTokens &&
      left.lastReasoningOutputTokens == right.lastReasoningOutputTokens &&
      left.lastTotalTokens == right.lastTotalTokens &&
      left.modelContextWindow == right.modelContextWindow;
}

int _tokenUsageHash(AgentTokenUsage? usage) => usage == null
    ? 0
    : Object.hashAll(<Object?>[
        usage.inputTokens,
        usage.cachedInputTokens,
        usage.outputTokens,
        usage.reasoningOutputTokens,
        usage.totalTokens,
        usage.lastInputTokens,
        usage.lastCachedInputTokens,
        usage.lastOutputTokens,
        usage.lastReasoningOutputTokens,
        usage.lastTotalTokens,
        usage.modelContextWindow,
      ]);

Object _modelConfigUiSignature(AgentModelConfigUiState state) {
  final preferenceEntries = state.preferences.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  return _freezeUiValue(<Object?>[
    state.models
        .map((model) {
          return <Object?>[
            model.id,
            model.model,
            model.displayName,
            model.description,
            model.hidden,
            model.supportedReasoningEfforts
                .map((item) => <Object?>[item.effort, item.description])
                .toList(growable: false),
            model.defaultReasoningEffort,
            model.serviceTiers
                .map(
                  (tier) => <Object?>[
                    tier.id,
                    tier.name,
                    tier.description,
                    tier.enabled,
                    tier.unavailableReason,
                  ],
                )
                .toList(growable: false),
            model.defaultServiceTier,
            model.isDefault,
            model.enabled,
            model.unavailableReason,
            model.contextWindowTokens,
          ];
        })
        .toList(growable: false),
    state.selectedModelId,
    state.expandedModelId,
    state.selectedReasoningEffort,
    state.selectedServiceTierId,
    preferenceEntries
        .map((entry) {
          final preference = entry.value;
          return <Object?>[
            entry.key,
            preference.modelId,
            preference.reasoningEffort,
            preference.fastEnabled,
            preference.serviceTierId,
            preference.updatedAt,
            preference.version,
          ];
        })
        .toList(growable: false),
    (state.savingModelIds.toList(growable: false)..sort()),
    state.isRefreshing,
    state.appliesNextTurn,
    state.supportsReasoningOptions,
    state.supportsServiceTierSelection,
    if (state.compatibilityConflict case final conflict?)
      <Object?>[
        conflict.modelId,
        conflict.message,
        conflict.actionLabel,
        conflict.resolution.modelId,
        conflict.resolution.reasoningEffort,
        conflict.resolution.serviceTierId,
      ],
    if (state.saveError case final error?)
      <Object?>[error.modelId, error.field, error.message, error.details],
    state.selectionNotice,
    state.refreshError,
  ])!;
}

Object _sessionConfigOptionsSignature(
  Iterable<AgentSessionConfigOption> options,
) {
  return _freezeUiValue(
    options
        .map((option) {
          return <Object?>[
            option.id,
            option.name,
            option.kind,
            option.description,
            option.category,
            option.currentValue,
            option.values
                .map(
                  (value) => <Object?>[
                    value.id,
                    value.label,
                    value.description,
                  ],
                )
                .toList(growable: false),
          ];
        })
        .toList(growable: false),
  )!;
}

AgentPermissionRequest _snapshotPermissionRequest(
  AgentPermissionRequest request,
) {
  return AgentPermissionRequest(
    id: request.id,
    title: request.title,
    kind: request.kind,
    description: request.description,
    command: request.command,
    cwd: request.cwd,
    sessionId: request.sessionId,
    turnId: request.turnId,
    fileChanges: Map<String, Object?>.unmodifiable(request.fileChanges),
    commandActions: List<String>.unmodifiable(request.commandActions),
    proposedExecpolicyAmendment: List<String>.unmodifiable(
      request.proposedExecpolicyAmendment,
    ),
    raw: Map<String, Object?>.unmodifiable(request.raw),
  );
}

AgentQuestionRequest _snapshotQuestionRequest(AgentQuestionRequest request) {
  return AgentQuestionRequest(
    id: request.id,
    title: request.title,
    description: request.description,
    questions: List<AgentUserInputQaPair>.unmodifiable(
      request.questions.map(_snapshotQuestion),
    ),
    sessionId: request.sessionId,
    turnId: request.turnId,
    raw: Map<String, Object?>.unmodifiable(request.raw),
  );
}

AgentUserInputQaPair _snapshotQuestion(AgentUserInputQaPair question) {
  return AgentUserInputQaPair(
    questionId: question.questionId,
    question: question.question,
    header: question.header,
    options: List<String>.unmodifiable(question.options),
    optionItems: List<AgentUserInputOption>.unmodifiable(
      question.optionItems.map(
        (option) => AgentUserInputOption(
          id: option.id,
          label: option.label,
          description: option.description,
        ),
      ),
    ),
    answers: List<String>.unmodifiable(question.answers),
    allowMultiple: question.allowMultiple,
    isOther: question.isOther,
    isSecret: question.isSecret,
  );
}

AgentPlanApprovalRequest _snapshotPlanApprovalRequest(
  AgentPlanApprovalRequest request,
) {
  return AgentPlanApprovalRequest(
    id: request.id,
    title: request.title,
    markdown: request.markdown,
    overview: request.overview,
    todos: List<AgentPlanEntry>.unmodifiable(
      request.todos.map(_snapshotPlanEntry),
    ),
    phases: List<AgentPlanApprovalPhase>.unmodifiable(
      request.phases.map(
        (phase) => AgentPlanApprovalPhase(
          name: phase.name,
          todos: List<AgentPlanEntry>.unmodifiable(
            phase.todos.map(_snapshotPlanEntry),
          ),
        ),
      ),
    ),
    isProject: request.isProject,
    sessionId: request.sessionId,
    turnId: request.turnId,
    raw: Map<String, Object?>.unmodifiable(request.raw),
  );
}

AgentPlanEntry _snapshotPlanEntry(AgentPlanEntry entry) => AgentPlanEntry(
  id: entry.id,
  content: entry.content,
  status: entry.status,
  priority: entry.priority,
);

AgentAutoApprovalReviewEvent _snapshotAutoReview(
  AgentAutoApprovalReviewEvent review,
) {
  return AgentAutoApprovalReviewEvent(
    threadId: review.threadId,
    turnId: review.turnId,
    reviewId: review.reviewId,
    status: review.status,
    rationale: review.rationale,
    riskLevel: review.riskLevel,
    targetItemId: review.targetItemId,
    raw: Map<String, Object?>.unmodifiable(review.raw),
  );
}

Object _pendingInteractionSignature({
  required Iterable<AgentPermissionRequest> permissions,
  required Iterable<AgentQuestionRequest> questions,
  required Iterable<AgentPlanApprovalRequest> planApprovals,
  required AgentPlanExecutionRequest? planExecutionHandoff,
  required bool isReadOnly,
  required Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId,
  required AgentAutoApprovalReviewEvent? latestDeniedAutoReview,
}) {
  final reviews = autoReviewsByTurnId.entries.toList(growable: false)
    ..sort((left, right) => left.key.compareTo(right.key));
  return _freezeUiValue(<Object?>[
    permissions
        .map((request) {
          return <Object?>[
            request.id,
            request.title,
            request.kind,
            request.description,
            request.command,
            request.cwd,
            request.sessionId,
            request.turnId,
            request.proposedExecpolicyAmendment,
          ];
        })
        .toList(growable: false),
    questions
        .map((request) {
          return <Object?>[
            request.id,
            request.title,
            request.description,
            request.sessionId,
            request.turnId,
            request.questions
                .map((question) {
                  return <Object?>[
                    question.questionId,
                    question.question,
                    question.header,
                    question.options,
                    question.optionItems
                        .map(
                          (option) => <Object?>[
                            option.id,
                            option.label,
                            option.description,
                          ],
                        )
                        .toList(growable: false),
                    question.answers,
                    question.allowMultiple,
                    question.isOther,
                    question.isSecret,
                  ];
                })
                .toList(growable: false),
          ];
        })
        .toList(growable: false),
    planApprovals
        .map((request) {
          return <Object?>[
            request.id,
            request.title,
            request.markdown,
            request.overview,
            request.todos.map(_planEntrySignature).toList(growable: false),
            request.phases
                .map(
                  (phase) => <Object?>[
                    phase.name,
                    phase.todos
                        .map(_planEntrySignature)
                        .toList(growable: false),
                  ],
                )
                .toList(growable: false),
            request.isProject,
            request.sessionId,
            request.turnId,
          ];
        })
        .toList(growable: false),
    if (planExecutionHandoff case final request?)
      <Object?>[
        request.id,
        request.sessionId,
        request.turnId,
        request.title,
        request.markdown,
      ],
    isReadOnly,
    reviews
        .map((entry) => <Object?>[entry.key, _autoReviewSignature(entry.value)])
        .toList(growable: false),
    if (latestDeniedAutoReview case final review?) _autoReviewSignature(review),
  ])!;
}

Object _planEntrySignature(AgentPlanEntry entry) => <Object?>[
  entry.id,
  entry.content,
  entry.status,
  entry.priority,
];

Object _autoReviewSignature(AgentAutoApprovalReviewEvent review) => <Object?>[
  review.threadId,
  review.turnId,
  review.reviewId,
  review.status,
  review.rationale,
  review.riskLevel,
  review.targetItemId,
];

AgentConversationTurnGroup _snapshotTurnGroup(AgentConversationTurnGroup turn) {
  return AgentConversationTurnGroup(
    id: turn.id,
    entries: List<AgentTimelineEntry>.unmodifiable(turn.entries),
    isStandby: turn.isStandby,
    status: turn.status,
    startedAt: turn.startedAt,
    completedAt: turn.completedAt,
    duration: turn.duration,
    tokenUsage: turn.tokenUsage,
    modelConfig: turn.modelConfig,
    renderRevision: turn.renderRevision,
    contentRevision: turn.contentRevision,
    metaRevision: turn.metaRevision,
  );
}

Object _historySignature(
  AgentConversationTurnGroup? standby,
  Iterable<AgentConversationTurnGroup> history,
) {
  Object? turnSignature(AgentConversationTurnGroup? turn) {
    if (turn == null) {
      return null;
    }
    return <Object?>[
      turn.id,
      turn.isStandby,
      turn.status,
      turn.startedAt,
      turn.completedAt,
      turn.duration,
      _tokenUsageHash(turn.tokenUsage),
      turn.modelConfig?.modelId,
      turn.modelConfig?.reasoningEffort,
      turn.modelConfig?.fastEnabled,
      turn.contentRevision,
      turn.metaRevision,
      turn.entries
          .map((entry) => <Object?>[entry.runtimeType, entry.id])
          .toList(growable: false),
    ];
  }

  return _freezeUiValue(<Object?>[
    turnSignature(standby),
    history.map(turnSignature).toList(growable: false),
  ])!;
}

Object? _freezeUiValue(Object? value) {
  if (value is Map) {
    final entries =
        value.entries
            .map(
              (entry) => MapEntry<Object?, Object?>(
                _freezeUiValue(entry.key),
                _freezeUiValue(entry.value),
              ),
            )
            .toList(growable: false)
          ..sort((left, right) => '${left.key}'.compareTo('${right.key}'));
    return Map<Object?, Object?>.unmodifiable(<Object?, Object?>{
      for (final entry in entries) entry.key: entry.value,
    });
  }
  if (value is Iterable) {
    return List<Object?>.unmodifiable(value.map(_freezeUiValue));
  }
  return value;
}

bool _deepUiEquals(Object? left, Object? right) {
  if (identical(left, right)) {
    return true;
  }
  if (left is List && right is List) {
    if (left.length != right.length) {
      return false;
    }
    for (var index = 0; index < left.length; index += 1) {
      if (!_deepUiEquals(left[index], right[index])) {
        return false;
      }
    }
    return true;
  }
  if (left is Map && right is Map) {
    if (left.length != right.length) {
      return false;
    }
    for (final entry in left.entries) {
      if (!right.containsKey(entry.key) ||
          !_deepUiEquals(entry.value, right[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return left == right;
}

int _deepUiHash(Object? value) {
  if (value is List) {
    return Object.hashAll(value.map(_deepUiHash));
  }
  if (value is Map) {
    return Object.hashAllUnordered(
      value.entries.map(
        (entry) =>
            Object.hash(_deepUiHash(entry.key), _deepUiHash(entry.value)),
      ),
    );
  }
  return value.hashCode;
}

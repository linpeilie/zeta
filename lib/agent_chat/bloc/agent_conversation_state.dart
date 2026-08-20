import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

export 'package:agent_conversation_repository/agent_conversation_repository.dart'
    show
        AgentConversationFailure,
        AgentConversationFailureCode,
        ConversationKey,
        ConversationSnapshot,
        SteerRequest,
        TurnRequest;
export 'package:agent_provider_contracts/agent_provider_contracts.dart'
    show
        AgentContext,
        AgentDeniedActionOverrideRequest,
        AgentHistoryTurnStatus,
        AgentModelSelection,
        AgentPermissionDecision,
        AgentPlanApprovalDecision,
        AgentPlanApprovalDecisionKind,
        AgentPlanExecutionRequest,
        AgentQuestionResponse;

enum AgentConversationStatus { initial, opening, ready, failure }

enum AgentThreadOpenPhase { idle, loadingHistory, openFailed }

enum AgentStatusCapsule { idle, running, waitingOnApproval, waitingOnInput }

enum AgentActivityCode { thinking, executing, waiting }

enum AgentConversationModeLoadStatus { unavailable, loading, ready, error }

final class AgentConversationTurnGroup extends Equatable {
  const AgentConversationTurnGroup({
    required this.id,
    this.entryIds = const <String>[],
    this.status = AgentHistoryTurnStatus.unknown,
  });

  final String id;
  final List<String> entryIds;
  final AgentHistoryTurnStatus status;

  @override
  List<Object?> get props => <Object?>[id, entryIds, status];
}

final class AgentModelConfigState extends Equatable {
  const AgentModelConfigState({
    this.catalog,
    this.selection = const AgentModelSelection(),
    this.fastEnabled = false,
    this.conflictCode,
    this.saveErrorCode,
  });

  final AgentModelList? catalog;
  final AgentModelSelection selection;
  final bool fastEnabled;
  final String? conflictCode;
  final String? saveErrorCode;

  AgentModelConfigState copyWith({
    AgentModelList? catalog,
    AgentModelSelection? selection,
    bool? fastEnabled,
    String? conflictCode,
    String? saveErrorCode,
    bool clearCatalog = false,
    bool clearConflict = false,
    bool clearSaveError = false,
  }) {
    return AgentModelConfigState(
      catalog: clearCatalog ? null : (catalog ?? this.catalog),
      selection: selection ?? this.selection,
      fastEnabled: fastEnabled ?? this.fastEnabled,
      conflictCode: clearConflict ? null : (conflictCode ?? this.conflictCode),
      saveErrorCode: clearSaveError
          ? null
          : (saveErrorCode ?? this.saveErrorCode),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    catalog,
    selection,
    fastEnabled,
    conflictCode,
    saveErrorCode,
  ];
}

final class AgentHeaderState extends Equatable {
  const AgentHeaderState({
    this.title = '',
    this.threadOpenPhase = AgentThreadOpenPhase.idle,
    this.systemNoticeCode,
    this.statusCapsule,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    this.showRunningIndicator = false,
    this.runningActivity,
    this.segmentStartedAt,
    this.turnStartedAt,
    this.tokenUsage,
    this.isTurnRunning = false,
    this.isReadOnly = false,
    this.canFork = false,
    this.canRename = false,
    this.canArchive = false,
    this.isPlanMode = false,
  });

  final String title;
  final AgentThreadOpenPhase threadOpenPhase;
  final String? systemNoticeCode;
  final AgentStatusCapsule? statusCapsule;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final bool showRunningIndicator;
  final AgentActivityCode? runningActivity;
  final DateTime? segmentStartedAt;
  final DateTime? turnStartedAt;
  final AgentTokenUsage? tokenUsage;
  final bool isTurnRunning;
  final bool isReadOnly;
  final bool canFork;
  final bool canRename;
  final bool canArchive;
  final bool isPlanMode;

  @override
  List<Object?> get props => <Object?>[
    title,
    threadOpenPhase,
    systemNoticeCode,
    statusCapsule,
    waitingOnApproval,
    waitingOnUserInput,
    showRunningIndicator,
    runningActivity,
    segmentStartedAt,
    turnStartedAt,
    tokenUsage,
    isTurnRunning,
    isReadOnly,
    canFork,
    canRename,
    canArchive,
    isPlanMode,
  ];
}

final class AgentComposerState extends Equatable {
  const AgentComposerState({
    this.canSubmitMessage = false,
    this.isTurnRunning = false,
    this.threadOpenPhase = AgentThreadOpenPhase.idle,
    this.contextUsage,
    this.isReadOnly = false,
    this.canAttachImages = false,
    this.canMentionResources = false,
    this.canUseSkills = false,
    this.canCancelTurn = false,
    this.canSteerTurn = false,
    this.conversationModeStatus = AgentConversationModeLoadStatus.unavailable,
    this.conversationModeOptions = const <AgentConversationModePreset>[],
    this.selectedConversationMode,
    this.conversationModeAppliesToNextTurn = true,
    this.conversationModeStatusCode,
    this.showModelSelection = false,
    this.modelConfig = const AgentModelConfigState(),
    this.showPermissionPolicy = false,
    this.permissionOptions = const <AgentPermissionOption>[],
    this.selectedPermissionOptionId,
    this.permissionApplyScopeCode,
    this.sessionConfigOptions = const <AgentSessionConfigOption>[],
    this.skillsCatalog,
    this.unavailableProviderCode,
    this.contextPanelVisible = false,
  });

  final bool canSubmitMessage;
  final bool isTurnRunning;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentTokenUsage? contextUsage;
  final bool isReadOnly;
  final bool canAttachImages;
  final bool canMentionResources;
  final bool canUseSkills;
  final bool canCancelTurn;
  final bool canSteerTurn;
  final AgentConversationModeLoadStatus conversationModeStatus;
  final List<AgentConversationModePreset> conversationModeOptions;
  final AgentConversationModeId? selectedConversationMode;
  final bool conversationModeAppliesToNextTurn;
  final String? conversationModeStatusCode;
  final bool showModelSelection;
  final AgentModelConfigState modelConfig;
  final bool showPermissionPolicy;
  final List<AgentPermissionOption> permissionOptions;
  final String? selectedPermissionOptionId;
  final String? permissionApplyScopeCode;
  final List<AgentSessionConfigOption> sessionConfigOptions;
  final AgentSkillsCatalog? skillsCatalog;
  final String? unavailableProviderCode;
  final bool contextPanelVisible;

  AgentComposerState copyWith({
    bool? canSubmitMessage,
    bool? isTurnRunning,
    AgentThreadOpenPhase? threadOpenPhase,
    AgentTokenUsage? contextUsage,
    bool? isReadOnly,
    bool? canAttachImages,
    bool? canMentionResources,
    bool? canUseSkills,
    bool? canCancelTurn,
    bool? canSteerTurn,
    AgentConversationModeLoadStatus? conversationModeStatus,
    List<AgentConversationModePreset>? conversationModeOptions,
    AgentConversationModeId? selectedConversationMode,
    bool? conversationModeAppliesToNextTurn,
    String? conversationModeStatusCode,
    bool? showModelSelection,
    AgentModelConfigState? modelConfig,
    bool? showPermissionPolicy,
    List<AgentPermissionOption>? permissionOptions,
    String? selectedPermissionOptionId,
    String? permissionApplyScopeCode,
    List<AgentSessionConfigOption>? sessionConfigOptions,
    AgentSkillsCatalog? skillsCatalog,
    String? unavailableProviderCode,
    bool? contextPanelVisible,
    bool clearContextUsage = false,
    bool clearSelectedMode = false,
    bool clearModeStatusCode = false,
    bool clearSelectedPermission = false,
    bool clearPermissionScope = false,
    bool clearSkills = false,
    bool clearUnavailable = false,
  }) {
    return AgentComposerState(
      canSubmitMessage: canSubmitMessage ?? this.canSubmitMessage,
      isTurnRunning: isTurnRunning ?? this.isTurnRunning,
      threadOpenPhase: threadOpenPhase ?? this.threadOpenPhase,
      contextUsage: clearContextUsage
          ? null
          : (contextUsage ?? this.contextUsage),
      isReadOnly: isReadOnly ?? this.isReadOnly,
      canAttachImages: canAttachImages ?? this.canAttachImages,
      canMentionResources: canMentionResources ?? this.canMentionResources,
      canUseSkills: canUseSkills ?? this.canUseSkills,
      canCancelTurn: canCancelTurn ?? this.canCancelTurn,
      canSteerTurn: canSteerTurn ?? this.canSteerTurn,
      conversationModeStatus:
          conversationModeStatus ?? this.conversationModeStatus,
      conversationModeOptions:
          conversationModeOptions ?? this.conversationModeOptions,
      selectedConversationMode: clearSelectedMode
          ? null
          : (selectedConversationMode ?? this.selectedConversationMode),
      conversationModeAppliesToNextTurn:
          conversationModeAppliesToNextTurn ??
          this.conversationModeAppliesToNextTurn,
      conversationModeStatusCode: clearModeStatusCode
          ? null
          : (conversationModeStatusCode ?? this.conversationModeStatusCode),
      showModelSelection: showModelSelection ?? this.showModelSelection,
      modelConfig: modelConfig ?? this.modelConfig,
      showPermissionPolicy: showPermissionPolicy ?? this.showPermissionPolicy,
      permissionOptions: permissionOptions ?? this.permissionOptions,
      selectedPermissionOptionId: clearSelectedPermission
          ? null
          : (selectedPermissionOptionId ?? this.selectedPermissionOptionId),
      permissionApplyScopeCode: clearPermissionScope
          ? null
          : (permissionApplyScopeCode ?? this.permissionApplyScopeCode),
      sessionConfigOptions: sessionConfigOptions ?? this.sessionConfigOptions,
      skillsCatalog: clearSkills ? null : (skillsCatalog ?? this.skillsCatalog),
      unavailableProviderCode: clearUnavailable
          ? null
          : (unavailableProviderCode ?? this.unavailableProviderCode),
      contextPanelVisible: contextPanelVisible ?? this.contextPanelVisible,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    canSubmitMessage,
    isTurnRunning,
    threadOpenPhase,
    contextUsage,
    isReadOnly,
    canAttachImages,
    canMentionResources,
    canUseSkills,
    canCancelTurn,
    canSteerTurn,
    conversationModeStatus,
    conversationModeOptions,
    selectedConversationMode,
    conversationModeAppliesToNextTurn,
    conversationModeStatusCode,
    showModelSelection,
    modelConfig,
    showPermissionPolicy,
    permissionOptions,
    selectedPermissionOptionId,
    permissionApplyScopeCode,
    sessionConfigOptions,
    skillsCatalog,
    unavailableProviderCode,
    contextPanelVisible,
  ];
}

final class AgentPendingInteractionState extends Equatable {
  const AgentPendingInteractionState({
    this.permissions = const <AgentPermissionRequest>[],
    this.questions = const <AgentQuestionRequest>[],
    this.planApprovals = const <AgentPlanApprovalRequest>[],
    this.planExecutionHandoff,
    this.isReadOnly = false,
    this.autoReviewsByTurnId = const <String, AgentAutoApprovalReviewEvent>{},
    this.latestDeniedAutoReview,
  });

  final List<AgentPermissionRequest> permissions;
  final List<AgentQuestionRequest> questions;
  final List<AgentPlanApprovalRequest> planApprovals;
  final AgentPlanExecutionRequest? planExecutionHandoff;
  final bool isReadOnly;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final AgentAutoApprovalReviewEvent? latestDeniedAutoReview;

  bool get isEmpty =>
      permissions.isEmpty &&
      questions.isEmpty &&
      planApprovals.isEmpty &&
      planExecutionHandoff == null;

  bool get blocksComposer => !isEmpty;

  AgentPendingInteractionState copyWith({
    List<AgentPermissionRequest>? permissions,
    List<AgentQuestionRequest>? questions,
    List<AgentPlanApprovalRequest>? planApprovals,
    AgentPlanExecutionRequest? planExecutionHandoff,
    bool? isReadOnly,
    Map<String, AgentAutoApprovalReviewEvent>? autoReviewsByTurnId,
    AgentAutoApprovalReviewEvent? latestDeniedAutoReview,
    bool clearHandoff = false,
    bool clearDeniedReview = false,
  }) {
    return AgentPendingInteractionState(
      permissions: permissions ?? this.permissions,
      questions: questions ?? this.questions,
      planApprovals: planApprovals ?? this.planApprovals,
      planExecutionHandoff: clearHandoff
          ? null
          : (planExecutionHandoff ?? this.planExecutionHandoff),
      isReadOnly: isReadOnly ?? this.isReadOnly,
      autoReviewsByTurnId: autoReviewsByTurnId ?? this.autoReviewsByTurnId,
      latestDeniedAutoReview: clearDeniedReview
          ? null
          : (latestDeniedAutoReview ?? this.latestDeniedAutoReview),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    permissions,
    questions,
    planApprovals,
    planExecutionHandoff,
    isReadOnly,
    autoReviewsByTurnId,
    latestDeniedAutoReview,
  ];
}

final class AgentExpansionState extends Equatable {
  const AgentExpansionState({
    this.toolCallIds = const <String>{},
    this.planMessageIds = const <String>{},
    this.activePlanTurnIds = const <String>{},
    this.commandGroupIds = const <String>{},
    this.fileEditItemIds = const <String>{},
  });

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

  AgentExpansionState copyWith({
    Set<String>? toolCallIds,
    Set<String>? planMessageIds,
    Set<String>? activePlanTurnIds,
    Set<String>? commandGroupIds,
    Set<String>? fileEditItemIds,
  }) {
    return AgentExpansionState(
      toolCallIds: toolCallIds ?? this.toolCallIds,
      planMessageIds: planMessageIds ?? this.planMessageIds,
      activePlanTurnIds: activePlanTurnIds ?? this.activePlanTurnIds,
      commandGroupIds: commandGroupIds ?? this.commandGroupIds,
      fileEditItemIds: fileEditItemIds ?? this.fileEditItemIds,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    toolCallIds,
    planMessageIds,
    activePlanTurnIds,
    commandGroupIds,
    fileEditItemIds,
  ];
}

final class AgentConversationHistoryState extends Equatable {
  const AgentConversationHistoryState({
    this.standbyTurn,
    this.visibleTurns = const <AgentConversationTurnGroup>[],
    this.threadOpenPhase = AgentThreadOpenPhase.idle,
    this.providerId = '',
    this.providerKind = AgentProviderKind.codexAppServer,
    this.providerName = '',
    this.visibleLimit = 50,
  });

  final AgentConversationTurnGroup? standbyTurn;
  final List<AgentConversationTurnGroup> visibleTurns;
  final AgentThreadOpenPhase threadOpenPhase;
  final String providerId;
  final AgentProviderKind providerKind;
  final String providerName;
  final int visibleLimit;

  bool get isLoading => threadOpenPhase == AgentThreadOpenPhase.loadingHistory;

  AgentConversationHistoryState copyWith({
    AgentConversationTurnGroup? standbyTurn,
    List<AgentConversationTurnGroup>? visibleTurns,
    AgentThreadOpenPhase? threadOpenPhase,
    String? providerId,
    AgentProviderKind? providerKind,
    String? providerName,
    int? visibleLimit,
    bool clearStandby = false,
  }) {
    return AgentConversationHistoryState(
      standbyTurn: clearStandby ? null : (standbyTurn ?? this.standbyTurn),
      visibleTurns: visibleTurns ?? this.visibleTurns,
      threadOpenPhase: threadOpenPhase ?? this.threadOpenPhase,
      providerId: providerId ?? this.providerId,
      providerKind: providerKind ?? this.providerKind,
      providerName: providerName ?? this.providerName,
      visibleLimit: visibleLimit ?? this.visibleLimit,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    standbyTurn,
    visibleTurns,
    threadOpenPhase,
    providerId,
    providerKind,
    providerName,
    visibleLimit,
  ];
}

final class AgentConversationState extends Equatable {
  const AgentConversationState({
    this.key = const ConversationKey.draft(providerId: '', entryId: ''),
    this.status = AgentConversationStatus.initial,
    this.header = const AgentHeaderState(),
    this.composer = const AgentComposerState(),
    this.pending = const AgentPendingInteractionState(),
    this.expansion = const AgentExpansionState(),
    this.history = const AgentConversationHistoryState(),
    this.failure,
    this.generation = 0,
  });

  final ConversationKey key;
  final AgentConversationStatus status;
  final AgentHeaderState header;
  final AgentComposerState composer;
  final AgentPendingInteractionState pending;
  final AgentExpansionState expansion;
  final AgentConversationHistoryState history;
  final AgentConversationFailure? failure;
  final int generation;

  AgentConversationState copyWith({
    ConversationKey? key,
    AgentConversationStatus? status,
    AgentHeaderState? header,
    AgentComposerState? composer,
    AgentPendingInteractionState? pending,
    AgentExpansionState? expansion,
    AgentConversationHistoryState? history,
    AgentConversationFailure? failure,
    int? generation,
    bool clearFailure = false,
  }) {
    return AgentConversationState(
      key: key ?? this.key,
      status: status ?? this.status,
      header: header ?? this.header,
      composer: composer ?? this.composer,
      pending: pending ?? this.pending,
      expansion: expansion ?? this.expansion,
      history: history ?? this.history,
      failure: clearFailure ? null : (failure ?? this.failure),
      generation: generation ?? this.generation,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    key,
    status,
    header,
    composer,
    pending,
    expansion,
    history,
    failure,
    generation,
  ];
}

import 'package:flutter/foundation.dart';

import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_port.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_composer_state_owner.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_ports.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_model_config_ui_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_ui_update_scheduler.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_corpus_port.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/features/agent/presentation/agent_flutter_listenable_adapter.dart';
import 'package:zeta/src/features/agent/presentation/agent_ui_update_scheduler.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

/// Presentation 门面：持有 application [AgentConversationRuntimeController]，
/// 并提供 Flutter listenable 适配与上下文面板这种 Widget-scope 状态。
class AgentConversationViewModel
    implements AgentConversationRegionSource, AgentConversationCommandPort {
  AgentConversationViewModel({
    required AgentProviderSettingsPort providerController,
    required AgentConversationBinding conversationBinding,
    required AgentProviderGlobalRuntime globalRuntime,
    required AgentConversationComposerStateOwner composerStateOwner,
    AgentUiTextCatalog? textCatalog,
    AgentConversationTimelineStore? timelineStore,
    WorkspaceFileCorpusPort? workspaceFileCorpus,
    AgentTurnTerminalCallback? onTurnTerminal,
    AgentAttentionCallback? onAttention,
    Future<void> Function(String providerId)? onProviderSwitchRequested,
    AgentCreatedThreadCallback? onCreatedThread,
    AgentTurnContextStore? turnContextStore,
    String? initialProjectPath,
    String? initialContextFilePath,
    AgentThreadSummary? initialThread,
    AgentFrameScheduler? uiFrameScheduler,
    ZetaMetricsPort metrics = noopZetaMetricsPort,
    ZetaMetricLabel Function(String providerId) providerMetricLabel =
        ZetaMetricLabel.hashed,
  }) : _runtime = AgentConversationRuntimeController(
         providerController: providerController,
         conversationBinding: conversationBinding,
         globalRuntime: globalRuntime,
         composerStateOwner: composerStateOwner,
         textCatalog: textCatalog,
         timelineStore: timelineStore,
         workspaceFileCorpus: workspaceFileCorpus,
         onTurnTerminal: onTurnTerminal,
         onAttention: onAttention,
         onProviderSwitchRequested: onProviderSwitchRequested,
         onCreatedThread: onCreatedThread,
         turnContextStore: turnContextStore,
         initialProjectPath: initialProjectPath,
         initialContextFilePath: initialContextFilePath,
         initialThread: initialThread,
         uiFrameScheduler:
             uiFrameScheduler ?? const SchedulerBindingAgentFrameScheduler(),
         metrics: metrics,
         providerMetricLabel: providerMetricLabel,
       ) {
    _header = ValueNotifier<AgentHeaderState>(_runtime.headerState);
    _composer = ValueNotifier<AgentComposerState>(_runtime.composerState);
    _pending = ValueNotifier<AgentPendingInteractionState>(
      _runtime.pendingInteractionState,
    );
    _expansion = ValueNotifier<AgentExpansionState>(_runtime.expansionState);
    _history = ValueNotifier<AgentConversationHistoryState>(
      _runtime.historyState,
    );
    _runtime.addUiUpdateListener(_syncRegionListenables);
  }

  static const String defaultThreadTitle =
      AgentConversationRuntimeController.defaultThreadTitle;
  static const String planExecutionPrompt =
      AgentConversationRuntimeController.planExecutionPrompt;

  final AgentConversationRuntimeController _runtime;

  /// application runtime owner；装配切片时用这个，不要再绕 ViewModel。
  AgentConversationRuntimeController get runtime => _runtime;

  ZetaMetricsPort get metrics => _runtime.metrics;

  WorkspaceFileCorpusPort? get workspaceFileCorpus =>
      _runtime.workspaceFileCorpus;

  AgentTurnTerminalCallback? get onTurnTerminal => _runtime.onTurnTerminal;

  AgentAttentionCallback? get onAttention => _runtime.onAttention;

  Future<void> Function(String providerId)? get onProviderSwitchRequested =>
      _runtime.onProviderSwitchRequested;

  AgentCreatedThreadCallback? get onCreatedThread => _runtime.onCreatedThread;

  AgentTurnContextStore? get turnContextStore => _runtime.turnContextStore;

  AgentProviderSettingsPort get providerController =>
      _runtime.providerController;

  AgentConversationBinding get conversationBinding =>
      _runtime.conversationBinding;

  AgentProviderGlobalRuntime get globalRuntime => _runtime.globalRuntime;

  final ValueNotifier<bool> contextPanelVisible = ValueNotifier<bool>(false);
  late final ValueNotifier<AgentHeaderState> _header;
  late final ValueNotifier<AgentComposerState> _composer;
  late final ValueNotifier<AgentPendingInteractionState> _pending;
  late final ValueNotifier<AgentExpansionState> _expansion;
  late final ValueNotifier<AgentConversationHistoryState> _history;

  ValueListenable<AgentHeaderState> get headerStateListenable => _header;
  ValueListenable<AgentComposerState> get composerStateListenable => _composer;
  ValueListenable<AgentPendingInteractionState>
  get pendingInteractionStateListenable => _pending;
  ValueListenable<AgentExpansionState> get expansionStateListenable =>
      _expansion;
  ValueListenable<AgentConversationHistoryState> get historyStateListenable =>
      _history;

  ValueListenable<AgentConversationTurnState?> get liveTurnListenable =>
      AgentFlutterValueListenableAdapter(_runtime.liveTurnListenable);

  ValueListenable<AgentConversationThreadSnapshot>
  get threadSnapshotListenable =>
      AgentFlutterValueListenableAdapter(_runtime.threadSnapshotListenable);

  Listenable get elapsedClockListenable =>
      AgentFlutterListenableAdapter(_runtime.elapsedClockListenable);

  void toggleContextPanel() {
    contextPanelVisible.value = !contextPanelVisible.value;
  }

  void hideContextPanel() {
    contextPanelVisible.value = false;
  }

  void _syncRegionListenables(AgentUiUpdateRequest request) {
    if (request.regions.contains(AgentUiRegion.header)) {
      final next = _runtime.headerState;
      if (_header.value != next) {
        _header.value = next;
      }
    }
    if (request.regions.contains(AgentUiRegion.composer)) {
      final next = _runtime.composerState;
      if (_composer.value != next) {
        _composer.value = next;
      }
    }
    if (request.regions.contains(AgentUiRegion.pendingInteraction)) {
      final next = _runtime.pendingInteractionState;
      if (_pending.value != next) {
        _pending.value = next;
      }
    }
    if (request.regions.contains(AgentUiRegion.expansion)) {
      final next = _runtime.expansionState;
      if (_expansion.value != next) {
        _expansion.value = next;
      }
    }
    if (request.regions.contains(AgentUiRegion.history)) {
      final next = _runtime.historyState;
      if (_history.value != next) {
        _history.value = next;
      }
    }
  }

  bool get isWorkspaceFileIndexReady => _runtime.isWorkspaceFileIndexReady;

  List<AgentConversationMessage> get messages => _runtime.messages;

  Future<void> get initialization => _runtime.initialization;

  List<AgentToolCall> get toolCalls => _runtime.toolCalls;

  List<AgentPermissionRequest> get permissionRequests =>
      _runtime.permissionRequests;

  List<AgentQuestionRequest> get questionRequests => _runtime.questionRequests;

  List<AgentPlanApprovalRequest> get planApprovalRequests =>
      _runtime.planApprovalRequests;

  AgentPlanExecutionRequest? get planExecutionRequest =>
      _runtime.planExecutionRequest;

  List<AgentTimelineEntry> get timelineEntries => _runtime.timelineEntries;

  List<AgentConversationTurnGroup> get conversationTurns =>
      _runtime.conversationTurns;

  List<AgentConversationTurnGroup> get visibleHistoryTurns =>
      _runtime.visibleHistoryTurns;

  AgentConversationTurnState? get standbyTurnState => _runtime.standbyTurnState;

  List<AgentConversationTurnState> get visibleHistoryTurnStates =>
      _runtime.visibleHistoryTurnStates;

  AgentConversationTurnState? get liveTurnState => _runtime.liveTurnState;

  List<AgentPlanEntry> get activePlanEntries => _runtime.activePlanEntries;

  bool get shouldShowActivePlan => _runtime.shouldShowActivePlan;

  AgentProviderStatus get status => _runtime.status;

  AgentThreadRuntimeStatus? get threadRuntimeStatus =>
      _runtime.threadRuntimeStatus;

  bool get threadWaitingOnApproval => _runtime.threadWaitingOnApproval;

  bool get threadWaitingOnUserInput => _runtime.threadWaitingOnUserInput;

  String? get threadStatusCapsuleLabel => _runtime.threadStatusCapsuleLabel;

  String? get systemNoticeLabel => _runtime.systemNoticeLabel;

  @visibleForTesting
  CoalescingEventBufferDiagnostics? get eventCoalescingBufferDiagnostics =>
      _runtime.eventCoalescingBufferDiagnostics;

  @visibleForTesting
  BoundedEventDispatcherDiagnostics? get eventDispatcherDiagnostics =>
      _runtime.eventDispatcherDiagnostics;

  @visibleForTesting
  AgentEventPipelineDiagnostics? get eventPipelineDiagnostics =>
      _runtime.eventPipelineDiagnostics;

  @visibleForTesting
  AgentUiUpdateSchedulerDiagnostics get uiStateDiagnostics =>
      _runtime.uiStateDiagnostics;

  @visibleForTesting
  AgentUiUpdateSchedulerDiagnostics get uiUpdateSchedulerDiagnostics =>
      _runtime.uiUpdateSchedulerDiagnostics;

  @visibleForTesting
  AgentUiUpdateRequest? get debugLastUiUpdateRequest =>
      _runtime.debugLastUiUpdateRequest;

  @override
  AgentConversationHistoryState get historyState => _runtime.historyState;

  @override
  AgentHeaderState get headerState => _runtime.headerState;

  @override
  AgentComposerState get composerState => _runtime.composerState;

  @override
  AgentPendingInteractionState get pendingInteractionState =>
      _runtime.pendingInteractionState;

  @override
  AgentExpansionState get expansionState => _runtime.expansionState;

  Stream<AgentUiEffect> get uiEffects => _runtime.uiEffects;

  String? get projectPath => _runtime.projectPath;

  String? get contextFilePath => _runtime.contextFilePath;

  String get activeProviderId => _runtime.activeProviderId;

  String get activeProviderName => _runtime.activeProviderName;

  AgentProviderCapabilities get activeCapabilities =>
      _runtime.activeCapabilities;

  bool get canSelectConversationMode => _runtime.canSelectConversationMode;

  bool get isPlanMode => _runtime.isPlanMode;

  AgentConversationModeLoadStatus get conversationModeLoadStatus =>
      _runtime.conversationModeLoadStatus;

  Object get conversationModeContextId => _runtime.conversationModeContextId;

  List<AgentConversationModePreset> get conversationModeOptions =>
      _runtime.conversationModeOptions;

  AgentConversationModeId? get selectedConversationMode =>
      _runtime.selectedConversationMode;

  String? get conversationModeStatusMessage =>
      _runtime.conversationModeStatusMessage;

  bool get conversationModeAppliesToNextTurn =>
      _runtime.conversationModeAppliesToNextTurn;

  List<AgentModelInfo> get models => _runtime.models;

  List<AgentSessionConfigOption> get sessionConfigOptions =>
      _runtime.sessionConfigOptions;

  AgentModelInfo? get selectedModel => _runtime.selectedModel;

  String? get selectedModelId => _runtime.selectedModelId;

  String? get selectedReasoningEffort => _runtime.selectedReasoningEffort;

  String? get selectedServiceTierId => _runtime.selectedServiceTierId;

  AgentModelConfigUiState get modelConfigUiState => _runtime.modelConfigUiState;

  bool get showReasoningEffort => _runtime.showReasoningEffort;

  bool get showServiceTier => _runtime.showServiceTier;

  bool get showPermissionPolicy => _runtime.showPermissionPolicy;

  bool get showModelSelection => _runtime.showModelSelection;

  bool get canAttachImages => _runtime.canAttachImages;

  bool get canMentionResources => _runtime.canMentionResources;

  bool get canUseSkills => _runtime.canUseSkills;

  bool get canRenameCurrentThread => _runtime.canRenameCurrentThread;

  bool get canArchiveCurrentThread => _runtime.canArchiveCurrentThread;

  bool get canCompactCurrentThread => _runtime.canCompactCurrentThread;

  bool get canForkCurrentThread => _runtime.canForkCurrentThread;

  List<AgentProviderConfig> get availableProviders =>
      _runtime.availableProviders;

  AgentPermissionSelection? get permissionSelection =>
      _runtime.permissionSelection;

  String get permissionPolicyLabel => _runtime.permissionPolicyLabel;

  String? get permissionApplyScopeHint => _runtime.permissionApplyScopeHint;

  bool get canRetryPermissionPreferencePersistence =>
      _runtime.canRetryPermissionPreferencePersistence;

  AgentAutoApprovalReviewEvent? get latestDeniedAutoReview =>
      _runtime.latestDeniedAutoReview;

  String? get sessionId => _runtime.sessionId;

  AgentConversationThreadSnapshot get threadSnapshot => _runtime.threadSnapshot;

  AgentSession? get currentSession => _runtime.currentSession;

  bool get isReadOnly => _runtime.isReadOnly;

  String get currentThreadTitle => _runtime.currentThreadTitle;

  String get currentThreadPreview => _runtime.currentThreadPreview;

  String get threadProviderId => _runtime.threadProviderId;

  bool get showRunningIndicator => _runtime.showRunningIndicator;

  String? get projectName => _runtime.projectName;

  DateTime get elapsedNow => _runtime.elapsedNow;

  AgentTurnActivitySnapshot get currentActivity => _runtime.currentActivity;

  DateTime? get currentTurnStartedAt => _runtime.currentTurnStartedAt;

  AgentUiTextCatalog get textCatalog => _runtime.textCatalog;

  String? get runningActivityLabel => _runtime.runningActivityLabel;

  AgentThreadOpenPhase get threadOpenPhase => _runtime.threadOpenPhase;

  bool get requiresResumedSelectedThread =>
      _runtime.requiresResumedSelectedThread;

  AgentTokenUsage? get currentThreadTokenUsage =>
      _runtime.currentThreadTokenUsage;

  AgentTokenUsage? get currentThreadLastTokenUsage =>
      _runtime.currentThreadLastTokenUsage;

  DateTime? get threadCreatedAt => _runtime.threadCreatedAt;

  DateTime? get threadLastActiveAt => _runtime.threadLastActiveAt;

  bool get canEditLastUserMessage => _runtime.canEditLastUserMessage;

  String? get lastEditableUserMessageText =>
      _runtime.lastEditableUserMessageText;

  String? get lastEditableUserMessageId => _runtime.lastEditableUserMessageId;

  bool get isTurnRunning => _runtime.isTurnRunning;

  bool get isRunning => _runtime.isRunning;

  bool get canSubmitMessage => _runtime.canSubmitMessage;

  void selectConversationMode(AgentConversationModeId modeId) =>
      _runtime.selectConversationMode(modeId);

  @override
  Future<AgentCommandOutcome> startPlanExecution(
    AgentPlanExecutionRequest request,
  ) => _runtime.startPlanExecution(request);

  void selectPlanExecutionPermissionOption(
    AgentPlanExecutionRequest request,
    AgentPermissionOption option,
  ) => _runtime.selectPlanExecutionPermissionOption(request, option);

  @override
  Future<AgentCommandOutcome> revisePlanExecution(
    AgentPlanExecutionRequest request, {
    String? revisionMessage,
  }) => _runtime.revisePlanExecution(request, revisionMessage: revisionMessage);

  @override
  void dismissPlanExecution(AgentPlanExecutionRequest request) =>
      _runtime.dismissPlanExecution(request);

  @override
  Future<AgentCommandOutcome> retryConversationModes() =>
      _runtime.retryConversationModes();

  List<AgentSkillMetadata> skillCandidates({String query = ''}) =>
      _runtime.skillCandidates(query: query);

  @override
  Future<AgentCommandOutcome> ensureSkillsCatalog() =>
      _runtime.ensureSkillsCatalog();

  Future<void> switchActiveProvider(String providerId) =>
      _runtime.switchActiveProvider(providerId);

  AgentPermissionRequestSnapshot permissionSnapshotForThread(
    String? threadId,
  ) => _runtime.permissionSnapshotForThread(threadId);

  AgentAutoApprovalReviewEvent? autoReviewForTurn(String? turnId) =>
      _runtime.autoReviewForTurn(turnId);

  List<WorkspaceNode> mentionCandidateFiles({String query = ''}) =>
      _runtime.mentionCandidateFiles(query: query);

  Duration? turnElapsedAt(DateTime now) => _runtime.turnElapsedAt(now);

  Duration? segmentElapsedAt(DateTime now) => _runtime.segmentElapsedAt(now);

  Duration? toolElapsedAt(AgentToolCall toolCall, DateTime now) =>
      _runtime.toolElapsedAt(toolCall, now);

  bool isToolCallExpanded(String toolCallId) =>
      _runtime.isToolCallExpanded(toolCallId);

  bool isPlanMessageExpanded(String messageId) =>
      _runtime.isPlanMessageExpanded(messageId);

  bool isActivePlanExpanded(String turnId) =>
      _runtime.isActivePlanExpanded(turnId);

  bool isCommandGroupExpanded(String commandGroupId) =>
      _runtime.isCommandGroupExpanded(commandGroupId);

  bool isFileEditItemExpanded(String fileEditItemId) =>
      _runtime.isFileEditItemExpanded(fileEditItemId);

  @override
  void toggleToolCall(String toolCallId) => _runtime.toggleToolCall(toolCallId);

  @override
  void togglePlanMessage(String messageId) =>
      _runtime.togglePlanMessage(messageId);

  @override
  void toggleActivePlan(String turnId) => _runtime.toggleActivePlan(turnId);

  @override
  void toggleCommandGroup(String commandGroupId) =>
      _runtime.toggleCommandGroup(commandGroupId);

  @override
  void toggleFileEditItem(String fileEditItemId) =>
      _runtime.toggleFileEditItem(fileEditItemId);

  Future<void> loadSettings() => _runtime.loadSettings();

  @override
  Future<AgentCommandOutcome> loadModels({bool forceRefresh = false}) =>
      _runtime.loadModels(forceRefresh: forceRefresh);

  Future<bool> selectModel(String modelId) => _runtime.selectModel(modelId);

  Future<bool> selectReasoningEffort(String? effort) =>
      _runtime.selectReasoningEffort(effort);

  Future<String?> selectPermissionOption(AgentPermissionOption option) =>
      _runtime.selectPermissionOption(option);

  String? takePermissionApplyHint() => _runtime.takePermissionApplyHint();

  Future<bool> retryPermissionPreferencePersistence() =>
      _runtime.retryPermissionPreferencePersistence();

  @override
  Future<AgentCommandOutcome> approveGuardianDeniedAction() =>
      _runtime.approveGuardianDeniedAction();

  Future<bool> selectFastEnabled(bool enabled) =>
      _runtime.selectFastEnabled(enabled);

  Future<bool> resolveModelCompatibilityConflict() =>
      _runtime.resolveModelCompatibilityConflict();

  Future<bool> retryModelConfigurationSave() =>
      _runtime.retryModelConfigurationSave();

  void clearModelConfigurationTransientState() =>
      _runtime.clearModelConfigurationTransientState();

  Future<void> selectSessionConfigOption(String configId, Object value) =>
      _runtime.selectSessionConfigOption(configId, value);

  void updateContext({
    required String? projectPath,
    required String? contextFilePath,
  }) => _runtime.updateContext(
    projectPath: projectPath,
    contextFilePath: contextFilePath,
  );

  @override
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const <String>[],
    List<({String name, String path})> mentions =
        const <({String name, String path})>[],
    List<AgentSkillRef> skills = const <AgentSkillRef>[],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  }) => _runtime.sendMessage(
    text,
    localImagePaths: localImagePaths,
    mentions: mentions,
    skills: skills,
    permissionSnapshotOverride: permissionSnapshotOverride,
  );

  @override
  Future<AgentCommandOutcome> cancelActiveTurn() => _runtime.cancelActiveTurn();

  @override
  Future<AgentCommandOutcome> retryOpenThread() => _runtime.retryOpenThread();

  @override
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const <String>[],
  }) => _runtime.respondToPermission(
    request,
    approved: approved,
    cancelTurn: cancelTurn,
    commandDecision: commandDecision,
    execpolicyAmendment: execpolicyAmendment,
  );

  @override
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const <String, List<String>>{},
  }) => _runtime.respondToQuestion(request, answers: answers);

  @override
  Future<AgentCommandOutcome> respondToPlanApproval(
    AgentPlanApprovalRequest request,
    AgentPlanApprovalDecisionKind kind, {
    String? reason,
  }) => _runtime.respondToPlanApproval(request, kind, reason: reason);

  @override
  Future<AgentCommandOutcome> editLastUserMessageAndRetry(String newText) =>
      _runtime.editLastUserMessageAndRetry(newText);

  @override
  Future<AgentSession?> forkCurrentThread() => _runtime.forkCurrentThread();

  @override
  Future<AgentCommandOutcome> renameCurrentThread(String name) =>
      _runtime.renameCurrentThread(name);

  @override
  Future<AgentCommandOutcome> archiveCurrentThread() =>
      _runtime.archiveCurrentThread();

  @override
  Future<AgentCommandOutcome> compactCurrentThread() =>
      _runtime.compactCurrentThread();

  void syncThreadTitleIfCurrent(String threadId, String title) =>
      _runtime.syncThreadTitleIfCurrent(threadId, title);

  @override
  void addUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  ) => _runtime.addUiUpdateListener(listener);

  @override
  void removeUiUpdateListener(
    void Function(AgentUiUpdateRequest request) listener,
  ) => _runtime.removeUiUpdateListener(listener);

  @override
  AgentConversationCommandScope currentCommandScope() =>
      _runtime.currentCommandScope();

  void dispose() {
    _runtime.removeUiUpdateListener(_syncRegionListenables);
    _header.dispose();
    _composer.dispose();
    _pending.dispose();
    _expansion.dispose();
    _history.dispose();
    contextPanelVisible.dispose();
    _runtime.dispose();
  }
}

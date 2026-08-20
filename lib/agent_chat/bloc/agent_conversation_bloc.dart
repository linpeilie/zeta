import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart'
    hide AgentPlanExecutionRequest;
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_event.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class AgentConversationBloc
    extends Bloc<AgentConversationEvent, AgentConversationState> {
  AgentConversationBloc({
    required AgentProviderRepository agentProviderRepository,
    required AgentConversationRepository agentConversationRepository,
  }) : _agentProviderRepository = agentProviderRepository,
       _agentConversationRepository = agentConversationRepository,
       super(const AgentConversationState()) {
    on<AgentConversationOpened>(_onOpened, transformer: restartable());
    on<AgentProviderSwitched>(_onOpenedFromSwitch, transformer: restartable());
    on<AgentConversationClosed>(_onClosed, transformer: sequential());
    on<AgentContextUpdated>(_onContextUpdated, transformer: sequential());
    on<AgentConversationSnapshotUpdated>(
      _onSnapshotUpdated,
      transformer: restartable(),
    );
    on<AgentMessageSubmitted>(_onMessageSubmitted, transformer: sequential());
    on<AgentTurnCancelled>(_onTurnCancelled, transformer: sequential());
    on<AgentTurnSteered>(_onTurnSteered, transformer: sequential());
    on<AgentLastUserMessageEdited>(
      _onLastUserMessageEdited,
      transformer: sequential(),
    );
    on<AgentThreadForked>(_onThreadForked, transformer: droppable());
    on<AgentThreadRenamed>(_onThreadRenamed, transformer: sequential());
    on<AgentThreadArchived>(_onThreadArchived, transformer: sequential());
    on<AgentThreadCompacted>(_onThreadCompacted, transformer: sequential());
    on<AgentPermissionResponded>(
      _onPermissionResponded,
      transformer: sequential(),
    );
    on<AgentQuestionResponded>(_onQuestionResponded, transformer: sequential());
    on<AgentPlanApprovalResponded>(
      _onPlanApprovalResponded,
      transformer: sequential(),
    );
    on<AgentPlanExecutionStarted>(
      _onPlanExecutionStarted,
      transformer: sequential(),
    );
    on<AgentPlanExecutionRevised>(_onPlanExecutionRevised);
    on<AgentPlanExecutionDismissed>(_onPlanExecutionDismissed);
    on<AgentDeniedActionApproved>(
      _onDeniedActionApproved,
      transformer: sequential(),
    );
    on<AgentModelSelected>(_onModelSelected, transformer: restartable());
    on<AgentReasoningEffortSelected>(
      _onReasoningEffortSelected,
      transformer: restartable(),
    );
    on<AgentServiceTierSelected>(
      _onServiceTierSelected,
      transformer: restartable(),
    );
    on<AgentFastToggled>(_onFastToggled, transformer: restartable());
    on<AgentModelConflictResolved>(
      _onModelConflictResolved,
      transformer: sequential(),
    );
    on<AgentModelConfigSaveRetried>(
      _onModelConfigSaveRetried,
      transformer: droppable(),
    );
    on<AgentModelConfigTransientCleared>(_onModelConfigTransientCleared);
    on<AgentPermissionOptionSelected>(
      _onPermissionOptionSelected,
      transformer: sequential(),
    );
    on<AgentPermissionPersistenceRetried>(
      _onPermissionPersistenceRetried,
      transformer: droppable(),
    );
    on<AgentConversationModeSelected>(_onConversationModeSelected);
    on<AgentConversationModesRetried>(
      _onConversationModesRetried,
      transformer: droppable(),
    );
    on<AgentSessionConfigOptionSelected>(
      _onSessionConfigOptionSelected,
      transformer: sequential(),
    );
    on<AgentPlanExecutionPermissionSelected>(
      _onPlanExecutionPermissionSelected,
    );
    on<AgentModelsRequested>(_onModelsRequested, transformer: restartable());
    on<AgentSkillsCatalogRequested>(
      _onSkillsCatalogRequested,
      transformer: droppable(),
    );
    on<AgentSettingsRequested>(
      _onSettingsRequested,
      transformer: restartable(),
    );
    on<AgentToolCallToggled>(_onToolCallToggled);
    on<AgentPlanMessageToggled>(_onPlanMessageToggled);
    on<AgentActivePlanToggled>(_onActivePlanToggled);
    on<AgentCommandGroupToggled>(_onCommandGroupToggled);
    on<AgentFileEditItemToggled>(_onFileEditItemToggled);
    on<AgentContextPanelToggled>(_onContextPanelToggled);
    on<AgentHistoryWindowChanged>(_onHistoryWindowChanged);
  }

  final AgentProviderRepository _agentProviderRepository;
  final AgentConversationRepository _agentConversationRepository;
  StreamSubscription<ConversationSnapshot>? _snapshotSubscription;
  StreamSubscription<ProviderConfigSnapshot>? _configSubscription;
  ConversationHandle? _handle;
  AgentProviderBundle? _bundle;
  AgentContext _context = const AgentContext();
  var _generation = 0;

  Future<void> _onOpened(
    AgentConversationOpened event,
    Emitter<AgentConversationState> emit,
  ) {
    return _open(event.key, event.context, emit);
  }

  Future<void> _onOpenedFromSwitch(
    AgentProviderSwitched event,
    Emitter<AgentConversationState> emit,
  ) {
    return _open(event.key, event.context, emit);
  }

  Future<void> _open(
    ConversationKey key,
    AgentContext context,
    Emitter<AgentConversationState> emit,
  ) async {
    final generation = ++_generation;
    _context = context;
    await _detachCurrent();
    emit(
      state.copyWith(
        key: key,
        status: AgentConversationStatus.opening,
        generation: generation,
        clearFailure: true,
      ),
    );
    try {
      final bundle = _agentProviderRepository.bundleFor(key.providerId);
      final handle = await _agentConversationRepository.openConversation(
        bundle: bundle,
        key: key,
        context: context,
      );
      if (generation != _generation) {
        await handle.release();
        return;
      }
      _bundle = bundle;
      _handle = handle;
      _snapshotSubscription = _agentConversationRepository
          .snapshots(key)
          .listen(
            (snapshot) => add(
              AgentConversationSnapshotUpdated(
                snapshot: snapshot,
                generation: generation,
              ),
            ),
          );
      _configSubscription ??= _agentProviderRepository.configChanges.listen(
        (_) => add(const AgentSettingsRequested()),
      );
      if (emit.isDone || generation != _generation) {
        return;
      }
      emit(
        _reduceSnapshot(
          _agentConversationRepository.snapshotOf(key),
          generation: generation,
        ),
      );
      add(const AgentSettingsRequested());
    } on Object catch (error) {
      if (emit.isDone || generation != _generation) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentConversationStatus.failure,
          failure: _mapError(error),
        ),
      );
    }
  }

  Future<void> _onClosed(
    AgentConversationClosed event,
    Emitter<AgentConversationState> emit,
  ) async {
    final key = state.key;
    await _detachCurrent();
    try {
      await _agentConversationRepository.closeConversation(key);
    } on Object {
      // The conversation may already be closed with the handle.
    }
    if (emit.isDone) {
      return;
    }
    emit(const AgentConversationState());
  }

  Future<void> _onContextUpdated(
    AgentContextUpdated event,
    Emitter<AgentConversationState> emit,
  ) async {
    _context = event.context;
    if (state.status != AgentConversationStatus.ready) {
      return;
    }
    await _open(state.key, event.context, emit);
  }

  void _onSnapshotUpdated(
    AgentConversationSnapshotUpdated event,
    Emitter<AgentConversationState> emit,
  ) {
    if (event.generation != _generation) {
      return;
    }
    emit(_reduceSnapshot(event.snapshot, generation: event.generation));
  }

  Future<void> _onMessageSubmitted(
    AgentMessageSubmitted event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () {
      return _agentConversationRepository.submit(
        key: state.key,
        request: TurnRequest(
          message: event.message,
          inputs: event.inputs,
          clientUserMessageId: event.clientUserMessageId,
          configuration: AgentTurnConfiguration(
            conversationMode: _modeSelection(),
          ),
          context: _context,
        ),
      );
    });
  }

  Future<void> _onTurnCancelled(
    AgentTurnCancelled event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () {
      return _agentConversationRepository.cancel(state.key);
    });
  }

  Future<void> _onTurnSteered(
    AgentTurnSteered event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () {
      return _agentConversationRepository.steer(
        key: state.key,
        request: SteerRequest(message: event.message, inputs: event.inputs),
      );
    });
  }

  Future<void> _onLastUserMessageEdited(
    AgentLastUserMessageEdited event,
    Emitter<AgentConversationState> emit,
  ) async {
    await _onThreadForked(const AgentThreadForked(), emit);
    if (state.status == AgentConversationStatus.failure) {
      return;
    }
    await _onMessageSubmitted(
      AgentMessageSubmitted(message: event.message),
      emit,
    );
  }

  Future<void> _onThreadForked(
    AgentThreadForked event,
    Emitter<AgentConversationState> emit,
  ) {
    return _runPort(emit, (bundle, threadId) {
      final port = bundle.threadBranching;
      if (port == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      return port.forkThread(threadId: threadId, context: _context);
    });
  }

  Future<void> _onThreadRenamed(
    AgentThreadRenamed event,
    Emitter<AgentConversationState> emit,
  ) {
    return _runPort(emit, (bundle, threadId) {
      final port = bundle.threadNaming;
      if (port == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      return port.renameThread(threadId: threadId, name: event.name);
    });
  }

  Future<void> _onThreadArchived(
    AgentThreadArchived event,
    Emitter<AgentConversationState> emit,
  ) {
    return _runPort(emit, (bundle, threadId) {
      final port = bundle.threadArchival;
      if (port == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      return port.archiveThread(threadId);
    });
  }

  Future<void> _onThreadCompacted(
    AgentThreadCompacted event,
    Emitter<AgentConversationState> emit,
  ) {
    return _runPort(emit, (bundle, threadId) {
      final port = bundle.threadCompaction;
      if (port == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      return port.compactThread(threadId);
    });
  }

  Future<void> _onPermissionResponded(
    AgentPermissionResponded event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () {
      return _agentConversationRepository.respondToPermission(
        state.key,
        event.decision,
      );
    });
  }

  Future<void> _onQuestionResponded(
    AgentQuestionResponded event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () {
      return _agentConversationRepository.respondToQuestion(
        state.key,
        event.response,
      );
    });
  }

  Future<void> _onPlanApprovalResponded(
    AgentPlanApprovalResponded event,
    Emitter<AgentConversationState> emit,
  ) async {
    final request = _planApproval(event.decision.requestId);
    await _run(emit, () {
      return _agentConversationRepository.respondToPlanApproval(
        state.key,
        event.decision,
      );
    });
    if (state.status == AgentConversationStatus.failure ||
        request == null ||
        event.decision.kind != AgentPlanApprovalDecisionKind.accepted ||
        request.continuation !=
            AgentPlanApprovalContinuation.localExecutionHandoff) {
      return;
    }
    emit(
      state.copyWith(
        pending: state.pending.copyWith(
          planExecutionHandoff: AgentPlanExecutionRequest(
            id: 'handoff-${request.id}',
            sessionId: request.sessionId ?? '',
            turnId: request.turnId ?? '',
            title: request.title ?? '',
            markdown: request.markdown,
            messageId: request.id,
          ),
        ),
      ),
    );
  }

  void _onPlanExecutionRevised(
    AgentPlanExecutionRevised event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(state.copyWith(pending: state.pending.copyWith(clearHandoff: true)));
  }

  void _onPlanExecutionDismissed(
    AgentPlanExecutionDismissed event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(state.copyWith(pending: state.pending.copyWith(clearHandoff: true)));
  }

  Future<void> _onPlanExecutionStarted(
    AgentPlanExecutionStarted event,
    Emitter<AgentConversationState> emit,
  ) async {
    final handoff = state.pending.planExecutionHandoff;
    if (handoff == null) {
      return;
    }
    await _run(emit, () {
      return _agentConversationRepository.submit(
        key: state.key,
        request: TurnRequest(
          message: event.message ?? handoff.markdown,
          context: _context,
        ),
      );
    });
    if (state.status != AgentConversationStatus.failure) {
      emit(
        state.copyWith(pending: state.pending.copyWith(clearHandoff: true)),
      );
    }
  }

  Future<void> _onDeniedActionApproved(
    AgentDeniedActionApproved event,
    Emitter<AgentConversationState> emit,
  ) {
    return _run(emit, () async {
      final port = _bundle?.deniedActionOverride;
      if (port == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      await port.approveDeniedAction(event.request);
      return null;
    });
  }

  Future<void> _onModelSelected(
    AgentModelSelected event,
    Emitter<AgentConversationState> emit,
  ) {
    final selection = AgentModelSelection(
      modelId: event.modelId,
      reasoningEffort: state.composer.modelConfig.selection.reasoningEffort,
      serviceTierId: state.composer.modelConfig.selection.serviceTierId,
    );
    return _persistSelection(emit, selection);
  }

  Future<void> _onReasoningEffortSelected(
    AgentReasoningEffortSelected event,
    Emitter<AgentConversationState> emit,
  ) {
    final selection = AgentModelSelection(
      modelId: state.composer.modelConfig.selection.modelId,
      reasoningEffort: event.effort,
      serviceTierId: state.composer.modelConfig.selection.serviceTierId,
    );
    return _persistSelection(emit, selection);
  }

  Future<void> _onServiceTierSelected(
    AgentServiceTierSelected event,
    Emitter<AgentConversationState> emit,
  ) {
    final selection = AgentModelSelection(
      modelId: state.composer.modelConfig.selection.modelId,
      reasoningEffort: state.composer.modelConfig.selection.reasoningEffort,
      serviceTierId: event.tierId,
    );
    return _persistSelection(emit, selection);
  }

  Future<void> _onFastToggled(
    AgentFastToggled event,
    Emitter<AgentConversationState> emit,
  ) async {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          modelConfig: state.composer.modelConfig.copyWith(
            fastEnabled: event.enabled,
          ),
        ),
      ),
    );
  }

  Future<void> _onModelConflictResolved(
    AgentModelConflictResolved event,
    Emitter<AgentConversationState> emit,
  ) async {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          modelConfig: state.composer.modelConfig.copyWith(clearConflict: true),
        ),
      ),
    );
    await _persistSelection(emit, state.composer.modelConfig.selection);
  }

  Future<void> _onModelConfigSaveRetried(
    AgentModelConfigSaveRetried event,
    Emitter<AgentConversationState> emit,
  ) {
    return _persistSelection(emit, state.composer.modelConfig.selection);
  }

  void _onModelConfigTransientCleared(
    AgentModelConfigTransientCleared event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          modelConfig: state.composer.modelConfig.copyWith(
            clearConflict: true,
            clearSaveError: true,
          ),
        ),
      ),
    );
  }

  Future<void> _onPermissionOptionSelected(
    AgentPermissionOptionSelected event,
    Emitter<AgentConversationState> emit,
  ) async {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          selectedPermissionOptionId: event.optionId,
        ),
      ),
    );
    await _run(emit, () {
      return _agentProviderRepository.applyPermissionSelection(
        state.key.providerId,
        AgentPermissionSelection(optionId: event.optionId),
      );
    });
  }

  Future<void> _onPermissionPersistenceRetried(
    AgentPermissionPersistenceRetried event,
    Emitter<AgentConversationState> emit,
  ) async {
    final optionId = state.composer.selectedPermissionOptionId;
    if (optionId == null) {
      return;
    }
    await _onPermissionOptionSelected(
      AgentPermissionOptionSelected(optionId),
      emit,
    );
  }

  void _onConversationModeSelected(
    AgentConversationModeSelected event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          selectedConversationMode: event.modeId,
        ),
        header: AgentHeaderState(
          title: state.header.title,
          threadOpenPhase: state.header.threadOpenPhase,
          systemNoticeCode: state.header.systemNoticeCode,
          statusCapsule: state.header.statusCapsule,
          waitingOnApproval: state.header.waitingOnApproval,
          waitingOnUserInput: state.header.waitingOnUserInput,
          showRunningIndicator: state.header.showRunningIndicator,
          runningActivity: state.header.runningActivity,
          segmentStartedAt: state.header.segmentStartedAt,
          turnStartedAt: state.header.turnStartedAt,
          tokenUsage: state.header.tokenUsage,
          isTurnRunning: state.header.isTurnRunning,
          isReadOnly: state.header.isReadOnly,
          canFork: state.header.canFork,
          canRename: state.header.canRename,
          canArchive: state.header.canArchive,
          isPlanMode: event.modeId == AgentConversationModeId.plan,
        ),
      ),
    );
  }

  Future<void> _onConversationModesRetried(
    AgentConversationModesRetried event,
    Emitter<AgentConversationState> emit,
  ) {
    return _loadModes(emit);
  }

  Future<void> _onSessionConfigOptionSelected(
    AgentSessionConfigOptionSelected event,
    Emitter<AgentConversationState> emit,
  ) async {
    emit(state.copyWith(clearFailure: true));
  }

  void _onPlanExecutionPermissionSelected(
    AgentPlanExecutionPermissionSelected event,
    Emitter<AgentConversationState> emit,
  ) {
    final handoff = state.pending.planExecutionHandoff;
    if (handoff == null) {
      return;
    }
    emit(
      state.copyWith(
        pending: state.pending.copyWith(
          planExecutionHandoff: handoff.copyWithExecutionPermission(
            AgentPlanExecutionPermissionChoice(
              label: event.optionId,
              origin: AgentPlanExecutionPermissionOrigin.userOverride,
              selection: AgentPermissionSelection(optionId: event.optionId),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onModelsRequested(
    AgentModelsRequested event,
    Emitter<AgentConversationState> emit,
  ) {
    return _loadModels(emit);
  }

  Future<void> _onSkillsCatalogRequested(
    AgentSkillsCatalogRequested event,
    Emitter<AgentConversationState> emit,
  ) async {
    final cwd = _context.projectPath;
    try {
      final catalog = await _agentProviderRepository.skills(
        state.key.providerId,
        cwds: cwd == null ? const <String>[] : <String>[cwd],
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(skillsCatalog: catalog),
        ),
      );
    } on Object catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(state.copyWith(failure: _mapError(error)));
    }
  }

  Future<void> _onSettingsRequested(
    AgentSettingsRequested event,
    Emitter<AgentConversationState> emit,
  ) async {
    await _loadModes(emit);
    await _loadModels(emit);
    try {
      final options = await _agentProviderRepository.permissionOptions(
        state.key.providerId,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(
            permissionOptions: options.options,
            showPermissionPolicy: true,
          ),
        ),
      );
    } on Object {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(showPermissionPolicy: false),
        ),
      );
    }
  }

  void _onToolCallToggled(
    AgentToolCallToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        expansion: state.expansion.copyWith(
          toolCallIds: _toggle(state.expansion.toolCallIds, event.id),
        ),
      ),
    );
  }

  void _onPlanMessageToggled(
    AgentPlanMessageToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        expansion: state.expansion.copyWith(
          planMessageIds: _toggle(state.expansion.planMessageIds, event.id),
        ),
      ),
    );
  }

  void _onActivePlanToggled(
    AgentActivePlanToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        expansion: state.expansion.copyWith(
          activePlanTurnIds: _toggle(
            state.expansion.activePlanTurnIds,
            event.id,
          ),
        ),
      ),
    );
  }

  void _onCommandGroupToggled(
    AgentCommandGroupToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        expansion: state.expansion.copyWith(
          commandGroupIds: _toggle(state.expansion.commandGroupIds, event.id),
        ),
      ),
    );
  }

  void _onFileEditItemToggled(
    AgentFileEditItemToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        expansion: state.expansion.copyWith(
          fileEditItemIds: _toggle(state.expansion.fileEditItemIds, event.id),
        ),
      ),
    );
  }

  void _onContextPanelToggled(
    AgentContextPanelToggled event,
    Emitter<AgentConversationState> emit,
  ) {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          contextPanelVisible:
              event.visible ?? !state.composer.contextPanelVisible,
        ),
      ),
    );
  }

  void _onHistoryWindowChanged(
    AgentHistoryWindowChanged event,
    Emitter<AgentConversationState> emit,
  ) {
    final snapshot = _agentConversationRepository.snapshotOf(state.key);
    emit(
      _reduceSnapshot(
        snapshot,
        generation: state.generation,
        visibleLimit: event.visibleLimit,
      ),
    );
  }

  @override
  Future<void> close() async {
    await _detachCurrent();
    await _configSubscription?.cancel();
    _configSubscription = null;
    try {
      await _agentConversationRepository.closeConversation(state.key);
    } on Object {
      // Already released with the conversation handle.
    }
    return super.close();
  }

  Future<void> _detachCurrent() async {
    await _snapshotSubscription?.cancel();
    _snapshotSubscription = null;
    await _handle?.release();
    _handle = null;
    _bundle = null;
  }

  Future<void> _run(
    Emitter<AgentConversationState> emit,
    Future<Object?> Function() action,
  ) async {
    try {
      await action();
      if (emit.isDone) {
        return;
      }
      emit(state.copyWith(clearFailure: true));
    } on Object catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentConversationStatus.failure,
          failure: _mapError(error),
        ),
      );
    }
  }

  Future<void> _runPort(
    Emitter<AgentConversationState> emit,
    Future<Object?> Function(AgentProviderBundle bundle, String threadId)
    action,
  ) {
    return _run(emit, () {
      final bundle = _bundle;
      final threadId = _threadId;
      if (bundle == null || threadId == null) {
        throw const AgentConversationRepositoryException(
          failure: AgentConversationFailure(
            AgentConversationFailureCode.operationUnsupported,
          ),
        );
      }
      return action(bundle, threadId);
    });
  }

  Future<void> _persistSelection(
    Emitter<AgentConversationState> emit,
    AgentModelSelection selection,
  ) async {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          modelConfig: state.composer.modelConfig.copyWith(
            selection: selection,
            clearSaveError: true,
          ),
        ),
      ),
    );
    _bundle?.runtime.updateModelSelection(selection);
    try {
      await _agentProviderRepository.persistDefaultModel(
        state.key.providerId,
        selection,
      );
    } on Object catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(
            modelConfig: state.composer.modelConfig.copyWith(
              saveErrorCode: _mapError(error).code.name,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _loadModes(Emitter<AgentConversationState> emit) async {
    emit(
      state.copyWith(
        composer: state.composer.copyWith(
          conversationModeStatus: AgentConversationModeLoadStatus.loading,
        ),
      ),
    );
    try {
      final catalog = await _agentProviderRepository.conversationModes(
        state.key.providerId,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(
            conversationModeStatus: AgentConversationModeLoadStatus.ready,
            conversationModeOptions: catalog.presets,
            clearModeStatusCode: true,
          ),
        ),
      );
    } on Object {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(
            conversationModeStatus: AgentConversationModeLoadStatus.error,
            conversationModeStatusCode: 'modes_unavailable',
          ),
        ),
      );
    }
  }

  Future<void> _loadModels(Emitter<AgentConversationState> emit) async {
    try {
      final catalog = await _agentProviderRepository.modelCatalog(
        state.key.providerId,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(
            modelConfig: state.composer.modelConfig.copyWith(catalog: catalog),
            showModelSelection: true,
          ),
        ),
      );
    } on Object {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          composer: state.composer.copyWith(showModelSelection: false),
        ),
      );
    }
  }

  AgentConversationState _reduceSnapshot(
    ConversationSnapshot? snapshot, {
    required int generation,
    int? visibleLimit,
  }) {
    final capabilities =
        _bundle?.runtime.capabilities ?? AgentProviderCapabilities.unsupported;
    final config = _bundle?.runtime.config;
    final phase = _phase(snapshot?.phase);
    final isTurnRunning = snapshot?.activeTurn != null;
    final isReadOnly = snapshot?.phase == ConversationPhase.failed;
    final limit = visibleLimit ?? state.history.visibleLimit;
    final groups = _groups(
      snapshot?.turns ?? const <ConversationTurnSnapshot>[],
    );
    final visible = groups.length <= limit
        ? groups
        : groups.sublist(groups.length - limit);
    final liveIds = <String>{
      for (final group in groups) ...group.entryIds,
      for (final group in groups) group.id,
    };
    final waitingOnApproval = snapshot?.waitingOnApproval ?? false;
    final waitingOnUserInput = snapshot?.waitingOnUserInput ?? false;
    return state.copyWith(
      key: snapshot?.key ?? state.key,
      status: snapshot?.failure != null
          ? AgentConversationStatus.failure
          : AgentConversationStatus.ready,
      generation: generation,
      failure: snapshot?.failure,
      clearFailure: snapshot?.failure == null,
      header: AgentHeaderState(
        title: snapshot?.threadName ?? '',
        threadOpenPhase: phase,
        statusCapsule: _capsule(
          isTurnRunning: isTurnRunning,
          waitingOnApproval: waitingOnApproval,
          waitingOnUserInput: waitingOnUserInput,
        ),
        waitingOnApproval: waitingOnApproval,
        waitingOnUserInput: waitingOnUserInput,
        showRunningIndicator: isTurnRunning,
        runningActivity: isTurnRunning ? AgentActivityCode.executing : null,
        turnStartedAt: _activeTurnStartedAt(snapshot),
        tokenUsage: _lastUsage(snapshot),
        isTurnRunning: isTurnRunning,
        isReadOnly: isReadOnly,
        canFork: capabilities.canForkThread,
        canRename: capabilities.canRenameThread,
        canArchive: capabilities.canArchiveThread,
        isPlanMode:
            state.composer.selectedConversationMode ==
            AgentConversationModeId.plan,
      ),
      composer: state.composer.copyWith(
        canSubmitMessage:
            capabilities.canPrompt && !isTurnRunning && !isReadOnly,
        isTurnRunning: isTurnRunning,
        threadOpenPhase: phase,
        contextUsage: _lastUsage(snapshot),
        isReadOnly: isReadOnly,
        canAttachImages: capabilities.supportsLocalImageInput,
        canMentionResources: capabilities.supportsResourceInput,
        canUseSkills: capabilities.supportsSkillInput,
        canCancelTurn: capabilities.canCancelTurn && isTurnRunning,
        canSteerTurn: capabilities.canSteerTurn && isTurnRunning,
        showModelSelection: capabilities.supportsModelSelection,
        sessionConfigOptions:
            snapshot?.sessionConfigOptions ??
            state.composer.sessionConfigOptions,
      ),
      pending: state.pending.copyWith(
        permissions: snapshot?.pendingPermissions ?? const [],
        questions: snapshot?.pendingQuestions ?? const [],
        planApprovals: snapshot?.pendingPlanApprovals ?? const [],
        isReadOnly: isReadOnly,
        autoReviewsByTurnId: snapshot?.autoReviewsByTurnId ?? const {},
        latestDeniedAutoReview: _latestDenied(
          snapshot?.autoReviewsByTurnId ?? const {},
        ),
      ),
      expansion: state.expansion.copyWith(
        toolCallIds: state.expansion.toolCallIds.intersection(liveIds),
        planMessageIds: state.expansion.planMessageIds.intersection(liveIds),
        activePlanTurnIds: state.expansion.activePlanTurnIds.intersection(
          liveIds,
        ),
        commandGroupIds: state.expansion.commandGroupIds.intersection(liveIds),
        fileEditItemIds: state.expansion.fileEditItemIds.intersection(liveIds),
      ),
      history: state.history.copyWith(
        visibleTurns: visible,
        threadOpenPhase: phase,
        providerId: config?.id ?? state.key.providerId,
        providerKind: config?.kind ?? AgentProviderKind.codexAppServer,
        providerName: config?.displayName ?? '',
        visibleLimit: limit,
        clearStandby: snapshot?.activeTurn != null,
      ),
    );
  }

  AgentThreadOpenPhase _phase(ConversationPhase? phase) {
    return switch (phase) {
      ConversationPhase.opening => AgentThreadOpenPhase.loadingHistory,
      ConversationPhase.failed => AgentThreadOpenPhase.openFailed,
      _ => AgentThreadOpenPhase.idle,
    };
  }

  AgentStatusCapsule _capsule({
    required bool isTurnRunning,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  }) {
    if (waitingOnApproval) {
      return AgentStatusCapsule.waitingOnApproval;
    }
    if (waitingOnUserInput) {
      return AgentStatusCapsule.waitingOnInput;
    }
    if (isTurnRunning) {
      return AgentStatusCapsule.running;
    }
    return AgentStatusCapsule.idle;
  }

  List<AgentConversationTurnGroup> _groups(
    List<ConversationTurnSnapshot> turns,
  ) {
    return <AgentConversationTurnGroup>[
      for (final turn in turns)
        AgentConversationTurnGroup(
          id: turn.id,
          entryIds: <String>[for (final entry in turn.entries) entry.id],
          status: turn.status,
        ),
    ];
  }

  Set<String> _toggle(Set<String> values, String id) {
    final next = Set<String>.of(values);
    if (!next.add(id)) {
      next.remove(id);
    }
    return next;
  }

  AgentPlanApprovalRequest? _planApproval(String requestId) {
    for (final request in state.pending.planApprovals) {
      if (request.id == requestId) {
        return request;
      }
    }
    return null;
  }

  AgentAutoApprovalReviewEvent? _latestDenied(
    Map<String, AgentAutoApprovalReviewEvent> reviews,
  ) {
    for (final review in reviews.values) {
      if (review.status == 'denied') {
        return review;
      }
    }
    return null;
  }

  DateTime? _activeTurnStartedAt(ConversationSnapshot? snapshot) {
    final activeId = snapshot?.activeTurn?.id;
    if (snapshot == null || activeId == null) {
      return null;
    }
    for (final turn in snapshot.turns) {
      if (turn.id == activeId) {
        return turn.startedAt;
      }
    }
    return null;
  }

  AgentTokenUsage? _lastUsage(ConversationSnapshot? snapshot) {
    if (snapshot == null || snapshot.turns.isEmpty) {
      return null;
    }
    return snapshot.turns.last.tokenUsage;
  }

  AgentConversationModeSelection? _modeSelection() {
    final mode = state.composer.selectedConversationMode;
    final modelId = state.composer.modelConfig.selection.modelId;
    if (mode == null || modelId == null || modelId.isEmpty) {
      return null;
    }
    return AgentConversationModeSelection(
      modeId: mode,
      effectiveModelId: modelId,
      effectiveReasoningEffort:
          state.composer.modelConfig.selection.reasoningEffort,
    );
  }

  String? get _threadId {
    final key = state.key;
    return key is ThreadConversationKey ? key.threadId : null;
  }

  AgentConversationFailure _mapError(Object error) {
    if (error is AgentConversationRepositoryException) {
      return error.failure;
    }
    return const AgentConversationFailure(
      AgentConversationFailureCode.providerOperationFailed,
    );
  }
}

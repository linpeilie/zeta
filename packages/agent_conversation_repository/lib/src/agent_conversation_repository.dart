import 'dart:async';

// Internal collaborators are public only across package library boundaries.
// ignore_for_file: public_member_api_docs, prefer_asserts_with_message

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_conversation_repository/src/conversation_models.dart';
import 'package:agent_conversation_repository/src/conversation_reducer.dart';
import 'package:agent_conversation_repository/src/event_pipeline.dart';
import 'package:agent_conversation_repository/src/turn_context.dart';
import 'package:agent_history_client/agent_history_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// Supplies provider-neutral replay inputs for one conversation.
typedef ConversationHistoryInputFactory =
    Future<Iterable<HistoryReplayInput>> Function({
      required ConversationKey key,
      required AgentProviderBundle bundle,
    });

/// A releasable reference to one open conversation.
final class ConversationHandle {
  ConversationHandle._(this.key, this.generation, this._release);

  final ConversationKey key;
  final int generation;
  Future<void> Function()? _release;

  bool get isReleased => _release == null;

  /// Releases this handle exactly once.
  Future<void> release() async {
    final callback = _release;
    if (callback == null) return;
    _release = null;
    await callback();
  }
}

/// Provider-neutral conversation aggregate and lifecycle owner.
final class AgentConversationRepository {
  AgentConversationRepository({
    required AgentTurnContextStore turnContextStore,
    required AppLogger logger,
    ConversationHistoryInputFactory? historyInputs,
    Clock clock = const Clock(),
    this.maxPendingEventKeys = 512,
    this.maxEventsPerTurn = 64,
  }) : assert(maxPendingEventKeys > 0),
       assert(maxEventsPerTurn > 0),
       _turnContextStore = turnContextStore,
       _logger = logger,
       _historyInputs = historyInputs ?? _noHistoryInputs,
       _clock = clock,
       _contextRecorder = TurnContextRecorder(
         store: turnContextStore,
         logger: logger,
         clock: clock,
       );

  final AgentTurnContextStore _turnContextStore;
  final AppLogger _logger;
  final ConversationHistoryInputFactory _historyInputs;
  final Clock _clock;
  final TurnContextRecorder _contextRecorder;
  final _BorrowedRuntimeRegistry _runtimes = _BorrowedRuntimeRegistry();
  final Map<ConversationKey, _Conversation> _conversations =
      <ConversationKey, _Conversation>{};
  final Map<ConversationKey, Future<_Conversation>> _opening =
      <ConversationKey, Future<_Conversation>>{};
  int _nextGeneration = 0;
  bool _closed = false;
  Future<void>? _closeFuture;

  final int maxPendingEventKeys;
  final int maxEventsPerTurn;

  /// Opens or leases a conversation using a bundle already resolved by Bloc.
  Future<ConversationHandle> openConversation({
    required AgentProviderBundle bundle,
    required ConversationKey key,
    required AgentContext context,
  }) async {
    _ensureRepositoryOpen();
    final providerId = bundle.runtime.config.id.trim();
    if (key.providerId.trim().isEmpty || providerId != key.providerId.trim()) {
      throw _exception(AgentConversationFailureCode.invalidIdentity);
    }
    final existing = _conversations[key];
    if (existing != null) {
      if (!identical(existing.bundle.runtime, bundle.runtime)) {
        throw _exception(AgentConversationFailureCode.invalidIdentity);
      }
      existing.context = context;
      return _lease(existing);
    }
    if (_opening.containsKey(key)) {
      throw _exception(AgentConversationFailureCode.conversationAlreadyOpening);
    }
    final opening = _open(bundle: bundle, key: key, context: context);
    _opening[key] = opening;
    try {
      final conversation = await opening;
      if (_closed) {
        await _disposeConversation(conversation);
        throw _exception(AgentConversationFailureCode.repositoryClosed);
      }
      _conversations[key] = conversation;
      conversation.publish();
      return _lease(conversation);
    } finally {
      unawaited(_opening.remove(key));
    }
  }

  /// Emits immutable domain snapshots for one currently open conversation.
  Stream<ConversationSnapshot> snapshots(ConversationKey key) =>
      _lookup(key).controller.stream;

  /// Returns the latest snapshot without waiting for the stream.
  ConversationSnapshot? snapshotOf(ConversationKey key) =>
      _conversations[key]?.snapshot;

  /// Returns payload-free diagnostics for acceptance tests and telemetry.
  ConversationDiagnostics diagnosticsOf(ConversationKey key) {
    final conversation = _lookup(key);
    final pipeline = conversation.pipeline?.diagnostics;
    return ConversationDiagnostics(
      receivedEvents: pipeline?.receivedEvents ?? 0,
      acceptedEvents: pipeline?.acceptedEvents ?? 0,
      coalescedEvents: pipeline?.coalescedEvents ?? 0,
      rejectedStaleEvents: pipeline?.rejectedStaleEvents ?? 0,
      rejectedOutOfOrderEvents: conversation.rejectedOutOfOrderEvents,
      backpressureFlushes: pipeline?.backpressureFlushes ?? 0,
      maxQueueDepth: pipeline?.maxQueueDepth ?? 0,
      runtimeLeaseCount: _runtimes.leaseCount,
      reducerInstanceCount: conversation.reducerInstanceCount,
    );
  }

  /// Starts a new provider turn from a caller-frozen request.
  Future<AgentTurn> submit({
    required ConversationKey key,
    required TurnRequest request,
  }) {
    final conversation = _lookup(key);
    return conversation.serial(() async {
      _ensureCurrent(conversation);
      final session = conversation.live.session;
      final context = request.context ?? conversation.context;
      late final AgentSession activeSession;
      if (session == null) {
        final created = await _providerCall(
          () => conversation.bundle.conversation.startSession(
            context: context,
            permissionSnapshot: request.permissionSnapshot,
          ),
        );
        _validateSession(created, conversation.key);
        conversation.live.session = created;
        activeSession = created;
      } else {
        activeSession = session;
      }
      final turn = await _providerCall(
        () => conversation.bundle.conversation.sendMessage(
          session: activeSession,
          context: context,
          message: request.message,
          inputs: request.inputs,
          clientUserMessageId: request.clientUserMessageId,
          configuration: request.configuration,
        ),
      );
      _validateTurn(turn, activeSession);
      final started = AgentTurnStartedEvent(
        turn,
        modelId: request.configuration.conversationMode?.effectiveModelId,
        reasoningEffort:
            request.configuration.conversationMode?.effectiveReasoningEffort,
        startedAt: _clock.now(),
      );
      conversation.live.beginLocalTurn(
        turn,
        message: request.message,
        messageId: request.clientUserMessageId,
      );
      _contextRecorder.recordStarted(
        providerId: key.providerId,
        event: started,
      );
      conversation.publish();
      return turn;
    });
  }

  /// Cancels the current active turn.
  Future<void> cancel(ConversationKey key) {
    final conversation = _lookup(key);
    return conversation.serial(() async {
      _ensureCurrent(conversation);
      final turn = conversation.live.activeTurn;
      if (turn == null) {
        throw _exception(AgentConversationFailureCode.noActiveTurn);
      }
      await _providerCall(
        () => conversation.bundle.conversation.cancelTurn(turn),
      );
    });
  }

  /// Appends a steering request to the current active turn.
  Future<void> steer({
    required ConversationKey key,
    required SteerRequest request,
  }) {
    final conversation = _lookup(key);
    return conversation.serial(() async {
      _ensureCurrent(conversation);
      final port = conversation.bundle.turnSteering;
      if (port == null) {
        throw _exception(AgentConversationFailureCode.operationUnsupported);
      }
      final turn = conversation.live.activeTurn;
      final session = conversation.live.session;
      if (turn == null || session == null) {
        throw _exception(AgentConversationFailureCode.noActiveTurn);
      }
      await _providerCall(
        () => port.steerTurn(
          session: session,
          expectedTurnId: turn.id,
          context: request.context ?? conversation.context,
          message: request.message,
          inputs: request.inputs,
          clientUserMessageId: request.clientUserMessageId,
        ),
      );
    });
  }

  /// Responds only to a pending permission request.
  Future<void> respondToPermission(
    ConversationKey key,
    AgentPermissionDecision decision,
  ) => _respond<AgentPermissionResponsePort, AgentPermissionRequest>(
    key: key,
    requestId: decision.requestId,
    pending: (c) => c.live.pendingPermissions,
    port: (c) => c.bundle.permissionResponses,
    invoke: (port) => port.respondToPermission(decision),
    resolve: (c) => c.live.resolvePermission(decision.requestId),
  );

  /// Responds only to a pending provider question.
  Future<void> respondToQuestion(
    ConversationKey key,
    AgentQuestionResponse response,
  ) => _respond<AgentQuestionResponsePort, AgentQuestionRequest>(
    key: key,
    requestId: response.requestId,
    pending: (c) => c.live.pendingQuestions,
    port: (c) => c.bundle.questions,
    invoke: (port) => port.respondToQuestion(response),
    resolve: (c) => c.live.resolveQuestion(response.requestId),
  );

  /// Responds only to a pending plan-approval request.
  Future<void> respondToPlanApproval(
    ConversationKey key,
    AgentPlanApprovalDecision decision,
  ) => _respond<AgentPlanApprovalPort, AgentPlanApprovalRequest>(
    key: key,
    requestId: decision.requestId,
    pending: (c) => c.live.pendingPlanApprovals,
    port: (c) => c.bundle.planApproval,
    invoke: (port) => port.respondToPlanApproval(decision),
    resolve: (c) => c.live.resolvePlanApproval(decision.requestId),
  );

  Future<void> _respond<P extends Object, V>({
    required ConversationKey key,
    required String requestId,
    required Map<String, V> Function(_Conversation conversation) pending,
    required P? Function(_Conversation conversation) port,
    required Future<void> Function(P port) invoke,
    required bool Function(_Conversation conversation) resolve,
  }) {
    final conversation = _lookup(key);
    return conversation.serial(() async {
      _ensureCurrent(conversation);
      if (!pending(conversation).containsKey(requestId)) {
        throw _exception(AgentConversationFailureCode.pendingRequestNotFound);
      }
      final target = port(conversation);
      if (target == null) {
        throw _exception(AgentConversationFailureCode.operationUnsupported);
      }
      await _providerCall(() => invoke(target));
      resolve(conversation);
      conversation.publish();
    });
  }

  /// Force-closes one conversation and all of its resources.
  Future<void> closeConversation(ConversationKey key) async {
    final conversation = _conversations.remove(key);
    if (conversation != null) await _disposeConversation(conversation);
  }

  /// Closes every conversation and rejects all future operations.
  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    _closed = true;
    return _closeFuture = _closeAll();
  }

  Future<_Conversation> _open({
    required AgentProviderBundle bundle,
    required ConversationKey key,
    required AgentContext context,
  }) async {
    _BorrowedRuntimeLease? runtimeLease;
    _Conversation? conversation;
    try {
      await _providerCall(bundle.runtime.initialize);
      runtimeLease = _runtimes.acquire(bundle);
      conversation = _Conversation(
        key: key,
        bundle: bundle,
        context: context,
        generation: ++_nextGeneration,
        runtimeLease: runtimeLease,
      );
      if (key is ThreadConversationKey) {
        await _loadHistory(conversation, key);
        final session = await _providerCall(
          () => bundle.conversation.resumeSession(
            key.threadId,
            context: context,
          ),
        );
        _validateSession(session, key);
        conversation.live.session = session;
      }
      final opened = conversation;
      conversation.pipeline = ConversationEventPipeline(
        source: bundle.runtime.events,
        isCurrent: () =>
            !_closed &&
            identical(_conversations[key] ?? opened, opened) &&
            opened.runtimeLease.isCurrent,
        onEvent: (event) => _processEvent(opened, event),
        onError: (error, stackTrace) =>
            _handleSourceError(opened, error, stackTrace),
        onDone: () => _handleSourceDone(opened),
        maxPendingKeys: maxPendingEventKeys,
        maxEventsPerTurn: maxEventsPerTurn,
      );
      return conversation;
    } catch (error, stackTrace) {
      await conversation?.pipeline?.close();
      await runtimeLease?.release();
      if (error is AgentConversationRepositoryException) rethrow;
      _logger.w(
        'Conversation open failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AgentConversationRepositoryException(
        failure: const AgentConversationFailure(
          AgentConversationFailureCode.providerOperationFailed,
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _loadHistory(
    _Conversation conversation,
    ThreadConversationKey key,
  ) async {
    try {
      final catalog = conversation.bundle.threadCatalog;
      if (catalog != null) {
        final values = await Future.wait<Object?>(<Future<Object?>>[
          catalog.readThreadHistory(
            threadId: key.threadId,
            projectPath: conversation.context.projectPath,
          ),
          _turnContextStore.load(
            providerId: key.providerId,
            threadId: key.threadId,
          ),
        ]);
        final history = overlayTurnContext(
          values[0]! as AgentThreadHistorySnapshot,
          values[1] as AgentThreadTurnContext?,
        );
        conversation.history.loadHistory(history.turns);
      }
      final inputs = await _historyInputs(
        key: key,
        bundle: conversation.bundle,
      );
      final replay = await mergeHistoryInputs(inputs);
      conversation.replay.loadHistory(replay.turns);
      if (replay.warnings.isNotEmpty) {
        _logger.w(
          'Conversation history skipped ${replay.warnings.length} records',
        );
      }
    } catch (error, stackTrace) {
      _logger.w(
        'Conversation history read failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AgentConversationRepositoryException(
        failure: const AgentConversationFailure(
          AgentConversationFailureCode.historyReadFailed,
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  void _processEvent(_Conversation conversation, AgentEvent event) {
    if (!_belongsTo(conversation, event)) {
      conversation.rejectedOutOfOrderEvents += 1;
      return;
    }
    conversation.live.reduce(event);
    if (event is AgentTurnStartedEvent) {
      _contextRecorder.recordStarted(
        providerId: conversation.key.providerId,
        event: event,
      );
    } else if (event is AgentTurnCompletedEvent) {
      _contextRecorder.recordCompleted(
        providerId: conversation.key.providerId,
        event: event,
      );
    }
    conversation.publish();
  }

  bool _belongsTo(_Conversation conversation, AgentEvent event) {
    if (event is AgentSessionStartedEvent &&
        event.session.providerId != conversation.key.providerId) {
      return false;
    }
    final expectedSession = conversation.live.session?.id;
    final expectedThread = switch (conversation.key) {
      ThreadConversationKey(:final threadId) => threadId,
      DraftConversationKey() => expectedSession,
    };
    final eventSession = _sessionIdOf(event);
    if (eventSession != null) {
      if (expectedThread == null && event is! AgentSessionStartedEvent) {
        return false;
      }
      if (expectedThread != null && eventSession != expectedThread) {
        return false;
      }
    }
    final eventThread = _threadIdOf(event);
    if (eventThread != null) {
      if (expectedThread == null || eventThread != expectedThread) {
        return false;
      }
    }
    final turnId = _turnIdOf(event);
    if (turnId == null || event is AgentTurnStartedEvent) return true;
    return conversation.live.activeTurn?.id == turnId ||
        conversation.live.hasTurn(turnId) ||
        conversation.history.hasTurn(turnId) ||
        conversation.replay.hasTurn(turnId);
  }

  void _handleSourceError(
    _Conversation conversation,
    Object error,
    StackTrace stackTrace,
  ) {
    if (!identical(_conversations[conversation.key], conversation)) return;
    conversation.live.failure = const AgentConversationFailure(
      AgentConversationFailureCode.providerOperationFailed,
    );
    conversation.publish();
    _logger.w(
      'Conversation event source failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _handleSourceDone(_Conversation conversation) {
    if (!identical(_conversations[conversation.key], conversation)) return;
    conversation.live.failure = const AgentConversationFailure(
      AgentConversationFailureCode.providerOperationFailed,
    );
    conversation.publish();
    _logger.w('Conversation event source closed');
  }

  ConversationHandle _lease(_Conversation conversation) {
    conversation.handleCount += 1;
    return ConversationHandle._(
      conversation.key,
      conversation.generation,
      () => _releaseHandle(conversation),
    );
  }

  Future<void> _releaseHandle(_Conversation conversation) async {
    if (!identical(_conversations[conversation.key], conversation)) return;
    if (conversation.handleCount > 0) conversation.handleCount -= 1;
    if (conversation.handleCount == 0) {
      _conversations.remove(conversation.key);
      await _disposeConversation(conversation);
    }
  }

  Future<void> _disposeConversation(_Conversation conversation) async {
    if (conversation.disposed) return;
    conversation.disposed = true;
    await conversation.operations;
    await conversation.pipeline?.close();
    final threadId = conversation.live.session?.id;
    final unsubscribe = conversation.bundle.threadSubscription;
    if (threadId != null && unsubscribe != null) {
      try {
        await unsubscribe.unsubscribeThread(threadId);
      } on Object catch (error, stackTrace) {
        _logger.w(
          'Conversation unsubscribe failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
    await conversation.runtimeLease.release();
    await _contextRecorder.flush();
    conversation.publish(phase: ConversationPhase.closed);
    await conversation.controller.close();
  }

  Future<void> _closeAll() async {
    for (final opening in _opening.values.toList(growable: false)) {
      try {
        await opening;
      } on Object {
        // The original open caller receives the typed failure.
      }
    }
    final conversations = _conversations.values.toList(growable: false);
    _conversations.clear();
    await Future.wait(conversations.map(_disposeConversation));
    await _contextRecorder.flush();
    await _runtimes.close();
  }

  _Conversation _lookup(ConversationKey key) {
    _ensureRepositoryOpen();
    final conversation = _conversations[key];
    if (conversation == null || conversation.disposed) {
      throw _exception(AgentConversationFailureCode.conversationNotOpen);
    }
    return conversation;
  }

  void _ensureRepositoryOpen() {
    if (_closed) {
      throw _exception(AgentConversationFailureCode.repositoryClosed);
    }
  }

  void _ensureCurrent(_Conversation conversation) {
    _ensureRepositoryOpen();
    if (conversation.disposed ||
        !identical(_conversations[conversation.key], conversation) ||
        !conversation.runtimeLease.isCurrent) {
      throw _exception(AgentConversationFailureCode.conversationNotOpen);
    }
  }

  Future<T> _providerCall<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } catch (error, stackTrace) {
      if (error is AgentConversationRepositoryException) rethrow;
      _logger.w(
        'Conversation provider operation failed',
        error: error,
        stackTrace: stackTrace,
      );
      throw AgentConversationRepositoryException(
        failure: const AgentConversationFailure(
          AgentConversationFailureCode.providerOperationFailed,
        ),
        cause: error,
        stackTrace: stackTrace,
      );
    }
  }

  AgentConversationRepositoryException _exception(
    AgentConversationFailureCode code,
  ) => AgentConversationRepositoryException(
    failure: AgentConversationFailure(code),
  );

  void _validateSession(AgentSession session, ConversationKey key) {
    final expectedThread = key is ThreadConversationKey ? key.threadId : null;
    if (session.providerId != key.providerId ||
        (expectedThread != null && session.id != expectedThread)) {
      throw _exception(AgentConversationFailureCode.invalidIdentity);
    }
  }

  void _validateTurn(AgentTurn turn, AgentSession session) {
    if (turn.sessionId != session.id) {
      throw _exception(AgentConversationFailureCode.invalidIdentity);
    }
  }
}

Future<Iterable<HistoryReplayInput>> _noHistoryInputs({
  required ConversationKey key,
  required AgentProviderBundle bundle,
}) async => const <HistoryReplayInput>[];

final class _Conversation {
  _Conversation({
    required this.key,
    required this.bundle,
    required this.context,
    required this.generation,
    required this.runtimeLease,
  });

  final ConversationKey key;
  final AgentProviderBundle bundle;
  AgentContext context;
  final int generation;
  final _BorrowedRuntimeLease runtimeLease;
  final ConversationReducer live = ConversationReducer(
    ConversationReductionScope.live,
  );
  final ConversationReducer history = ConversationReducer(
    ConversationReductionScope.history,
  );
  final ConversationReducer replay = ConversationReducer(
    ConversationReductionScope.replay,
  );
  final StreamController<ConversationSnapshot> controller =
      StreamController<ConversationSnapshot>.broadcast(sync: true);
  ConversationEventPipeline? pipeline;
  ConversationSnapshot? snapshot;
  Future<void> operations = Future<void>.value();
  int revision = 0;
  int handleCount = 0;
  int rejectedOutOfOrderEvents = 0;
  bool disposed = false;

  int get reducerInstanceCount =>
      <ConversationReducer>{live, history, replay}.length;

  Future<T> serial<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    operations = operations.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void publish({ConversationPhase phase = ConversationPhase.ready}) {
    revision += 1;
    snapshot = ConversationSnapshot(
      key: key,
      phase: phase,
      generation: generation,
      revision: revision,
      session: live.session,
      activeTurn: live.activeTurn,
      turns: _mergeTurns(history.turns, replay.turns, live.turns),
      providerStatus: live.providerStatus,
      threadStatus: live.threadStatus,
      threadName: live.threadName,
      threadPreview: live.threadPreview,
      isArchived: live.isArchived,
      waitingOnApproval: live.waitingOnApproval,
      waitingOnUserInput: live.waitingOnUserInput,
      pendingPermissions: live.pendingPermissions.values.toList(
        growable: false,
      ),
      pendingQuestions: live.pendingQuestions.values.toList(growable: false),
      pendingPlanApprovals: live.pendingPlanApprovals.values.toList(
        growable: false,
      ),
      autoReviewsByTurnId: live.autoReviewsByTurnId,
      sessionConfigOptions: live.sessionConfigOptions,
      conversationMode: live.conversationMode,
      modelList: live.modelList,
      failure: live.failure,
    );
    if (!controller.isClosed) controller.add(snapshot!);
  }
}

List<ConversationTurnSnapshot> _mergeTurns(
  List<ConversationTurnSnapshot> history,
  List<ConversationTurnSnapshot> replay,
  List<ConversationTurnSnapshot> live,
) {
  final order = <String>[];
  final values = <String, ConversationTurnSnapshot>{};
  for (final incoming in <ConversationTurnSnapshot>[
    ...history,
    ...replay,
    ...live,
  ]) {
    final previous = values[incoming.id];
    if (previous == null) {
      order.add(incoming.id);
      values[incoming.id] = incoming;
      continue;
    }
    final entries = <String, ConversationTimelineEntry>{
      for (final entry in previous.entries) entry.id: entry,
      for (final entry in incoming.entries) entry.id: entry,
    };
    values[incoming.id] = ConversationTurnSnapshot(
      id: incoming.id,
      entries: entries.values.toList(growable: false),
      status: incoming.status == AgentHistoryTurnStatus.unknown
          ? previous.status
          : incoming.status,
      startedAt: incoming.startedAt ?? previous.startedAt,
      completedAt: incoming.completedAt ?? previous.completedAt,
      duration: incoming.duration ?? previous.duration,
      tokenUsage: incoming.tokenUsage ?? previous.tokenUsage,
      contextWindowUsedTokens:
          incoming.contextWindowUsedTokens ?? previous.contextWindowUsedTokens,
      modelContextWindow:
          incoming.modelContextWindow ?? previous.modelContextWindow,
    );
  }
  return <ConversationTurnSnapshot>[for (final id in order) values[id]!];
}

final class _BorrowedRuntimeRegistry {
  final Map<AgentRuntimePort, _BorrowedRuntimeEntry> _entries =
      Map<AgentRuntimePort, _BorrowedRuntimeEntry>.identity();
  final Map<String, int> _generationByProvider = <String, int>{};
  bool _closed = false;

  int get leaseCount => _entries.values.fold<int>(
    0,
    (total, entry) => total + entry.leaseCount,
  );

  _BorrowedRuntimeLease acquire(AgentProviderBundle bundle) {
    if (_closed) throw StateError('Borrowed runtime registry is closed');
    final runtime = bundle.runtime;
    final entry = _entries.putIfAbsent(runtime, () {
      final providerId = runtime.config.id;
      final generation = (_generationByProvider[providerId] ?? 0) + 1;
      _generationByProvider[providerId] = generation;
      return _BorrowedRuntimeEntry(runtime, generation);
    })..leaseCount += 1;
    return _BorrowedRuntimeLease._(this, entry);
  }

  bool isCurrent(_BorrowedRuntimeEntry entry) =>
      !_closed && identical(_entries[entry.runtime], entry);

  void release(_BorrowedRuntimeEntry entry) {
    if (entry.leaseCount > 0) entry.leaseCount -= 1;
    if (entry.leaseCount == 0) _entries.remove(entry.runtime);
  }

  Future<void> close() async {
    _closed = true;
    _entries.clear();
  }
}

final class _BorrowedRuntimeEntry {
  _BorrowedRuntimeEntry(this.runtime, this.generation);
  final AgentRuntimePort runtime;
  final int generation;
  int leaseCount = 0;
}

final class _BorrowedRuntimeLease {
  _BorrowedRuntimeLease._(this._registry, this._entry);
  _BorrowedRuntimeRegistry? _registry;
  final _BorrowedRuntimeEntry _entry;

  bool get isCurrent => _registry?.isCurrent(_entry) ?? false;

  Future<void> release() async {
    final registry = _registry;
    if (registry == null) return;
    _registry = null;
    registry.release(_entry);
  }
}

String? _sessionIdOf(AgentEvent event) => switch (event) {
  AgentSessionStartedEvent() => event.session.id,
  AgentTurnStartedEvent() => event.turn.sessionId,
  AgentTurnCompletedEvent() => event.sessionId,
  AgentTokenUsageEvent() => event.sessionId,
  AgentContextWindowUsageEvent() => event.sessionId,
  AgentMessageDeltaEvent() => event.sessionId,
  AgentReasoningDeltaEvent() => event.sessionId,
  AgentMessageUpdatedEvent() => event.sessionId,
  AgentPlanUpdatedEvent() => event.sessionId,
  AgentSessionConfigUpdatedEvent() => event.sessionId,
  AgentConversationModeUpdatedEvent() => event.sessionId,
  AgentPlanApprovalRequestedEvent() => event.request.sessionId,
  AgentPlanApprovalResolvedEvent() => event.sessionId,
  AgentTurnFileChangesEvent() => event.sessionId,
  AgentToolCallEvent() => event.toolCall.sessionId,
  AgentPermissionRequestedEvent() => event.request.sessionId,
  AgentQuestionRequestedEvent() => event.request.sessionId,
  AgentSystemItemEvent() => event.sessionId,
  AgentErrorEvent() => event.sessionId,
  _ => null,
};

String? _threadIdOf(AgentEvent event) => switch (event) {
  AgentThreadStatusChangedEvent() => event.threadId,
  AgentThreadNameUpdatedEvent() => event.threadId,
  AgentThreadPreviewUpdatedEvent() => event.threadId,
  AgentThreadArchivedEvent() => event.threadId,
  AgentThreadUnarchivedEvent() => event.threadId,
  AgentThreadDeletedEvent() => event.threadId,
  AgentThreadClosedEvent() => event.threadId,
  AgentThreadCompactedEvent() => event.threadId,
  AgentThreadSettingsUpdatedEvent() => event.threadId,
  AgentAutoApprovalReviewEvent() => event.threadId,
  AgentPermissionResolvedEvent() => event.threadId,
  AgentQuestionResolvedEvent() => event.threadId,
  AgentModelReroutedEvent() => event.threadId,
  _ => null,
};

String? _turnIdOf(AgentEvent event) => switch (event) {
  AgentTurnStartedEvent() => event.turn.id,
  AgentTurnCompletedEvent() => event.turnId,
  AgentTokenUsageEvent() => event.turnId,
  AgentContextWindowUsageEvent() => event.turnId,
  AgentMessageDeltaEvent() => event.turnId,
  AgentReasoningDeltaEvent() => event.turnId,
  AgentMessageUpdatedEvent() => event.turnId,
  AgentPlanUpdatedEvent() => event.turnId,
  AgentPlanApprovalRequestedEvent() => event.request.turnId,
  AgentTurnFileChangesEvent() => event.turnId,
  AgentToolCallEvent() => event.toolCall.turnId,
  AgentPermissionRequestedEvent() => event.request.turnId,
  AgentQuestionRequestedEvent() => event.request.turnId,
  AgentModelReroutedEvent() => event.turnId,
  AgentSystemItemEvent() => event.turnId,
  AgentErrorEvent() => event.turnId,
  _ => null,
};

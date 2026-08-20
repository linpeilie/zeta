import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';

// The barrel exposes these value objects; class-level docs describe their fields.
// ignore_for_file: lines_longer_than_80_chars, prefer_asserts_with_message, public_member_api_docs, sort_constructors_first

/// A stable, provider-scoped conversation identity.
sealed class ConversationKey extends Equatable {
  const ConversationKey({required this.providerId});

  /// Provider configuration id owning this conversation.
  final String providerId;

  /// Creates an identity for a conversation that has no provider thread yet.
  const factory ConversationKey.draft({
    required String providerId,
    required String entryId,
  }) = DraftConversationKey;

  /// Creates an identity for an existing provider thread.
  const factory ConversationKey.thread({
    required String providerId,
    required String threadId,
  }) = ThreadConversationKey;
}

/// Conversation identity used before the first provider session is created.
final class DraftConversationKey extends ConversationKey {
  const DraftConversationKey({
    required super.providerId,
    required this.entryId,
  });

  /// Stable workspace entry id.
  final String entryId;

  @override
  List<Object?> get props => <Object?>[providerId, entryId];

  @override
  String toString() => 'draft($providerId)';
}

/// Conversation identity backed by an existing provider thread.
final class ThreadConversationKey extends ConversationKey {
  const ThreadConversationKey({
    required super.providerId,
    required this.threadId,
  });

  /// Provider thread id.
  final String threadId;

  @override
  List<Object?> get props => <Object?>[providerId, threadId];

  @override
  String toString() => 'thread($providerId)';
}

/// Immutable input frozen by the Bloc for one new turn.
final class TurnRequest {
  const TurnRequest({
    this.message,
    this.inputs,
    this.clientUserMessageId,
    this.configuration = const AgentTurnConfiguration(),
    this.permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
    this.context,
  });

  /// Optional plain-text user message.
  final String? message;

  /// Optional structured user inputs.
  final List<AgentUserInput>? inputs;

  /// Caller-generated user message id used for idempotency.
  final String? clientUserMessageId;

  /// Turn-only model and mode configuration.
  final AgentTurnConfiguration configuration;

  /// Permission state captured at submit time.
  final AgentPermissionRequestSnapshot permissionSnapshot;

  /// Optional context override; otherwise the open-conversation context is used.
  final AgentContext? context;
}

/// Immutable input for steering an active turn.
final class SteerRequest {
  const SteerRequest({
    this.message,
    this.inputs,
    this.clientUserMessageId,
    this.context,
  });

  final String? message;
  final List<AgentUserInput>? inputs;
  final String? clientUserMessageId;
  final AgentContext? context;
}

/// Conversation lifecycle exposed to business consumers.
enum ConversationPhase { opening, ready, failed, closed }

/// Domain-only kinds for timeline entries.
enum ConversationEntryKind {
  message,
  reasoning,
  tool,
  history,
  fileChanges,
  permission,
  question,
  planApproval,
  plan,
  system,
}

/// Content-free system signals retained in the domain timeline.
enum ConversationSystemSignal {
  threadCompacted,
  modelRerouted,
  deprecationNotice,
  providerError,
}

/// An immutable domain entry in a conversation turn.
sealed class ConversationTimelineEntry extends Equatable {
  const ConversationTimelineEntry({
    required this.id,
    required this.turnId,
    required this.kind,
  });

  final String id;
  final String? turnId;
  final ConversationEntryKind kind;
}

/// A normalized message entry.
final class ConversationMessageEntry extends ConversationTimelineEntry {
  const ConversationMessageEntry({
    required super.id,
    required super.turnId,
    required this.role,
    required this.text,
    this.sourceMessageId,
    this.messageKind = AgentMessageKind.regular,
    this.phase,
    this.status,
    this.duration,
  }) : super(kind: ConversationEntryKind.message);

  final AgentMessageRole role;
  final String text;
  final String? sourceMessageId;
  final AgentMessageKind messageKind;
  final AgentMessagePhase? phase;
  final AgentMessageStatus? status;
  final Duration? duration;

  ConversationMessageEntry copyWith({
    String? text,
    String? sourceMessageId,
    AgentMessageKind? messageKind,
    AgentMessageRole? role,
    AgentMessagePhase? phase,
    AgentMessageStatus? status,
    Duration? duration,
  }) {
    return ConversationMessageEntry(
      id: id,
      turnId: turnId,
      role: role ?? this.role,
      text: text ?? this.text,
      sourceMessageId: sourceMessageId ?? this.sourceMessageId,
      messageKind: messageKind ?? this.messageKind,
      phase: phase ?? this.phase,
      status: status ?? this.status,
      duration: duration ?? this.duration,
    );
  }

  @override
  List<Object?> get props => <Object?>[
    id,
    turnId,
    role,
    text,
    sourceMessageId,
    messageKind,
    phase,
    status,
    duration,
  ];
}

/// A normalized reasoning stream entry.
final class ConversationReasoningEntry extends ConversationTimelineEntry {
  const ConversationReasoningEntry({
    required super.id,
    required super.turnId,
    required this.text,
    required this.reasoningKind,
    this.sourceItemId,
  }) : super(kind: ConversationEntryKind.reasoning);

  final String text;
  final AgentReasoningDeltaKind reasoningKind;
  final String? sourceItemId;

  @override
  List<Object?> get props => <Object?>[
    id,
    turnId,
    text,
    reasoningKind,
    sourceItemId,
  ];
}

/// A provider-neutral tool entry.
final class ConversationToolEntry extends ConversationTimelineEntry {
  const ConversationToolEntry({
    required super.id,
    required super.turnId,
    required this.toolCall,
  }) : super(kind: ConversationEntryKind.tool);

  final AgentToolCall toolCall;

  @override
  List<Object?> get props => <Object?>[id, turnId, toolCall];
}

/// A typed provider history entry retained without UI projection.
final class ConversationHistoryEntry extends ConversationTimelineEntry {
  const ConversationHistoryEntry({
    required super.id,
    required super.turnId,
    required this.entry,
  }) : super(kind: ConversationEntryKind.history);

  final AgentHistoryEntry entry;

  @override
  List<Object?> get props => <Object?>[id, turnId, entry];
}

/// A full, provider-normalized file-change snapshot for one turn.
final class ConversationFileChangesEntry extends ConversationTimelineEntry {
  const ConversationFileChangesEntry({
    required super.id,
    required super.turnId,
    required this.snapshot,
  }) : super(kind: ConversationEntryKind.fileChanges);

  final AgentFileChangeSnapshot snapshot;

  @override
  List<Object?> get props => <Object?>[id, turnId, snapshot];
}

/// One of the three deliberately isolated pending security semantics.
final class ConversationPendingEntry extends ConversationTimelineEntry {
  const ConversationPendingEntry({
    required super.id,
    required super.turnId,
    required super.kind,
    required this.request,
    this.resolved = false,
  }) : assert(
         kind == ConversationEntryKind.permission ||
             kind == ConversationEntryKind.question ||
             kind == ConversationEntryKind.planApproval,
       );

  final Object request;
  final bool resolved;

  ConversationPendingEntry markResolved() => ConversationPendingEntry(
    id: id,
    turnId: turnId,
    kind: kind,
    request: request,
    resolved: true,
  );

  @override
  List<Object?> get props => <Object?>[id, turnId, kind, request, resolved];
}

/// A plan or system event that has no presentation-specific rendering data.
final class ConversationValueEntry extends ConversationTimelineEntry {
  const ConversationValueEntry({
    required super.id,
    required super.turnId,
    required super.kind,
    required this.value,
  }) : assert(
         kind == ConversationEntryKind.plan ||
             kind == ConversationEntryKind.system,
       );

  final Object value;

  @override
  List<Object?> get props => <Object?>[id, turnId, kind, value];
}

/// Immutable aggregate for one provider turn.
final class ConversationTurnSnapshot extends Equatable {
  ConversationTurnSnapshot({
    required this.id,
    required List<ConversationTimelineEntry> entries,
    this.status = AgentHistoryTurnStatus.unknown,
    this.startedAt,
    this.completedAt,
    this.duration,
    this.tokenUsage,
    this.contextWindowUsedTokens,
    this.modelContextWindow,
  }) : entries = List<ConversationTimelineEntry>.unmodifiable(entries);

  final String id;
  final List<ConversationTimelineEntry> entries;
  final AgentHistoryTurnStatus status;
  final DateTime? startedAt;
  final DateTime? completedAt;
  final Duration? duration;
  final AgentTokenUsage? tokenUsage;
  final int? contextWindowUsedTokens;
  final int? modelContextWindow;

  @override
  List<Object?> get props => <Object?>[
    id,
    entries,
    status,
    startedAt,
    completedAt,
    duration,
    tokenUsage,
    contextWindowUsedTokens,
    modelContextWindow,
  ];
}

/// The complete immutable domain view of an open conversation.
final class ConversationSnapshot extends Equatable {
  ConversationSnapshot({
    required this.key,
    required this.phase,
    required this.generation,
    required this.revision,
    required List<ConversationTurnSnapshot> turns,
    required List<AgentPermissionRequest> pendingPermissions,
    required List<AgentQuestionRequest> pendingQuestions,
    required List<AgentPlanApprovalRequest> pendingPlanApprovals,
    required Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId,
    this.session,
    this.activeTurn,
    this.providerStatus = const AgentProviderStatus.idle(),
    this.threadStatus = AgentThreadRuntimeStatus.unknown,
    this.threadName,
    this.threadPreview,
    this.isArchived = false,
    this.waitingOnApproval = false,
    this.waitingOnUserInput = false,
    List<AgentSessionConfigOption> sessionConfigOptions =
        const <AgentSessionConfigOption>[],
    this.conversationMode,
    this.modelList,
    this.failure,
  }) : turns = List<ConversationTurnSnapshot>.unmodifiable(turns),
       pendingPermissions = List<AgentPermissionRequest>.unmodifiable(
         pendingPermissions,
       ),
       pendingQuestions = List<AgentQuestionRequest>.unmodifiable(
         pendingQuestions,
       ),
       pendingPlanApprovals = List<AgentPlanApprovalRequest>.unmodifiable(
         pendingPlanApprovals,
       ),
       autoReviewsByTurnId =
           Map<String, AgentAutoApprovalReviewEvent>.unmodifiable(
             autoReviewsByTurnId,
           ),
       sessionConfigOptions = List<AgentSessionConfigOption>.unmodifiable(
         sessionConfigOptions,
       );

  final ConversationKey key;
  final ConversationPhase phase;
  final int generation;
  final int revision;
  final AgentSession? session;
  final AgentTurn? activeTurn;
  final List<ConversationTurnSnapshot> turns;
  final AgentProviderStatus providerStatus;
  final AgentThreadRuntimeStatus threadStatus;
  final String? threadName;
  final String? threadPreview;
  final bool isArchived;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final List<AgentPermissionRequest> pendingPermissions;
  final List<AgentQuestionRequest> pendingQuestions;
  final List<AgentPlanApprovalRequest> pendingPlanApprovals;
  final Map<String, AgentAutoApprovalReviewEvent> autoReviewsByTurnId;
  final List<AgentSessionConfigOption> sessionConfigOptions;
  final AgentConversationModeId? conversationMode;
  final AgentModelList? modelList;
  final AgentConversationFailure? failure;

  @override
  List<Object?> get props => <Object?>[
    key,
    phase,
    generation,
    revision,
    session,
    activeTurn,
    turns,
    providerStatus,
    threadStatus,
    threadName,
    threadPreview,
    isArchived,
    waitingOnApproval,
    waitingOnUserInput,
    pendingPermissions,
    pendingQuestions,
    pendingPlanApprovals,
    autoReviewsByTurnId,
    sessionConfigOptions,
    conversationMode,
    modelList,
    failure,
  ];
}

/// Stable failure categories suitable for Bloc decisions and localization.
enum AgentConversationFailureCode {
  repositoryClosed,
  invalidIdentity,
  conversationNotOpen,
  conversationAlreadyOpening,
  operationUnsupported,
  noActiveTurn,
  pendingRequestNotFound,
  historyReadFailed,
  providerOperationFailed,
}

/// Content-free domain failure.
final class AgentConversationFailure extends Equatable {
  const AgentConversationFailure(this.code);

  final AgentConversationFailureCode code;

  @override
  List<Object?> get props => <Object?>[code];

  @override
  String toString() => 'AgentConversationFailure(${code.name})';
}

/// Exception retaining the original diagnostic chain without rendering it.
final class AgentConversationRepositoryException implements Exception {
  const AgentConversationRepositoryException({
    required this.failure,
    this.cause,
    this.stackTrace,
  });

  final AgentConversationFailure failure;
  final Object? cause;
  final StackTrace? stackTrace;

  @override
  String toString() => 'AgentConversationRepositoryException($failure)';
}

/// Payload-free throughput and lifecycle counters.
final class ConversationDiagnostics extends Equatable {
  const ConversationDiagnostics({
    required this.receivedEvents,
    required this.acceptedEvents,
    required this.coalescedEvents,
    required this.rejectedStaleEvents,
    required this.rejectedOutOfOrderEvents,
    required this.backpressureFlushes,
    required this.maxQueueDepth,
    required this.runtimeLeaseCount,
    required this.reducerInstanceCount,
  });

  final int receivedEvents;
  final int acceptedEvents;
  final int coalescedEvents;
  final int rejectedStaleEvents;
  final int rejectedOutOfOrderEvents;
  final int backpressureFlushes;
  final int maxQueueDepth;
  final int runtimeLeaseCount;
  final int reducerInstanceCount;

  @override
  List<Object?> get props => <Object?>[
    receivedEvents,
    acceptedEvents,
    coalescedEvents,
    rejectedStaleEvents,
    rejectedOutOfOrderEvents,
    backpressureFlushes,
    maxQueueDepth,
    runtimeLeaseCount,
    reducerInstanceCount,
  ];
}

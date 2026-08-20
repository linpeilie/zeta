import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';
import 'package:zeta/agent_chat/bloc/agent_conversation_state.dart';

sealed class AgentConversationEvent extends Equatable {
  const AgentConversationEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class AgentConversationOpened extends AgentConversationEvent {
  const AgentConversationOpened({
    required this.key,
    required this.context,
  });

  final ConversationKey key;
  final AgentContext context;

  @override
  List<Object?> get props => <Object?>[key, context];
}

final class AgentConversationClosed extends AgentConversationEvent {
  const AgentConversationClosed();
}

final class AgentProviderSwitched extends AgentConversationEvent {
  const AgentProviderSwitched({
    required this.key,
    required this.context,
  });

  final ConversationKey key;
  final AgentContext context;

  @override
  List<Object?> get props => <Object?>[key, context];
}

final class AgentContextUpdated extends AgentConversationEvent {
  const AgentContextUpdated(this.context);

  final AgentContext context;

  @override
  List<Object?> get props => <Object?>[context];
}

final class AgentConversationSnapshotUpdated extends AgentConversationEvent {
  const AgentConversationSnapshotUpdated({
    required this.snapshot,
    required this.generation,
  });

  final ConversationSnapshot snapshot;
  final int generation;

  @override
  List<Object?> get props => <Object?>[snapshot, generation];
}

final class AgentMessageSubmitted extends AgentConversationEvent {
  const AgentMessageSubmitted({
    this.message,
    this.inputs,
    this.clientUserMessageId,
  });

  final String? message;
  final List<AgentUserInput>? inputs;
  final String? clientUserMessageId;

  @override
  List<Object?> get props => <Object?>[message, inputs, clientUserMessageId];
}

final class AgentTurnCancelled extends AgentConversationEvent {
  const AgentTurnCancelled();
}

final class AgentTurnSteered extends AgentConversationEvent {
  const AgentTurnSteered({this.message, this.inputs});

  final String? message;
  final List<AgentUserInput>? inputs;

  @override
  List<Object?> get props => <Object?>[message, inputs];
}

final class AgentLastUserMessageEdited extends AgentConversationEvent {
  const AgentLastUserMessageEdited(this.message);

  final String message;

  @override
  List<Object?> get props => <Object?>[message];
}

final class AgentThreadForked extends AgentConversationEvent {
  const AgentThreadForked();
}

final class AgentThreadRenamed extends AgentConversationEvent {
  const AgentThreadRenamed(this.name);

  final String name;

  @override
  List<Object?> get props => <Object?>[name];
}

final class AgentThreadArchived extends AgentConversationEvent {
  const AgentThreadArchived();
}

final class AgentThreadCompacted extends AgentConversationEvent {
  const AgentThreadCompacted();
}

final class AgentPermissionResponded extends AgentConversationEvent {
  const AgentPermissionResponded(this.decision);

  final AgentPermissionDecision decision;

  @override
  List<Object?> get props => <Object?>[decision];
}

final class AgentQuestionResponded extends AgentConversationEvent {
  const AgentQuestionResponded(this.response);

  final AgentQuestionResponse response;

  @override
  List<Object?> get props => <Object?>[response];
}

final class AgentPlanApprovalResponded extends AgentConversationEvent {
  const AgentPlanApprovalResponded(this.decision);

  final AgentPlanApprovalDecision decision;

  @override
  List<Object?> get props => <Object?>[decision];
}

final class AgentPlanExecutionStarted extends AgentConversationEvent {
  const AgentPlanExecutionStarted({this.message});

  final String? message;

  @override
  List<Object?> get props => <Object?>[message];
}

final class AgentPlanExecutionRevised extends AgentConversationEvent {
  const AgentPlanExecutionRevised();
}

final class AgentPlanExecutionDismissed extends AgentConversationEvent {
  const AgentPlanExecutionDismissed();
}

final class AgentDeniedActionApproved extends AgentConversationEvent {
  const AgentDeniedActionApproved(this.request);

  final AgentDeniedActionOverrideRequest request;

  @override
  List<Object?> get props => <Object?>[request];
}

final class AgentModelSelected extends AgentConversationEvent {
  const AgentModelSelected(this.modelId);

  final String modelId;

  @override
  List<Object?> get props => <Object?>[modelId];
}

final class AgentReasoningEffortSelected extends AgentConversationEvent {
  const AgentReasoningEffortSelected(this.effort);

  final String effort;

  @override
  List<Object?> get props => <Object?>[effort];
}

final class AgentServiceTierSelected extends AgentConversationEvent {
  const AgentServiceTierSelected(this.tierId);

  final String tierId;

  @override
  List<Object?> get props => <Object?>[tierId];
}

final class AgentFastToggled extends AgentConversationEvent {
  const AgentFastToggled({required this.enabled});

  final bool enabled;

  @override
  List<Object?> get props => <Object?>[enabled];
}

final class AgentModelConflictResolved extends AgentConversationEvent {
  const AgentModelConflictResolved();
}

final class AgentModelConfigSaveRetried extends AgentConversationEvent {
  const AgentModelConfigSaveRetried();
}

final class AgentModelConfigTransientCleared extends AgentConversationEvent {
  const AgentModelConfigTransientCleared();
}

final class AgentPermissionOptionSelected extends AgentConversationEvent {
  const AgentPermissionOptionSelected(this.optionId);

  final String optionId;

  @override
  List<Object?> get props => <Object?>[optionId];
}

final class AgentPermissionPersistenceRetried extends AgentConversationEvent {
  const AgentPermissionPersistenceRetried();
}

final class AgentConversationModeSelected extends AgentConversationEvent {
  const AgentConversationModeSelected(this.modeId);

  final AgentConversationModeId modeId;

  @override
  List<Object?> get props => <Object?>[modeId];
}

final class AgentConversationModesRetried extends AgentConversationEvent {
  const AgentConversationModesRetried();
}

final class AgentSessionConfigOptionSelected extends AgentConversationEvent {
  const AgentSessionConfigOptionSelected(this.optionId);

  final String optionId;

  @override
  List<Object?> get props => <Object?>[optionId];
}

final class AgentPlanExecutionPermissionSelected
    extends AgentConversationEvent {
  const AgentPlanExecutionPermissionSelected(this.optionId);

  final String optionId;

  @override
  List<Object?> get props => <Object?>[optionId];
}

final class AgentModelsRequested extends AgentConversationEvent {
  const AgentModelsRequested();
}

final class AgentSkillsCatalogRequested extends AgentConversationEvent {
  const AgentSkillsCatalogRequested();
}

final class AgentSettingsRequested extends AgentConversationEvent {
  const AgentSettingsRequested();
}

final class AgentToolCallToggled extends AgentConversationEvent {
  const AgentToolCallToggled(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class AgentPlanMessageToggled extends AgentConversationEvent {
  const AgentPlanMessageToggled(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class AgentActivePlanToggled extends AgentConversationEvent {
  const AgentActivePlanToggled(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class AgentCommandGroupToggled extends AgentConversationEvent {
  const AgentCommandGroupToggled(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class AgentFileEditItemToggled extends AgentConversationEvent {
  const AgentFileEditItemToggled(this.id);

  final String id;

  @override
  List<Object?> get props => <Object?>[id];
}

final class AgentContextPanelToggled extends AgentConversationEvent {
  const AgentContextPanelToggled({this.visible});

  final bool? visible;

  @override
  List<Object?> get props => <Object?>[visible];
}

final class AgentHistoryWindowChanged extends AgentConversationEvent {
  const AgentHistoryWindowChanged(this.visibleLimit);

  final int visibleLimit;

  @override
  List<Object?> get props => <Object?>[visibleLimit];
}

final class AgentThreadUnarchived extends AgentConversationEvent {
  const AgentThreadUnarchived();
}

final class AgentThreadDeleted extends AgentConversationEvent {
  const AgentThreadDeleted();
}

final class AgentThreadRemovedFromList extends AgentConversationEvent {
  const AgentThreadRemovedFromList();
}

final class AgentThreadUnsubscribed extends AgentConversationEvent {
  const AgentThreadUnsubscribed();
}

final class AgentImagesAttachRequested extends AgentConversationEvent {
  const AgentImagesAttachRequested();
}

final class AgentFilesMentionRequested extends AgentConversationEvent {
  const AgentFilesMentionRequested();
}

final class AgentClipboardPasteRequested extends AgentConversationEvent {
  const AgentClipboardPasteRequested();
}

final class AgentQuotaRequested extends AgentConversationEvent {
  const AgentQuotaRequested();
}

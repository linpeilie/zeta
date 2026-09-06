import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'agent_conversation_command_scope.dart';

/// 命令仅驻留内存；固定 scope 不携带用户输入或资源身份。
sealed class AgentConversationCommandPayload {
  const AgentConversationCommandPayload();
  String get fixedScope;
  bool get isSynchronous => false;
}

enum AgentConversationExpansionTarget {
  toolCall,
  planMessage,
  activePlan,
  commandGroup,
  fileEditItem,
}

final class AgentConversationCommandEnvelope {
  const AgentConversationCommandEnvelope({
    required this.id,
    required this.scope,
    required this.ownerLifetimeToken,
    required this.payload,
  });
  final OperationId id;
  final AgentConversationCommandScope scope;
  final Object ownerLifetimeToken;
  final AgentConversationCommandPayload payload;
}

final class AgentSendMessageCommand extends AgentConversationCommandPayload {
  AgentSendMessageCommand({
    required this.text,
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    this.permissionSnapshotOverride,
  }) : localImagePaths = List.unmodifiable(localImagePaths),
       mentions = List.unmodifiable(mentions),
       skills = List.unmodifiable(skills);
  final String text;
  final List<String> localImagePaths;
  final List<({String name, String path})> mentions;
  final List<AgentSkillRef> skills;
  final AgentPermissionRequestSnapshot? permissionSnapshotOverride;
  @override
  String get fixedScope => AgentConversationOperationScopes.send;
}

final class AgentCancelActiveTurnCommand
    extends AgentConversationCommandPayload {
  const AgentCancelActiveTurnCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.cancel;
}

final class AgentEditLastUserMessageCommand
    extends AgentConversationCommandPayload {
  const AgentEditLastUserMessageCommand({required this.newText});
  final String newText;
  @override
  String get fixedScope => AgentConversationOperationScopes.editLastMessage;
}

final class AgentRetryOpenThreadCommand
    extends AgentConversationCommandPayload {
  const AgentRetryOpenThreadCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.retryOpen;
}

final class AgentRespondPermissionCommand
    extends AgentConversationCommandPayload {
  AgentRespondPermissionCommand({
    required AgentPermissionRequest request,
    required this.approved,
    this.cancelTurn = false,
    this.commandDecision,
    List<String> execpolicyAmendment = const [],
  }) : request = _freezePermission(request),
       execpolicyAmendment = List.unmodifiable(execpolicyAmendment);
  final AgentPermissionRequest request;
  final bool approved;
  final bool cancelTurn;
  final AgentCommandApprovalDecisionKind? commandDecision;
  final List<String> execpolicyAmendment;
  @override
  String get fixedScope => AgentConversationOperationScopes.permission;
}

final class AgentRespondQuestionCommand
    extends AgentConversationCommandPayload {
  AgentRespondQuestionCommand({
    required AgentQuestionRequest request,
    Map<String, List<String>> answers = const {},
  }) : request = _freezeQuestion(request),
       answers = Map.unmodifiable(
         answers.map(
           (key, values) => MapEntry(key, List<String>.unmodifiable(values)),
         ),
       );
  final AgentQuestionRequest request;
  final Map<String, List<String>> answers;
  @override
  String get fixedScope => AgentConversationOperationScopes.question;
}

final class AgentRespondPlanApprovalCommand
    extends AgentConversationCommandPayload {
  AgentRespondPlanApprovalCommand({
    required AgentPlanApprovalRequest request,
    required this.kind,
    this.reason,
  }) : request = _freezePlan(request);
  final AgentPlanApprovalRequest request;
  final AgentPlanApprovalDecisionKind kind;
  final String? reason;
  @override
  String get fixedScope => AgentConversationOperationScopes.planApproval;
}

final class AgentStartPlanExecutionCommand
    extends AgentConversationCommandPayload {
  const AgentStartPlanExecutionCommand({required this.request});
  final AgentPlanExecutionRequest request;
  @override
  String get fixedScope => AgentConversationOperationScopes.planExecution;
}

final class AgentRevisePlanExecutionCommand
    extends AgentConversationCommandPayload {
  const AgentRevisePlanExecutionCommand({
    required this.request,
    this.revisionMessage,
  });
  final AgentPlanExecutionRequest request;
  final String? revisionMessage;
  @override
  String get fixedScope => AgentConversationOperationScopes.planExecution;
}

final class AgentDismissPlanExecutionCommand
    extends AgentConversationCommandPayload {
  const AgentDismissPlanExecutionCommand({required this.request});
  final AgentPlanExecutionRequest request;
  @override
  String get fixedScope => AgentConversationOperationScopes.planExecution;
  @override
  bool get isSynchronous => true;
}

final class AgentSelectPlanExecutionPermissionCommand
    extends AgentConversationCommandPayload {
  const AgentSelectPlanExecutionPermissionCommand({
    required this.request,
    required this.option,
  });
  final AgentPlanExecutionRequest request;
  final AgentPermissionOption option;
  @override
  String get fixedScope =>
      AgentConversationOperationScopes.planExecutionPermission;
  @override
  bool get isSynchronous => true;
}

final class AgentApproveGuardianDeniedActionCommand
    extends AgentConversationCommandPayload {
  const AgentApproveGuardianDeniedActionCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.guardianOverride;
}

final class AgentForkCurrentThreadCommand
    extends AgentConversationCommandPayload {
  const AgentForkCurrentThreadCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.threadMutation;
}

final class AgentRenameCurrentThreadCommand
    extends AgentConversationCommandPayload {
  const AgentRenameCurrentThreadCommand({required this.name});
  final String name;
  @override
  String get fixedScope => AgentConversationOperationScopes.threadMutation;
}

final class AgentArchiveCurrentThreadCommand
    extends AgentConversationCommandPayload {
  const AgentArchiveCurrentThreadCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.threadMutation;
}

final class AgentCompactCurrentThreadCommand
    extends AgentConversationCommandPayload {
  const AgentCompactCurrentThreadCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.threadMutation;
}

final class AgentToggleExpansionCommand
    extends AgentConversationCommandPayload {
  const AgentToggleExpansionCommand({required this.target, required this.id});
  final AgentConversationExpansionTarget target;
  final String id;
  @override
  String get fixedScope => AgentConversationOperationScopes.expansion;
  @override
  bool get isSynchronous => true;
}

final class AgentLoadModelsCommand extends AgentConversationCommandPayload {
  const AgentLoadModelsCommand({this.forceRefresh = false});
  final bool forceRefresh;
  @override
  String get fixedScope => AgentConversationOperationScopes.catalog;
}

final class AgentEnsureSkillsCatalogCommand
    extends AgentConversationCommandPayload {
  const AgentEnsureSkillsCatalogCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.catalog;
}

final class AgentRetryConversationModesCommand
    extends AgentConversationCommandPayload {
  const AgentRetryConversationModesCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.catalog;
}

final class AgentSelectConversationModeCommand
    extends AgentConversationCommandPayload {
  const AgentSelectConversationModeCommand({required this.modeId});
  final AgentConversationModeId modeId;
  @override
  String get fixedScope => AgentConversationOperationScopes.modeSelection;
  @override
  bool get isSynchronous => true;
}

final class AgentSelectModelCommand extends AgentConversationCommandPayload {
  const AgentSelectModelCommand({required this.modelId});
  final String modelId;
  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
}

final class AgentSelectReasoningEffortCommand
    extends AgentConversationCommandPayload {
  const AgentSelectReasoningEffortCommand({required this.effort});
  final String? effort;
  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
}

final class AgentSelectFastEnabledCommand
    extends AgentConversationCommandPayload {
  const AgentSelectFastEnabledCommand({required this.enabled});
  final bool enabled;
  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
}

final class AgentResolveModelCompatibilityCommand
    extends AgentConversationCommandPayload {
  const AgentResolveModelCompatibilityCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
}

final class AgentRetryModelSaveCommand extends AgentConversationCommandPayload {
  const AgentRetryModelSaveCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
}

final class AgentClearModelTransientStateCommand
    extends AgentConversationCommandPayload {
  const AgentClearModelTransientStateCommand();

  @override
  String get fixedScope => AgentConversationOperationScopes.modelSelection;
  @override
  bool get isSynchronous => true;
}

final class AgentSelectPermissionOptionCommand
    extends AgentConversationCommandPayload {
  const AgentSelectPermissionOptionCommand({required this.option});
  final AgentPermissionOption option;
  @override
  String get fixedScope =>
      AgentConversationOperationScopes.permissionPreference;
}

final class AgentRetryPermissionPersistenceCommand
    extends AgentConversationCommandPayload {
  const AgentRetryPermissionPersistenceCommand();

  @override
  String get fixedScope =>
      AgentConversationOperationScopes.permissionPreference;
}

final class AgentSelectSessionConfigOptionCommand
    extends AgentConversationCommandPayload {
  AgentSelectSessionConfigOptionCommand({
    required this.configId,
    required Object value,
  }) : value = _configScalar(value);
  final String configId;
  final Object value;
  @override
  String get fixedScope => AgentConversationOperationScopes.sessionConfig;
}

final class AgentSwitchProviderCommand extends AgentConversationCommandPayload {
  const AgentSwitchProviderCommand({required this.providerId});
  final String providerId;
  @override
  String get fixedScope => AgentConversationOperationScopes.providerSelection;
}

Object _configScalar(Object value) {
  if (value is String || value is bool || value is num) return value;
  throw ArgumentError('Session config requires a scalar value');
}

abstract final class AgentConversationOperationScopes {
  static const String send = 'conversation.send';
  static const String cancel = 'conversation.cancel';
  static const String editLastMessage = 'conversation.editLastMessage';
  static const String retryOpen = 'conversation.retryOpen';
  static const String permission = 'conversation.permission';
  static const String question = 'conversation.question';
  static const String planApproval = 'conversation.planApproval';
  static const String planExecution = 'conversation.planExecution';
  static const String guardianOverride = 'conversation.guardianOverride';
  static const String threadMutation = 'conversation.threadMutation';
  static const String catalog = 'conversation.catalog';

  static const String planExecutionPermission =
      'conversation.planExecutionPermission';
  static const String expansion = 'conversation.expansion';
  static const String modeSelection = 'conversation.modeSelection';
  static const String modelSelection = 'conversation.modelSelection';
  static const String permissionPreference =
      'conversation.permissionPreference';
  static const String sessionConfig = 'conversation.sessionConfig';
  static const String providerSelection = 'conversation.providerSelection';

  /// 全部作用域，供守卫与测试遍历。
  static const List<String> all = <String>[
    send,
    cancel,
    editLastMessage,
    retryOpen,
    permission,
    question,
    planApproval,
    planExecution,
    guardianOverride,
    threadMutation,
    catalog,
    planExecutionPermission,
    expansion,
    modeSelection,
    modelSelection,
    permissionPreference,
    sessionConfig,
    providerSelection,
  ];
}

AgentPermissionRequest _freezePermission(AgentPermissionRequest r) =>
    AgentPermissionRequest(
      id: r.id,
      title: r.title,
      kind: r.kind,
      description: r.description,
      command: r.command,
      cwd: r.cwd,
      sessionId: r.sessionId,
      turnId: r.turnId,
      raw: r.raw,
      fileChanges: Map.unmodifiable(
        r.fileChanges.map((key, value) => MapEntry(key, _freezeValue(value))),
      ),
      commandActions: List.unmodifiable(r.commandActions),
      proposedExecpolicyAmendment: List.unmodifiable(
        r.proposedExecpolicyAmendment,
      ),
    );

Object? _freezeValue(Object? value) => switch (value) {
  Map<Object?, Object?>() => Map.unmodifiable(
    value.map((key, item) => MapEntry(key, _freezeValue(item))),
  ),
  List<Object?>() => List.unmodifiable(value.map(_freezeValue)),
  Set<Object?>() => Set.unmodifiable(value.map(_freezeValue)),
  _ => value,
};

AgentQuestionRequest _freezeQuestion(AgentQuestionRequest r) =>
    AgentQuestionRequest(
      id: r.id,
      title: r.title,
      description: r.description,
      sessionId: r.sessionId,
      turnId: r.turnId,
      raw: r.raw,
      questions: List.unmodifiable(
        r.questions.map(
          (q) => AgentUserInputQaPair(
            question: q.question,
            questionId: q.questionId,
            header: q.header,
            isOther: q.isOther,
            answers: List.unmodifiable(q.answers),
            optionItems: List.unmodifiable(q.optionItems),
            allowMultiple: q.allowMultiple,
            isSecret: q.isSecret,
            options: List.unmodifiable(q.options),
          ),
        ),
      ),
    );

AgentPlanApprovalRequest _freezePlan(AgentPlanApprovalRequest r) =>
    AgentPlanApprovalRequest(
      id: r.id,
      title: r.title,
      markdown: r.markdown,
      overview: r.overview,
      isProject: r.isProject,
      sessionId: r.sessionId,
      turnId: r.turnId,
      continuation: r.continuation,
      raw: r.raw,
      todos: List.unmodifiable(r.todos),
      phases: List.unmodifiable(
        r.phases.map(
          (phase) => AgentPlanApprovalPhase(
            name: phase.name,
            todos: List.unmodifiable(phase.todos),
          ),
        ),
      ),
    );

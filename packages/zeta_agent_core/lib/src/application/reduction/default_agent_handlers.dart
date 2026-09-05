import 'package:zeta_agent_core/src/application/reduction/agent_event_handler_registry.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/auto_approval_review_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/context_usage_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/conversation_mode_updated_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/deprecation_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/error_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/message_delta_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/message_updated_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/model_list_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/model_rerouted_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/no_op_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/permission_requested_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/permission_resolved_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/plan_approval_requested_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/plan_approval_resolved_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/plan_updated_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/question_requested_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/question_resolved_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/reasoning_delta_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/session_config_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/session_started_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/status_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/system_item_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_closed_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_compacted_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_name_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_preview_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_settings_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/thread_status_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/token_usage_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/tool_call_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/turn_completed_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/turn_file_changes_handler.dart';
import 'package:zeta_agent_core/src/application/reduction/handlers/turn_started_handler.dart';
import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 共享默认 handler 注册清单。返回已 seal 的 builder，供 Provider 覆盖非审批事件。
AgentEventHandlerRegistryBuilder defaultAgentHandlerRegistryBuilder() {
  final builder = AgentEventHandlerRegistryBuilder();
  builder
    ..register<AgentStatusEvent>(const StatusHandler())
    ..register<AgentSessionStartedEvent>(const SessionStartedHandler())
    ..register<AgentThreadStatusChangedEvent>(const ThreadStatusHandler())
    ..register<AgentThreadNameUpdatedEvent>(const ThreadNameHandler())
    ..register<AgentThreadPreviewUpdatedEvent>(const ThreadPreviewHandler())
    ..register<AgentThreadArchivedEvent>(
      const NoOpHandler<AgentThreadArchivedEvent>(),
    )
    ..register<AgentThreadUnarchivedEvent>(
      const NoOpHandler<AgentThreadUnarchivedEvent>(),
    )
    ..register<AgentThreadDeletedEvent>(
      const NoOpHandler<AgentThreadDeletedEvent>(),
    )
    ..register<AgentThreadClosedEvent>(const ThreadClosedHandler())
    ..register<AgentThreadCompactedEvent>(const ThreadCompactedHandler())
    ..register<AgentThreadSettingsUpdatedEvent>(const ThreadSettingsHandler())
    ..register<AgentAutoApprovalReviewEvent>(const AutoApprovalReviewHandler())
    ..register<AgentTurnStartedEvent>(const TurnStartedHandler())
    ..register<AgentTurnCompletedEvent>(const TurnCompletedHandler())
    ..register<AgentTokenUsageEvent>(const TokenUsageHandler())
    ..register<AgentContextWindowUsageEvent>(const ContextUsageHandler())
    ..register<AgentMessageDeltaEvent>(const MessageDeltaHandler())
    ..register<AgentReasoningDeltaEvent>(const ReasoningDeltaHandler())
    ..register<AgentMessageUpdatedEvent>(const MessageUpdatedHandler())
    ..register<AgentPlanUpdatedEvent>(const PlanUpdatedHandler())
    ..register<AgentSessionConfigUpdatedEvent>(const SessionConfigHandler())
    ..register<AgentConversationModeUpdatedEvent>(
      const ConversationModeUpdatedHandler(),
    )
    ..register<AgentPlanApprovalRequestedEvent>(
      const PlanApprovalRequestedHandler(),
    )
    ..register<AgentPlanApprovalResolvedEvent>(
      const PlanApprovalResolvedHandler(),
    )
    ..register<AgentTurnFileChangesEvent>(const TurnFileChangesHandler())
    ..register<AgentToolCallEvent>(const ToolCallHandler())
    ..register<AgentPermissionRequestedEvent>(
      const PermissionRequestedHandler(),
    )
    ..register<AgentPermissionResolvedEvent>(const PermissionResolvedHandler())
    ..register<AgentQuestionRequestedEvent>(const QuestionRequestedHandler())
    ..register<AgentQuestionResolvedEvent>(const QuestionResolvedHandler())
    ..register<AgentModelReroutedEvent>(const ModelReroutedHandler())
    ..register<AgentDeprecationNoticeEvent>(const DeprecationHandler())
    ..register<AgentSystemItemEvent>(const SystemItemHandler())
    ..register<AgentErrorEvent>(const ErrorHandler())
    ..register<AgentModelListEvent>(const ModelListHandler());
  builder.seal();
  return builder;
}

/// 共享默认注册表。无可变状态，live/history/replay 共用一份。
final AgentEventHandlerRegistry defaultAgentEventHandlerRegistry =
    defaultAgentHandlerRegistryBuilder().build();

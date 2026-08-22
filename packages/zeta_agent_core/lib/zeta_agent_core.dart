/// Zeta 的中立 Agent 内核。
///
/// 这里是**机制层**：领域模型与端口、Binding/runtime 契约、事件管线、纯 reducer、
/// TimelineStore 与 Effect 描述。所有 Provider 差异都必须在各自的 adapter/reducer
/// 里消化完再进来（G1/G2）。
///
/// 明确不做的事：
///
/// - 不认识任何具体 Provider，不按 providerId / kind / 显示名分支；
/// - 不含 Provider 协议类型（JSON-RPC / ACP / stream-json 只存在于 data 层）；
/// - 不读文件、不起进程（无 `dart:io`）；不依赖 Riverpod、Flutter widgets 或根 app；
/// - 不产出本地化文案：需要用户可见文案时只接受注入的 `AgentUiTextCatalog`。
library;

export 'src/domain/agent_attention_models.dart';
export 'src/domain/agent_conversation_mode_models.dart';
export 'src/domain/agent_event_models.dart';
export 'src/domain/agent_file_change_models.dart';
export 'src/domain/agent_message_models.dart';
export 'src/domain/agent_model_catalog_models.dart';
export 'src/domain/agent_model_codec.dart';
export 'src/domain/agent_model_selection_models.dart';
export 'src/domain/agent_models.dart';
export 'src/domain/agent_permission_models.dart';
export 'src/domain/agent_permission_policy_models.dart';
export 'src/domain/agent_plan_approval_models.dart';
export 'src/domain/agent_plan_execution_models.dart';
export 'src/domain/agent_provider_bundle.dart';
export 'src/domain/agent_provider_capabilities.dart';
export 'src/domain/agent_provider_error_presentation.dart';
export 'src/domain/agent_provider_models.dart';
export 'src/domain/agent_question_models.dart';
export 'src/domain/agent_runtime_models.dart';
export 'src/domain/agent_session_config_models.dart';
export 'src/domain/agent_session_models.dart';
export 'src/domain/agent_skill_models.dart';
export 'src/domain/agent_thread_models.dart';
export 'src/domain/agent_tool_models.dart';
export 'src/domain/agent_turn_activity_models.dart';
export 'src/domain/agent_turn_context_models.dart';
export 'src/domain/agent_turn_history_models.dart';
export 'src/domain/agent_turn_terminal_signal.dart';
export 'src/domain/agent_ui_text_catalog.dart';
export 'src/domain/agent_usage_models.dart';
export 'src/domain/agent_usage_window_labels.dart';
export 'src/domain/agent_user_input_models.dart';
export 'src/domain/fallback_agent_ui_text_catalog.dart';
export 'src/application/agent_conversation_binding.dart';
export 'src/application/agent_conversation_binding_manager.dart';
export 'src/application/agent_conversation_effect.dart';
export 'src/application/agent_conversation_effect_runner.dart';
export 'src/application/agent_conversation_event_processor.dart';
export 'src/application/agent_conversation_mutation.dart';
export 'src/application/agent_conversation_permission_selection_controller.dart';
export 'src/application/agent_conversation_permission_state.dart';
export 'src/application/agent_conversation_reducer.dart';
export 'src/application/agent_conversation_thread_snapshot.dart';
export 'src/application/agent_conversation_timeline_store.dart';
export 'src/application/agent_elapsed_ticker.dart';
export 'src/application/agent_event_coalescing_policy.dart';
export 'src/application/agent_event_pipeline.dart';
export 'src/application/agent_permission_catalog_controller.dart';
export 'src/application/agent_permission_request_resolver.dart';
export 'src/application/agent_provider_config_store.dart';
export 'src/application/agent_provider_event_listener_gate.dart';
export 'src/application/agent_provider_global_runtime.dart';
export 'src/application/agent_provider_runtime_identity.dart';
export 'src/application/agent_provider_runtime_registry.dart';
export 'src/application/agent_turn_context_recorder.dart';
export 'src/application/agent_turn_context_store.dart';
export 'src/application/agent_ui_update_port.dart';
export 'src/application/agent_ui_update_request.dart';
export 'src/application/bounded_event_dispatcher.dart';
export 'src/application/coalescing_event_buffer.dart';

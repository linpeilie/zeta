/// Zeta 的 Agent Provider 适配层。
///
/// 这里是**厂商差异的唯一容身处**：Codex app-server（JSON-RPC）、Grok（ACP）、
/// Claude Code（stream-json）的协议 transport、data adapter、Provider-local
/// reducer/tracker、CLI 定位与插件入口。
///
/// 边界规则：
///
/// - 协议原文（JSON-RPC / ACP / stream-json 的 wire 字段、CLI 参数、会话文件
///   格式）**只能出现在这里**，对外一律输出 `zeta_agent_core` 的中立模型；
/// - 不依赖根 app、presentation、Riverpod 或 `zeta_ui`；
/// - 允许 `dart:io`：拉起本机 CLI、读取 Provider 私有配置与历史是这一层的职责；
/// - 新增 Provider 的正常改动面就是这个包 + 一行插件注册（目标架构 §9.3）。
library;

export 'src/agent_ignored_message_logger.dart';
export 'src/agent_metric_labels.dart';
export 'src/agent_provider_permission_migration.dart';
export 'src/agent_provider_plugin_contribution.dart';
export 'src/agent_provider_static_capabilities.dart';
export 'src/claude_code_cli_locator.dart';
export 'src/cli_command_locator.dart';
export 'src/codex_cli_locator.dart';
export 'src/compatibility_agent_provider_plugin.dart';
export 'src/datasources/acp/grok_acp_agent_provider.dart'
    hide JsonRpcPeerFactory;
export 'src/datasources/acp/grok_models_cli.dart';
export 'src/datasources/acp/grok_permission_policy_adapter.dart';
export 'src/datasources/acp/grok_process_starter.dart';
export 'src/datasources/app_server/codex_app_server_agent_provider.dart';
export 'src/datasources/app_server/codex_permission_policy_adapter.dart';
export 'src/datasources/app_server/codex_process_starter.dart';
export 'src/datasources/claude_code/claude_code_agent_provider.dart';
export 'src/datasources/claude_code/claude_code_anthropic_api_client.dart';
export 'src/datasources/claude_code/claude_code_cli_metadata.dart';
export 'src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
export 'src/datasources/claude_code/claude_code_cli_metadata_probe.dart';
export 'src/datasources/claude_code/claude_code_control_request_handler.dart';
export 'src/datasources/claude_code/claude_code_event_mapper.dart';
export 'src/datasources/claude_code/claude_code_file_change_tracker.dart';
export 'src/datasources/claude_code/claude_code_hidden_thread_store.dart';
export 'src/datasources/claude_code/claude_code_macos_keychain_source.dart';
export 'src/datasources/claude_code/claude_code_model_catalog.dart';
export 'src/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
export 'src/datasources/claude_code/claude_code_permission_policy_adapter.dart';
export 'src/datasources/claude_code/claude_code_plan_approval_adapter.dart';
export 'src/datasources/claude_code/claude_code_process_starter.dart';
export 'src/datasources/claude_code/claude_code_question_adapter.dart';
export 'src/datasources/claude_code/claude_code_session_history_reader.dart';
export 'src/datasources/claude_code/claude_code_usage_quota_adapter.dart';
export 'src/datasources/claude_code/stream_json_peer.dart';
export 'src/datasources/local_history/grok_chat_history_parser.dart';
export 'src/datasources/local_history/grok_session_history_reader.dart';
export 'src/datasources/local_history/grok_updates_history_parser.dart';
export 'src/datasources/local_history/grok_user_content_parser.dart';
export 'src/datasources/transport/json_rpc_stdio_transport.dart';
export 'src/datasources/transport/provider_operation_scheduler.dart';
export 'src/datasources/transport/provider_runtime_json_rpc_peer.dart';
export 'src/default_agent_provider_factory.dart';
export 'src/grok_cli_locator.dart';
export 'src/mappers/acp_content_codec.dart';
export 'src/mappers/acp_permission_mapper.dart';
export 'src/mappers/acp_session_config_mapper.dart';
export 'src/mappers/acp_session_update_decoder.dart';
export 'src/mappers/claude_code_initialize_metadata_mapper.dart';
export 'src/mappers/claude_code_permission_mode_codec.dart';
export 'src/mappers/claude_code_stream_identity.dart';
export 'src/mappers/claude_code_usage_quota_mapper.dart';
export 'src/mappers/codex_permission_policy_codec.dart';
export 'src/mappers/context_window_codec.dart';
export 'src/mappers/grok_acp_notification_mapper.dart';
export 'src/mappers/grok_billing_quota_mapper.dart';
export 'src/mappers/grok_error_normalizer.dart';
export 'src/mappers/grok_file_change_tracker.dart';
export 'src/mappers/grok_permission_mode_codec.dart';
export 'src/mappers/grok_question_mapper.dart';
export 'src/mappers/grok_session_update_mapper.dart';
export 'src/mappers/grok_skills_mapper.dart';
export 'src/mappers/grok_stream_identity.dart';
export 'src/native_agent_provider_bundles.dart';

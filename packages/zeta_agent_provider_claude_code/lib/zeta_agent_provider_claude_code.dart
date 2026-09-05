/// Provider 插件入口与稳定编译期身份。
library;

export 'claude_code_plugin.dart';

// WP-C 过渡导出：供 manifest 宿主注入与已登记的 management/usage 调用点使用。
// WP-D 收口后，保留宿主注入类型，其余实现仅经独立 testing barrel 提供。
export 'src/claude_code_cli_locator.dart'
    show ClaudeCodeCliLocator, looksLikeClaudeCodeCliPath;
export 'src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart'
    show ClaudeCodeCliMetadataLoader;
export 'src/datasources/claude_code/claude_code_cli_metadata_probe.dart'
    show
        ClaudeCodeCliMetadataProbe,
        ClaudeCodeCliMetadataProbeException,
        ClaudeCodeCliMetadataProbeFailure;
export 'src/datasources/claude_code/claude_code_hidden_thread_store.dart'
    show ClaudeCodeHiddenThreadStore, FileClaudeCodeHiddenThreadStore;
export 'src/datasources/claude_code/claude_code_permission_policy_adapter.dart'
    show
        ClaudeCodeSessionDecisionStoreFactory,
        FileClaudeCodeSessionDecisionStore;
export 'src/datasources/claude_code/claude_code_provider_config.dart'
    show claudeCodeAccountDataEnrichmentKey;
export 'src/datasources/claude_code/claude_code_session_history_reader.dart'
    show ClaudeCodeSessionHistoryReader;

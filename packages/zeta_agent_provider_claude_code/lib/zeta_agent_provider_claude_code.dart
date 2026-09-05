/// Provider 插件入口与稳定编译期身份。
library;

export 'claude_code_plugin.dart';

// manifest 所需的宿主注入类型。
export 'src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart'
    show ClaudeCodeCliMetadataLoader;
export 'src/datasources/claude_code/claude_code_hidden_thread_store.dart'
    show ClaudeCodeHiddenThreadStore, FileClaudeCodeHiddenThreadStore;
export 'src/datasources/claude_code/claude_code_permission_policy_adapter.dart'
    show
        ClaudeCodeSessionDecisionStoreFactory,
        FileClaudeCodeSessionDecisionStore;

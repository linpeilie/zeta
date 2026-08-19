import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';

/// Claude Code 模型目录：只接受 CLI initialize 返回的当前有效选项。
///
/// 动态结果只在当前 Provider 实例内缓存；[refreshModels] 绕过该缓存。
final class ClaudeCodeModelCatalog {
  /// Creates a [ClaudeCodeModelCatalog].
  ClaudeCodeModelCatalog({required ClaudeCodeCliMetadataLoader metadataLoader})
    : _loadCliMetadata = metadataLoader;

  final ClaudeCodeCliMetadataLoader _loadCliMetadata;

  AgentModelList? _cachedModels;

  /// Runs `listModels`.
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    final cached = _cachedModels;
    if (cached != null) {
      return cached;
    }
    return _loadAndCache();
  }

  /// Runs `refreshModels`.
  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) {
    return _loadAndCache();
  }

  Future<AgentModelList> _loadAndCache() async {
    final models = await _loadCurrentModels();
    _cachedModels = models;
    return models;
  }

  Future<AgentModelList> _loadCurrentModels() async {
    try {
      final metadata = await _loadCliMetadata();
      if (metadata.models.models.isNotEmpty) {
        return metadata.models;
      }
    } on Object catch (_) {
      // 不向共享 repository 或日志上浮 CLI 原始异常文本。
      throw StateError('Claude Code CLI model metadata is unavailable');
    }
    throw StateError('Claude Code CLI returned no available models');
  }
}

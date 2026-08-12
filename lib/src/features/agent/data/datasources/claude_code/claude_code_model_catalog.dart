import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_model_catalog_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Claude Code 账号数据增强开关在 Provider 配置中的稳定 key。
const String claudeCodeAccountDataEnrichmentKey =
    'claudeCode.accountDataEnrichment';

typedef ClaudeCodeCredentialsLoader =
    Future<ClaudeCodeOAuthCredentials?> Function();

typedef ClaudeCodeRemoteModelsLoader =
    Future<Map<String, Object?>?> Function({
      required String accessToken,
      required bool isSubscriptionOAuth,
    });

/// Claude Code CLI 无模型目录端点时使用的静态兜底目录。
///
/// 明确版本便于固定复现性，短别名由 Claude Code CLI 解析到当前版本。
const AgentModelList claudeCodeStaticModelCatalog = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'claude-opus-4-7',
      model: 'claude-opus-4-7',
      displayName: 'Opus 4.7',
      description: '适合复杂推理与高难度编程任务。',
    ),
    AgentModelInfo(
      id: 'claude-sonnet-4-6',
      model: 'claude-sonnet-4-6',
      displayName: 'Sonnet 4.6',
      description: '性能、速度与成本的平衡选择。',
    ),
    AgentModelInfo(
      id: 'claude-haiku-4-5-20251001',
      model: 'claude-haiku-4-5-20251001',
      displayName: 'Haiku 4.5',
      description: '适合低延迟、轻量任务。',
    ),
    AgentModelInfo(
      id: 'opus',
      model: 'opus',
      displayName: 'Opus（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Opus 版本。',
    ),
    AgentModelInfo(
      id: 'sonnet',
      model: 'sonnet',
      displayName: 'Sonnet（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Sonnet 版本。',
      isDefault: true,
    ),
    AgentModelInfo(
      id: 'haiku',
      model: 'haiku',
      displayName: 'Haiku（最新别名）',
      description: '由 Claude Code CLI 解析到当前 Haiku 版本。',
    ),
  ],
);

/// Claude Code 模型目录：动态优先，任何失败都回退静态目录。
///
/// 动态结果只在当前 Provider 实例内缓存；[refreshModels] 绕过该缓存。
/// 账号数据增强关闭时不会读取凭据，也不会调用远端 loader。
final class ClaudeCodeModelCatalog {
  ClaudeCodeModelCatalog({
    this.accountDataEnrichmentEnabled = true,
    ClaudeCodeCredentialsLoader? credentialsLoader,
    ClaudeCodeRemoteModelsLoader? remoteModelsLoader,
  }) : _credentialsLoader =
           credentialsLoader ?? ClaudeCodeOAuthCredentialsReader().read,
       _remoteModelsLoader =
           remoteModelsLoader ?? ClaudeCodeAnthropicApiClient().listModels;

  final bool accountDataEnrichmentEnabled;
  final ClaudeCodeCredentialsLoader _credentialsLoader;
  final ClaudeCodeRemoteModelsLoader _remoteModelsLoader;

  AgentModelList? _cachedModels;

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

  Future<AgentModelList> refreshModels({
    int limit = 20,
    bool includeHidden = false,
  }) {
    return _loadAndCache();
  }

  Future<AgentModelList> _loadAndCache() async {
    if (!accountDataEnrichmentEnabled) {
      return _cache(claudeCodeStaticModelCatalog);
    }

    try {
      final credentials = await _credentialsLoader();
      if (credentials == null) {
        return _cache(claudeCodeStaticModelCatalog);
      }
      final response = await _remoteModelsLoader(
        accessToken: credentials.accessToken,
        isSubscriptionOAuth: true,
      );
      final dynamicModels = mapClaudeCodeModelCatalog(response);
      if (dynamicModels.models.isNotEmpty) {
        return _cache(dynamicModels);
      }
    } catch (_) {
      // 凭据或动态目录是 best-effort 增强，异常不得阻断静态模型选择。
    }
    return _cache(claudeCodeStaticModelCatalog);
  }

  AgentModelList _cache(AgentModelList models) {
    _cachedModels = models;
    return models;
  }
}

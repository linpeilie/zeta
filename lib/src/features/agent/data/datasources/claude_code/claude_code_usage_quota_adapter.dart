import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_usage_quota_mapper.dart';
import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';

typedef ClaudeCodeUsageCredentialsLoader =
    Future<ClaudeCodeOAuthCredentials?> Function();

typedef ClaudeCodeRemoteUsageLoader =
    Future<Map<String, Object?>?> Function({
      required String accessToken,
      required String? claudeCodeVersion,
    });

/// Claude Code 套餐用量的只读、失败闭合适配器。
///
/// 成功与失败结果都按 60 秒节流；并发读取复用同一个 Future，避免刷新动作形成
/// 请求风暴。OAuth 凭据只在一次请求期间传递，不在此对象中缓存。
final class ClaudeCodeUsageQuotaAdapter {
  ClaudeCodeUsageQuotaAdapter({
    required this.providerId,
    required this.providerName,
    this.accountDataEnrichmentEnabled = true,
    this.usesApiKey = false,
    this.claudeCodeVersion,
    ClaudeCodeUsageCredentialsLoader? credentialsLoader,
    ClaudeCodeRemoteUsageLoader? remoteUsageLoader,
    DateTime Function()? clock,
  }) : _credentialsLoader =
           credentialsLoader ?? ClaudeCodeOAuthCredentialsReader().read,
       _remoteUsageLoader =
           remoteUsageLoader ?? ClaudeCodeAnthropicApiClient().readUsageQuota,
       _clock = clock ?? DateTime.now;

  static const Duration refreshInterval = Duration(seconds: 60);

  final String providerId;
  final String providerName;
  final bool accountDataEnrichmentEnabled;
  final bool usesApiKey;
  final String? claudeCodeVersion;
  final ClaudeCodeUsageCredentialsLoader _credentialsLoader;
  final ClaudeCodeRemoteUsageLoader _remoteUsageLoader;
  final DateTime Function() _clock;

  DateTime? _lastAttemptAt;
  AgentUsageQuotaSnapshot? _lastResult;
  Future<AgentUsageQuotaSnapshot?>? _inFlight;

  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
    if (!accountDataEnrichmentEnabled || usesApiKey) {
      return null;
    }

    final inFlight = _inFlight;
    if (inFlight != null) {
      return inFlight;
    }

    final now = _clock();
    final lastAttemptAt = _lastAttemptAt;
    if (lastAttemptAt != null) {
      final elapsed = now.difference(lastAttemptAt);
      if (!elapsed.isNegative && elapsed < refreshInterval) {
        return _lastResult;
      }
    }

    _lastAttemptAt = now;
    final operation = _load();
    _inFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    }
  }

  Future<AgentUsageQuotaSnapshot?> _load() async {
    AgentUsageQuotaSnapshot? result;
    try {
      final credentials = await _credentialsLoader();
      if (credentials != null) {
        final response = await _remoteUsageLoader(
          accessToken: credentials.accessToken,
          claudeCodeVersion: claudeCodeVersion,
        );
        result = mapClaudeCodeUsageQuota(
          response,
          providerId: providerId,
          providerName: providerName,
          subscriptionType: credentials.subscriptionType,
        );
      }
    } catch (_) {
      // 凭据、网络与映射都是 best-effort 增强，失败不得穿透到用量面板。
    }
    _lastResult = result;
    return result;
  }
}

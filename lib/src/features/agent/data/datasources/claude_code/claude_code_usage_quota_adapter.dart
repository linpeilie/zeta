import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_anthropic_api_client.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
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
    required ClaudeCodeCliMetadataLoader metadataLoader,
    ClaudeCodeUsageCredentialsLoader? credentialsLoader,
    ClaudeCodeRemoteUsageLoader? remoteUsageLoader,
    DateTime Function()? clock,
  }) : _loadMetadata = metadataLoader,
       _credentialsLoader =
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
  final ClaudeCodeCliMetadataLoader _loadMetadata;
  final ClaudeCodeUsageCredentialsLoader _credentialsLoader;
  final ClaudeCodeRemoteUsageLoader _remoteUsageLoader;
  final DateTime Function() _clock;

  DateTime? _lastAttemptAt;
  AgentUsageQuotaSnapshot? _lastResult;
  Future<AgentUsageQuotaSnapshot?>? _inFlight;

  Future<AgentUsageQuotaSnapshot?> readUsageQuota() async {
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
    final operation = _load(now);
    _inFlight = operation;
    try {
      return await operation;
    } finally {
      if (identical(_inFlight, operation)) {
        _inFlight = null;
      }
    }
  }

  Future<AgentUsageQuotaSnapshot?> _load(DateTime attemptedAt) async {
    String? subscriptionType;
    try {
      subscriptionType = (await _loadMetadata()).subscriptionType;
    } catch (_) {
      // 套餐名称是 best-effort CLI metadata；失败时仍允许旧额度 REST 返回窗口。
    }

    Map<String, Object?>? response;
    if (accountDataEnrichmentEnabled && !usesApiKey) {
      try {
        final credentials = await _credentialsLoader();
        if (credentials != null &&
            _canReadSubscriptionUsage(credentials, attemptedAt)) {
          response = await _remoteUsageLoader(
            accessToken: credentials.accessToken,
            claudeCodeVersion: claudeCodeVersion,
          );
        }
      } catch (_) {
        // 凭据和网络是可选额度增强；失败时仍返回 metadata 提供的 plan-only 快照。
      }
    }
    final result = mapClaudeCodeUsageQuota(
      response,
      providerId: providerId,
      providerName: providerName,
      subscriptionType: subscriptionType,
    );
    _lastResult = result;
    return result;
  }
}

bool _canReadSubscriptionUsage(
  ClaudeCodeOAuthCredentials credentials,
  DateTime attemptedAt,
) {
  if (credentials.accessToken.trim().isEmpty ||
      !credentials.expiresAt.isAfter(attemptedAt)) {
    return false;
  }
  // Claude Code 用 user:inference 区分 Claude.ai 订阅 OAuth，并额外要求
  // user:profile 才访问 usage/profile 端点；service-key OAuth 因而 fail-closed。
  return credentials.scopes.contains('user:inference') &&
      credentials.scopes.contains('user:profile');
}

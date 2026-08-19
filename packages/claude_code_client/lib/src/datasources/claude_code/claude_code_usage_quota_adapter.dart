import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:claude_code_client/src/claude_text_catalog.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_anthropic_api_client.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_cli_metadata_coordinator.dart';
import 'package:claude_code_client/src/datasources/claude_code/claude_code_oauth_credentials_reader.dart';
import 'package:claude_code_client/src/mappers/claude_code_usage_quota_mapper.dart';
import 'package:zeta_logging/zeta_logging.dart';

/// The `ClaudeCodeUsageCredentialsLoader` value.
typedef ClaudeCodeUsageCredentialsLoader =
    Future<ClaudeCodeOAuthCredentials?> Function();

/// Runs `Function`.
typedef ClaudeCodeRemoteUsageLoader = Future<Map<String, Object?>?> Function({
  required String accessToken,
  required String? claudeCodeVersion,
});

/// Claude Code 套餐用量的只读、失败闭合适配器。
///
/// 成功与失败结果都按 60 秒节流；并发读取复用同一个 Future，避免刷新动作形成
/// 请求风暴。OAuth 凭据只在一次请求期间传递，不在此对象中缓存。
final class ClaudeCodeUsageQuotaAdapter {
  /// Creates a [ClaudeCodeUsageQuotaAdapter].
  ClaudeCodeUsageQuotaAdapter({
    required this.providerId,
    required this.providerName,
    required ClaudeCodeCliMetadataLoader metadataLoader,
    this.accountDataEnrichmentEnabled = true,
    this.usesApiKey = false,
    this.claudeCodeVersion,
    ClaudeCodeUsageCredentialsLoader? credentialsLoader,
    ClaudeCodeRemoteUsageLoader? remoteUsageLoader,
    DateTime Function()? clock,
    this.textCatalog = const ClaudeCodeTextCatalog(),
    AppLogger? logger,
  }) : _loadMetadata = metadataLoader,
       _credentialsLoader =
           credentialsLoader ?? ClaudeCodeOAuthCredentialsReader().read,
       _remoteUsageLoader =
           remoteUsageLoader ??
           ClaudeCodeAnthropicApiClient(logger: logger).readUsageQuota,
       _clock = clock ?? DateTime.now;

  /// Runs `Duration`.
  static const Duration refreshInterval = Duration(seconds: 60);

  /// The `providerId` value.
  final String providerId;

  /// The `providerName` value.
  final String providerName;

  /// The `accountDataEnrichmentEnabled` value.
  final bool accountDataEnrichmentEnabled;

  /// The `usesApiKey` value.
  final bool usesApiKey;

  /// The `claudeCodeVersion` value.
  final String? claudeCodeVersion;
  final ClaudeCodeCliMetadataLoader _loadMetadata;
  final ClaudeCodeUsageCredentialsLoader _credentialsLoader;
  final ClaudeCodeRemoteUsageLoader _remoteUsageLoader;
  final DateTime Function() _clock;

  /// The `textCatalog` value.
  final ClaudeCodeTextCatalog textCatalog;

  DateTime? _lastAttemptAt;
  AgentUsageQuotaSnapshot? _lastResult;
  Future<AgentUsageQuotaSnapshot?>? _inFlight;

  /// Runs `readUsageQuota`.
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
    } on Object catch (_) {
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
      } on Object catch (_) {
        // 凭据和网络是可选额度增强；失败时仍返回 metadata 提供的 plan-only 快照。
      }
    }
    final result = mapClaudeCodeUsageQuota(
      response,
      providerId: providerId,
      providerName: providerName,
      subscriptionType: subscriptionType,
      textCatalog: textCatalog,
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

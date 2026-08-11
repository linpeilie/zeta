import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/logging/app_logging.dart';

final _log = loggerFor('zeta.agent.claude_code.anthropic_api');

typedef ClaudeCodeHttpClientFactory = HttpClient Function();
typedef ClaudeCodeHttpStatusLogger = void Function(int statusCode);

/// Claude Code 账号数据增强使用的 Anthropic 只读 API 客户端。
///
/// 客户端只发 GET，请求失败时不重试并返回 `null`。每次调用都创建短生命周期
/// [HttpClient]，结束时强制关闭，避免在 Provider 生命周期内保留认证连接。
final class ClaudeCodeAnthropicApiClient {
  ClaudeCodeAnthropicApiClient({
    ClaudeCodeHttpClientFactory? httpClientFactory,
    ClaudeCodeHttpStatusLogger? statusLogger,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _statusLogger = statusLogger ?? _logStatusCode;

  static const Duration requestTimeout = Duration(seconds: 10);
  static final Uri modelsUri = Uri.parse(
    'https://api.anthropic.com/v1/models?limit=100',
  );
  static final Uri usageQuotaUri = Uri.parse(
    'https://api.anthropic.com/api/oauth/usage',
  );

  final ClaudeCodeHttpClientFactory _httpClientFactory;
  final ClaudeCodeHttpStatusLogger _statusLogger;

  /// 获取模型目录；订阅 OAuth 与 Console API Key 使用互斥的鉴权头。
  Future<Map<String, Object?>?> listModels({
    required String accessToken,
    required bool isSubscriptionOAuth,
  }) {
    return _get(
      modelsUri,
      accessToken: accessToken,
      isSubscriptionOAuth: isSubscriptionOAuth,
      extraHeaders: isSubscriptionOAuth
          ? const <String, String>{'anthropic-beta': 'oauth-2025-04-20'}
          : const <String, String>{},
    );
  }

  /// 获取订阅套餐用量；调用方负责在 API Key 模式下提前短路。
  Future<Map<String, Object?>?> readUsageQuota({
    required String accessToken,
    required String? claudeCodeVersion,
  }) {
    final version = claudeCodeVersion?.trim();
    return _get(
      usageQuotaUri,
      accessToken: accessToken,
      isSubscriptionOAuth: true,
      extraHeaders: <String, String>{
        'anthropic-beta': 'oauth-2025-04-20',
        if (version != null && version.isNotEmpty)
          HttpHeaders.userAgentHeader: 'claude-code/$version',
      },
    );
  }

  Future<Map<String, Object?>?> _get(
    Uri uri, {
    required String accessToken,
    required bool isSubscriptionOAuth,
    required Map<String, String> extraHeaders,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set('anthropic-version', '2023-06-01');
      if (isSubscriptionOAuth) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $accessToken',
        );
      } else {
        request.headers.set('x-api-key', accessToken);
      }
      extraHeaders.forEach(request.headers.set);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        _statusLogger(response.statusCode);
        return null;
      }
      final body = await response
          .transform(const Utf8Decoder())
          .join()
          .timeout(requestTimeout);
      final decoded = jsonDecode(body);
      if (decoded is! Map) {
        return null;
      }
      return decoded.map<String, Object?>(
        (key, value) => MapEntry(key.toString(), value),
      );
    } catch (_) {
      // 网络、超时与响应解析错误都是 best-effort 降级，且不记录敏感原文。
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

void _logStatusCode(int statusCode) {
  _log.w('Claude Code Anthropic API returned HTTP $statusCode');
}

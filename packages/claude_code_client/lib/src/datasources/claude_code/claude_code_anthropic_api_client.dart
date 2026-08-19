import 'dart:convert';
import 'dart:io';

import 'package:zeta_logging/zeta_logging.dart';

/// Runs `Function`.
typedef ClaudeCodeHttpClientFactory = HttpClient Function();

/// Runs `Function`.
typedef ClaudeCodeHttpStatusLogger = void Function(int statusCode);

/// Claude Code 额度详情增强使用的 Anthropic 只读 API 客户端。
///
/// 客户端只发 GET，请求失败时不重试并返回 `null`。每次调用都创建短生命周期
/// [HttpClient]，结束时强制关闭，避免在 Provider 生命周期内保留认证连接。
final class ClaudeCodeAnthropicApiClient {
  /// Creates a [ClaudeCodeAnthropicApiClient].
  ClaudeCodeAnthropicApiClient({
    ClaudeCodeHttpClientFactory? httpClientFactory,
    this.statusLogger,
    AppLogger? logger,
  }) : _httpClientFactory = httpClientFactory ?? HttpClient.new,
       _log = logger ?? loggerFor('zeta.agent.claude_code.anthropic_api');

  // 与 Claude Code 的 usage client 保持同一超时上限；失败由上层降级为 plan-only。
  /// Runs `Duration`.
  static const Duration requestTimeout = Duration(seconds: 5);

  /// Runs `parse`.
  static final Uri usageQuotaUri = Uri.parse(
    'https://api.anthropic.com/api/oauth/usage',
  );

  final ClaudeCodeHttpClientFactory _httpClientFactory;

  /// The `statusLogger` value.
  final ClaudeCodeHttpStatusLogger? statusLogger;
  final AppLogger _log;

  /// 获取订阅套餐用量；调用方负责在 API Key 模式下提前短路。
  Future<Map<String, Object?>?> readUsageQuota({
    required String accessToken,
    required String? claudeCodeVersion,
  }) {
    final version = claudeCodeVersion?.trim();
    return _get(
      usageQuotaUri,
      accessToken: accessToken,
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
    required Map<String, String> extraHeaders,
  }) async {
    final client = _httpClientFactory();
    try {
      final request = await client.getUrl(uri).timeout(requestTimeout);
      request.headers.set('anthropic-version', '2023-06-01');
      request.headers.set(
        HttpHeaders.authorizationHeader,
        'Bearer $accessToken',
      );
      extraHeaders.forEach(request.headers.set);
      final response = await request.close().timeout(requestTimeout);
      if (response.statusCode != HttpStatus.ok) {
        final statusCode = response.statusCode;
        final statusLoggerCallback = statusLogger;
        if (statusLoggerCallback != null) {
          statusLoggerCallback(statusCode);
        } else {
          _log.w('Claude Code Anthropic API returned HTTP $statusCode');
        }
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
    } on Object catch (_) {
      // 网络、超时与响应解析错误都是 best-effort 降级，且不记录敏感原文。
      return null;
    } finally {
      client.close(force: true);
    }
  }
}

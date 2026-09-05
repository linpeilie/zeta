import 'package:zeta_agent_core/src/domain/agent_ui_text_catalog.dart';

/// Provider 错误在时间线中的用户可见文案。
///
/// 同时服务 live（[AgentErrorEvent] / turn.failed）与 history
/// （[AgentHistoryTurn.errorMessage] / [AgentHistoryTurn.errorCode]），
/// 避免两套提示语义漂移。
abstract final class AgentProviderErrorPresentation {
  /// 组装时间线系统消息正文。
  ///
  /// [message] 为 provider 原始概要；[code] 为归一化错误码
  /// （如 Codex `codexErrorInfo`）；[prefixTurnFailed] 为 true 时加
  /// turn-failed 前缀（仅用于 turn 终态失败且未先收到 error 事件）。
  static String formatUserVisibleText({
    required String message,
    required AgentUiTextCatalog catalog,
    String? details,
    String? code,
    bool? willRetry,
    bool prefixTurnFailed = false,
  }) {
    final trimmed = message.trim();
    final effectiveCode = resolveCode(code: code, message: trimmed);
    final buffer = StringBuffer();
    if (prefixTurnFailed) {
      buffer.write(catalog.turnFailedPrefix);
    }
    buffer.write(trimmed.isEmpty ? catalog.unknownProviderError : trimmed);
    final trimmedDetails = details?.trim();
    if (trimmedDetails != null && trimmedDetails.isNotEmpty) {
      buffer.write(': $trimmedDetails');
    }
    if (willRetry ?? false) {
      buffer.write(catalog.serverWillRetry);
    }
    final guidance = catalog.errorGuidance(effectiveCode ?? '');
    if (guidance != null) {
      buffer.write(guidance);
    }
    return buffer.toString();
  }

  /// 解析有效错误码：优先显式 [code]，否则从常见原文启发式识别。
  static String? resolveCode({String? code, String? message}) {
    final normalized = code?.trim();
    if (normalized != null && normalized.isNotEmpty) {
      return normalized;
    }
    final text = message?.trim() ?? '';
    if (text.isEmpty) {
      return null;
    }
    final lower = text.toLowerCase();
    if (lower.contains('at capacity') ||
        lower.contains('server overloaded') ||
        lower.contains('model is overloaded')) {
      return 'serverOverloaded';
    }
    if (lower.contains('context window') && lower.contains('exceed')) {
      return 'contextWindowExceeded';
    }
    if (lower.contains('usage limit') || lower.contains('rate limit')) {
      return 'usageLimitExceeded';
    }
    if (lower.contains('session budget')) {
      return 'sessionBudgetExceeded';
    }
    return null;
  }
}

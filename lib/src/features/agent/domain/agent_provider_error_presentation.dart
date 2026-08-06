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
  /// `Turn failed: ` 前缀（仅用于 turn 终态失败且未先收到 error 事件）。
  static String formatUserVisibleText({
    required String message,
    String? details,
    String? code,
    bool? willRetry,
    bool prefixTurnFailed = false,
  }) {
    final trimmed = message.trim();
    final effectiveCode = resolveCode(code: code, message: trimmed);
    final buffer = StringBuffer();
    if (prefixTurnFailed) {
      buffer.write('Turn failed: ');
    }
    buffer.write(trimmed.isEmpty ? 'Unknown provider error' : trimmed);
    final trimmedDetails = details?.trim();
    if (trimmedDetails != null && trimmedDetails.isNotEmpty) {
      buffer.write(': $trimmedDetails');
    }
    if (willRetry ?? false) {
      buffer.write('（服务端将自动重试）');
    }
    final guidance = guidanceForCode(effectiveCode);
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

  /// 按错误码返回可操作的中文引导；未知码返回 null。
  static String? guidanceForCode(String? code) {
    return switch (code) {
      'serverOverloaded' => '。当前模型容量已满，请切换其他模型或稍后重试。',
      'usageLimitExceeded' => '。用量或速率额度已用尽，请检查账户额度或稍后重试。',
      'sessionBudgetExceeded' => '。会话预算已用尽，请开启新会话或调整预算后继续。',
      'unauthorized' => '。认证失败，请检查登录状态或 API 凭证后重试。',
      'internalServerError' => '。服务端内部错误，请稍后重试；若持续出现可切换模型。',
      'httpConnectionFailed' ||
      'responseStreamConnectionFailed' ||
      'responseStreamDisconnected' => '。网络连接异常，请检查网络后重试。',
      'responseTooManyFailedAttempts' => '。多次重试仍失败，请稍后重试或切换模型。',
      _ => null,
    };
  }
}

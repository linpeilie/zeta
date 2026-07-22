/// Grok 限流场景统一使用的用户可见摘要。
const grokRateLimitErrorMessage =
    'Grok rate limit reached. Please try again later.';

/// Grok 未提供可安全展示细节时使用的通用摘要。
const grokRequestFailedErrorMessage = 'Grok request failed. Please try again.';

/// 判断 Grok 终态或重试诊断是否表示限流。
///
/// [reason] 仅参与分类，不应直接进入用户可见文本。
bool isGrokRateLimitFailure({
  String? stopReason,
  String? reason,
  bool isRateLimited = false,
}) {
  if (isRateLimited) {
    return true;
  }
  final diagnostic = '${stopReason ?? ''}\n${reason ?? ''}'.toLowerCase();
  return diagnostic.contains('rate_limit') ||
      diagnostic.contains('rate limited') ||
      diagnostic.contains('too many requests') ||
      diagnostic.contains('status 429') ||
      diagnostic.contains('usage-exhausted');
}

/// 将 Grok 终态原因映射为安全、稳定的展示摘要。
String grokTerminalErrorMessage(String stopReason) {
  return isGrokRateLimitFailure(stopReason: stopReason)
      ? grokRateLimitErrorMessage
      : stopReason;
}

/// 将 Grok 重试耗尽记录映射为安全、稳定的展示摘要。
String grokRetryFailureMessage({
  required String? reason,
  required bool isRateLimited,
}) {
  return isGrokRateLimitFailure(reason: reason, isRateLimited: isRateLimited)
      ? grokRateLimitErrorMessage
      : grokRequestFailedErrorMessage;
}

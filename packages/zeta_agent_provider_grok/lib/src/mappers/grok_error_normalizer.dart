/// Grok 限流场景统一使用的用户可见摘要。
const grokRateLimitErrorMessage =
    'Grok rate limit reached. Please try again later.';

/// Grok 未提供可安全展示细节时使用的通用摘要。
const grokRequestFailedErrorMessage = 'Grok request failed. Please try again.';

/// Grok 传输层自动重试中的用户可见摘要。
const grokTransportRetryingErrorMessage = 'Grok connection interrupted';

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

/// 占位式 stopReason：本身不含任何可读信息，不能直接展示给用户。
bool _isPlaceholderStopReason(String stopReason) {
  final normalized = stopReason.trim().toLowerCase();
  return normalized.isEmpty ||
      normalized == 'error' ||
      normalized == 'unknown' ||
      normalized == 'exception';
}

/// 将 Grok 终态映射为安全、稳定的展示摘要。
///
/// 优先级：
/// 1. 限流（429 / usage-exhausted 等）→ 统一 [grokRateLimitErrorMessage]；
/// 2. 服务端下发了真实错误文案 [agentResult] → 直接展示（如
///    `API error (status 402 Payment Required): ...`）；
/// 3. [stopReason] 是占位词（`error`）且无 [agentResult] → 通用摘要；
/// 4. 兜底使用 [stopReason] 原文。
String grokTerminalErrorMessage(String stopReason, {String? agentResult}) {
  if (isGrokRateLimitFailure(stopReason: stopReason, reason: agentResult)) {
    return grokRateLimitErrorMessage;
  }
  final result = agentResult?.trim();
  if (result != null && result.isNotEmpty) {
    return result;
  }
  if (_isPlaceholderStopReason(stopReason)) {
    return grokRequestFailedErrorMessage;
  }
  return stopReason;
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

/// 将进行中的 Grok 传输重试映射为安全、稳定的展示摘要。
///
/// [attempt] / [maxRetries] 仅用于可选进度提示；[reason] 只参与限流分类，
/// 不进入用户可见正文。
String grokTransportRetryingMessage({
  String? reason,
  bool isRateLimited = false,
  int? attempt,
  int? maxRetries,
}) {
  if (isGrokRateLimitFailure(reason: reason, isRateLimited: isRateLimited)) {
    return grokRateLimitErrorMessage;
  }
  if (attempt != null && attempt > 0 && maxRetries != null && maxRetries > 0) {
    return '$grokTransportRetryingErrorMessage (retry $attempt/$maxRetries)';
  }
  if (attempt != null && attempt > 0) {
    return '$grokTransportRetryingErrorMessage (retry $attempt)';
  }
  return grokTransportRetryingErrorMessage;
}

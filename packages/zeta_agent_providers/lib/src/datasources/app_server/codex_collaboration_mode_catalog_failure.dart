part of 'codex_app_server_agent_provider.dart';

/// 对话模式目录发现的内部失败分类，用于区分熔断与可重试错误。
enum _CodexConversationModeCatalogFailureKind {
  unsupportedRuntime,
  malformedResponse,
  timeout,
  transport,
}

_CodexConversationModeCatalogFailureKind
_classifyConversationModeCatalogFailure(Object error) {
  if (error is JsonRpcException) {
    final message = error.error.message.toLowerCase();
    final experimentalDisabled =
        message.contains('experimental') &&
        (message.contains('disabled') || message.contains('not enabled'));
    if (error.error.code == -32601 || experimentalDisabled) {
      return _CodexConversationModeCatalogFailureKind.unsupportedRuntime;
    }
  }
  if (error is FormatException) {
    return _CodexConversationModeCatalogFailureKind.malformedResponse;
  }
  if (error is TimeoutException) {
    return _CodexConversationModeCatalogFailureKind.timeout;
  }
  return _CodexConversationModeCatalogFailureKind.transport;
}

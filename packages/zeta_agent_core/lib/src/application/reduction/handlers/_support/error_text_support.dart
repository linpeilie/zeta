import 'package:zeta_agent_core/src/domain/agent_models.dart';

/// 模型改道原因文案。
String modelRerouteReasonLabel(AgentUiTextCatalog catalog, String reason) {
  return switch (reason) {
    'highRiskCyberActivity' => catalog.rerouteReasonHighRisk,
    _ => catalog.rerouteReasonUnknown(reason),
  };
}

/// 用户可见错误正文。
String errorMessageText(AgentUiTextCatalog catalog, AgentErrorEvent event) {
  return AgentProviderErrorPresentation.formatUserVisibleText(
    message: event.message,
    catalog: catalog,
    details: event.details,
    code: event.code,
    willRetry: event.willRetry,
  );
}

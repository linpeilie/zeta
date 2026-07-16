/// Provider 运行时与 Zeta 协议适配层的兼容状态。
enum AgentRuntimeCompatibilityStatus {
  supported,
  supportedWithLimitedCapabilities,
  newerUntested,
  olderUnsupported,
  protocolMismatch,
}

/// Provider 初始化后暴露的中立运行时诊断信息。
///
/// UI 只消费该模型，不依赖 Codex、ACP 等供应商原始握手结构。
class AgentRuntimeInfo {
  const AgentRuntimeInfo({
    required this.protocolName,
    required this.protocolVersion,
    required this.compatibilityStatus,
    this.cliVersion,
    this.serverUserAgent,
    this.platform,
    this.homePath,
    this.experimentalApiEnabled = false,
  });

  final String protocolName;
  final String protocolVersion;
  final String? cliVersion;
  final String? serverUserAgent;
  final String? platform;
  final String? homePath;
  final bool experimentalApiEnabled;
  final AgentRuntimeCompatibilityStatus compatibilityStatus;
}

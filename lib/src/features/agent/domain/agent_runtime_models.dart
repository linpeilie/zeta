/// Provider 运行时与 Zeta 协议适配层的兼容状态。
enum AgentRuntimeCompatibilityStatus {
  supported,
  supportedWithLimitedCapabilities,
  newerUntested,
  olderUnsupported,
  protocolMismatch,
}

/// Provider 进程与协议连接的生命周期状态。
///
/// [closing] 开始后不再接受新的 RPC；[closed] 为当前 Provider 实例的终态。
enum AgentProviderLifecycleState {
  stopped,
  starting,
  initializing,
  ready,
  failed,
  closing,
  closed,
}

/// 标识一次具体 Provider 连接，防止重启后的旧请求污染新连接。
class AgentRuntimeScope {
  const AgentRuntimeScope({
    required this.runtimeId,
    required this.connectionEpoch,
  });

  final String runtimeId;
  final int connectionEpoch;

  @override
  bool operator ==(Object other) =>
      other is AgentRuntimeScope &&
      other.runtimeId == runtimeId &&
      other.connectionEpoch == connectionEpoch;

  @override
  int get hashCode => Object.hash(runtimeId, connectionEpoch);

  @override
  String toString() => '$runtimeId@$connectionEpoch';
}

/// Provider 初始化后暴露的中立运行时诊断信息。
///
/// UI 只消费该模型，不依赖 Codex、ACP 等供应商原始握手结构。
class AgentRuntimeInfo {
  const AgentRuntimeInfo({
    required this.runtimeId,
    required this.connectionEpoch,
    required this.protocolName,
    required this.protocolVersion,
    required this.compatibilityStatus,
    this.cliVersion,
    this.serverUserAgent,
    this.platform,
    this.homePath,
    this.experimentalApiEnabled = false,
  });

  final String runtimeId;
  final int connectionEpoch;
  final String protocolName;
  final String protocolVersion;
  final String? cliVersion;
  final String? serverUserAgent;
  final String? platform;
  final String? homePath;
  final bool experimentalApiEnabled;
  final AgentRuntimeCompatibilityStatus compatibilityStatus;
}

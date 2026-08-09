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

/// Provider 运行时实例的隔离范围。
///
/// [global] 由 `AgentProviderGlobalRuntime` 使用；[session] 仅由
/// `AgentConversationBinding` 生成并在草稿晋升后保持稳定。它是 registry 的内部
/// 隔离键，不暴露给 ViewModel，也不持有 Timer 或进程引用。
sealed class AgentProviderRuntimeScopeKey {
  const AgentProviderRuntimeScopeKey();

  /// 会话建立前的全局共享实例；也是未显式指定 scope 时的默认值。
  static const AgentProviderRuntimeScopeKey global =
      AgentProviderRuntimeGlobalScope._();

  /// 单个 Binding 专属的实例。[id] 是 Binding Manager 生成的稳定内部身份。
  const factory AgentProviderRuntimeScopeKey.session(String id) =
      AgentProviderRuntimeSessionScope;
}

/// [AgentProviderRuntimeScopeKey.global] 的具体类型；不对外单独构造，
/// 通过该静态常量访问。
final class AgentProviderRuntimeGlobalScope
    extends AgentProviderRuntimeScopeKey {
  const AgentProviderRuntimeGlobalScope._();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is AgentProviderRuntimeGlobalScope;

  @override
  int get hashCode => (AgentProviderRuntimeGlobalScope).hashCode;

  @override
  String toString() => 'global';
}

/// [AgentProviderRuntimeScopeKey.session] 的具体类型。
final class AgentProviderRuntimeSessionScope
    extends AgentProviderRuntimeScopeKey {
  const AgentProviderRuntimeSessionScope(this.id);

  /// Binding Manager 生成的稳定内部身份。
  final String id;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AgentProviderRuntimeSessionScope && other.id == id;

  @override
  int get hashCode => Object.hash(AgentProviderRuntimeSessionScope, id);

  @override
  String toString() => 'session($id)';
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

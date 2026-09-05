/// 一个 Provider 进程实例的稳定身份。
///
/// [providerId] 相同但 [generation] 不同的状态永不互通，避免已失效 runtime 的
/// 异步事件或操作污染新进程。
final class AgentProviderRuntimeIdentity {
  const AgentProviderRuntimeIdentity({
    required this.providerId,
    required this.generation,
    this.isProvisional = false,
  });

  final String providerId;
  final int generation;
  final bool isProvisional;

  @override
  bool operator ==(Object other) {
    return identical(this, other) ||
        other is AgentProviderRuntimeIdentity &&
            other.providerId == providerId &&
            other.generation == generation &&
            other.isProvisional == isProvisional;
  }

  @override
  int get hashCode => Object.hash(providerId, generation, isProvisional);

  @override
  String toString() => '$providerId@$generation${isProvisional ? "?" : ""}';
}

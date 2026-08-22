import 'package:zeta_agent_core/src/domain/agent_runtime_models.dart';

/// 一次 Provider 事件监听的资源身份。
///
/// Provider 尚未启动时 [runtimeScope] 可以为空；收到首个连接事件后由 Gate 绑定，
/// 此后 runtime/epoch 变化必须创建新的 listener generation。
final class AgentProviderEventListenerScope {
  AgentProviderEventListenerScope._(
    this.providerId,
    this.threadId,
    this.listenerGeneration,
    this._runtimeScope,
  );

  final String providerId;
  final String? threadId;
  final int listenerGeneration;
  AgentRuntimeScope? _runtimeScope;

  AgentRuntimeScope? get runtimeScope => _runtimeScope;

  String? get runtimeId => _runtimeScope?.runtimeId;

  int? get connectionEpoch => _runtimeScope?.connectionEpoch;

  @override
  String toString() =>
      '${_runtimeScope ?? 'unbound'}:$providerId:${threadId ?? '<all>'}'
      '#$listenerGeneration';
}

/// 隔离 Provider 重启、Thread 切换和异步 subscription 退出的旧事件。
final class AgentProviderEventListenerGate {
  int _nextGeneration = 0;
  AgentProviderEventListenerScope? _current;

  AgentProviderEventListenerScope? get current => _current;

  /// scope 是否仍是当前 listener。
  bool isCurrent(AgentProviderEventListenerScope scope) {
    return identical(_current, scope);
  }

  /// 异步收尾前确认期间没有创建更新的 generation。
  bool isLatestGeneration(AgentProviderEventListenerScope scope) {
    return scope.listenerGeneration == _nextGeneration;
  }

  AgentProviderEventListenerScope activate({
    required String providerId,
    required String? threadId,
    required AgentRuntimeScope? runtimeScope,
  }) {
    final scope = AgentProviderEventListenerScope._(
      providerId,
      threadId,
      ++_nextGeneration,
      runtimeScope,
    );
    _current = scope;
    return scope;
  }

  /// 使当前监听立即失效，避免切换过程中的异步事件进入新会话。
  void invalidate() {
    _nextGeneration += 1;
    _current = null;
  }

  /// 判断事件是否仍属于当前监听。
  ///
  /// [allowDetachedRuntime] 只用于连接关闭后由 Provider 主动发出的状态、错误和
  /// pending 交互收尾事件；有新 runtime 时仍严格拒绝旧连接事件。
  bool accepts(
    AgentProviderEventListenerScope scope, {
    required AgentRuntimeScope? currentRuntimeScope,
    bool allowDetachedRuntime = false,
  }) {
    if (!identical(_current, scope)) {
      return false;
    }
    final expectedRuntime = scope._runtimeScope;
    if (expectedRuntime == null) {
      if (currentRuntimeScope != null) {
        scope._runtimeScope = currentRuntimeScope;
      }
      return true;
    }
    if (currentRuntimeScope == null) {
      return allowDetachedRuntime;
    }
    return expectedRuntime == currentRuntimeScope;
  }

  /// 仅当前代数的 listener 退出时才清空 Gate。
  bool release(AgentProviderEventListenerScope scope) {
    if (!identical(_current, scope)) {
      return false;
    }
    _current = null;
    return true;
  }
}

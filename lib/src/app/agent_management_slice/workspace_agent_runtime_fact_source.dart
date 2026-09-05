import 'dart:async';
import 'dart:collection';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_runtime_facts.dart';

/// Shell 拥有的 session 事实源。只观察现存 Binding，不创建/释放 runtime 或租约。
final class WorkspaceAgentRuntimeFactSource
    implements AgentManagementRuntimeFactSource {
  WorkspaceAgentRuntimeFactSource(this.workspace);

  final AgentConversationWorkspaceStore workspace;
  final _handles = Map<AgentConversationBinding, _ObservationHandle>.identity();
  final _listeners = <void Function(AgentManagementRuntimeFacts)>[];
  AgentManagementRuntimeFacts _current = AgentManagementRuntimeFacts.empty;
  bool _started = false;
  bool _closed = false;
  bool _reconciling = false;
  bool _reconcileAgain = false;
  int _generation = 0;

  @override
  AgentManagementRuntimeFacts get current => _current;

  void start() {
    if (_closed) throw StateError('Runtime fact source is closed');
    if (_started) return;
    _started = true;
    workspace.bindingManager.addListener(_reconcile);
    workspace.addListener(_reconcile);
    try {
      _reconcile();
    } catch (_) {
      close();
      rethrow;
    }
  }

  @override
  void Function() subscribe(
    void Function(AgentManagementRuntimeFacts) receive,
  ) {
    if (_closed) throw StateError('Runtime fact source is closed');
    // 每次订阅都有独立身份，重复订阅同一个函数也能精确退订。
    void listener(AgentManagementRuntimeFacts facts) => receive(facts);
    _listeners.add(listener);
    return () => _listeners.remove(listener);
  }

  void _reconcile() {
    if (_closed) return;
    if (_reconciling) {
      _reconcileAgain = true;
      return;
    }
    _reconciling = true;
    try {
      do {
        _reconcileAgain = false;
        final bindings = HashSet<AgentConversationBinding>.identity()
          ..addAll(workspace.bindingManager.bindings.values);
        final controllers =
            Map<
              AgentConversationBinding,
              AgentConversationRuntimeController
            >.identity();
        for (final entry in workspace.entries) {
          final previous = controllers[entry.binding];
          if (entry.providerId != entry.binding.providerId ||
              !identical(entry.controller.conversationBinding, entry.binding) ||
              (previous != null && !identical(previous, entry.controller))) {
            throw StateError(
              'Mismatched conversation runtime observation owner',
            );
          }
          controllers[entry.binding] = entry.controller;
        }
        for (final binding in _handles.keys.toList()) {
          if (!bindings.contains(binding)) _handles.remove(binding)!.detach();
        }
        for (final binding in bindings) {
          final handle = _handles.putIfAbsent(binding, () {
            final created = _ObservationHandle(binding);
            final generation = _generation;
            void changed() {
              if (!_closed &&
                  generation == _generation &&
                  identical(_handles[binding], created)) {
                _reconcile();
              }
            }

            created.bindingChanged = changed;
            binding.addListener(changed);
            return created;
          });
          final controller = controllers[binding];
          if (!identical(handle.controller, controller)) {
            handle.detachController();
            handle.controller = controller;
            if (controller != null) {
              final generation = _generation;
              final subscription = handle.subscriptionGeneration;
              void changed() {
                if (!_closed &&
                    generation == _generation &&
                    identical(_handles[binding], handle) &&
                    subscription == handle.subscriptionGeneration &&
                    identical(handle.controller, controller)) {
                  _reconcile();
                }
              }

              handle.controllerChanged = changed;
              controller.runtimeObservationListenable.addListener(changed);
            }
          }
          if (controller == null && handle.events == null) {
            // 仅 retained Binding 缺少 controller 时观察事件通知，内容完全不读。
            // 正常 entry 只在 controller 的安全发布边界重算，不沿 token 流逐条扫描。
            final generation = _generation;
            final subscription = handle.subscriptionGeneration;
            void changed() {
              if (!_closed &&
                  generation == _generation &&
                  identical(_handles[binding], handle) &&
                  handle.controller == null &&
                  subscription == handle.subscriptionGeneration) {
                _reconcile();
              }
            }

            handle.events = binding.events.listen(
              (_) => changed(),
              onError: (Object _, StackTrace _) => changed(),
            );
          } else if (controller != null && handle.events != null) {
            unawaited(handle.events!.cancel());
            handle.events = null;
          }
        }
        final facts = AgentManagementRuntimeFacts(_handles.values.map(_read));
        if (facts != _current) {
          _current = facts;
          for (final listener in List.of(_listeners)) {
            if (_closed) break;
            if (_listeners.contains(listener)) listener(facts);
          }
        }
      } while (_reconcileAgain && !_closed);
    } finally {
      _reconciling = false;
    }
  }

  AgentManagementRuntimeFact _read(_ObservationHandle handle) {
    final binding = handle.binding;
    final lifecycle = binding.runtimeLifecycle.phase;
    final runtime = binding.currentRuntime;
    final controller = handle.controller;
    final observation = controller?.runtimeObservationListenable.value;
    final sameOwner =
        observation != null &&
        observation.bindingKey.providerId == binding.providerId &&
        observation.attemptEpoch == controller!.runtimeObservationAttemptEpoch;
    final sameRuntime =
        sameOwner &&
        runtime != null &&
        observation.runtimeIdentity == runtime.runtimeIdentity &&
        observation.connectionScope == runtime.runtimeScope;
    final attached =
        lifecycle == AgentConversationRuntimeLifecyclePhase.attached &&
        runtime != null;
    final connection = sameRuntime
        ? observation.connectionState
        : _connection(runtime?.bundle.runtime.lifecycleState);
    final startup =
        sameOwner &&
        observation.attemptEpoch > 0 &&
        runtime == null &&
        lifecycle == AgentConversationRuntimeLifecyclePhase.dormant &&
        observation.lifecycle == AgentConversationRuntimeLifecyclePhase.dormant;
    final active =
        attached &&
        sameRuntime &&
        (observation.isTurnRunning ||
            observation.waitingOnApproval ||
            observation.waitingOnUserInput);
    return AgentManagementRuntimeFact(
      observationKey: handle.key,
      providerId: binding.providerId,
      runtimeIdentity: runtime?.runtimeIdentity,
      connectionScope: runtime?.runtimeScope,
      lifecycle: lifecycle,
      connectionState: startup ? observation.connectionState : connection,
      hasCurrentThreadObservation: attached && sameRuntime,
      connected:
          attached &&
          runtime.bundle.runtime.lifecycleState ==
              AgentProviderLifecycleState.ready &&
          (controller == null ||
              connection == AgentProviderConnectionState.ready ||
              connection == AgentProviderConnectionState.running),
      activeTurn: active,
      waitingOnApproval: active && observation.waitingOnApproval,
      waitingOnUserInput: active && observation.waitingOnUserInput,
      currentError:
          ((startup || sameRuntime) &&
              observation.connectionState ==
                  AgentProviderConnectionState.error) ||
          (attached &&
              runtime.bundle.runtime.lifecycleState ==
                  AgentProviderLifecycleState.failed),
      unavailable:
          (startup &&
              observation.connectionState ==
                  AgentProviderConnectionState.unavailable) ||
          connection == AgentProviderConnectionState.unavailable,
    );
  }

  void close() {
    if (_closed) return;
    _closed = true;
    _generation++;
    workspace.bindingManager.removeListener(_reconcile);
    workspace.removeListener(_reconcile);
    for (final handle in _handles.values) {
      handle.detach();
    }
    _handles.clear();
    _listeners.clear();
  }
}

AgentProviderConnectionState? _connection(
  AgentProviderLifecycleState? lifecycle,
) => switch (lifecycle) {
  AgentProviderLifecycleState.starting ||
  AgentProviderLifecycleState.initializing =>
    AgentProviderConnectionState.connecting,
  AgentProviderLifecycleState.ready => AgentProviderConnectionState.ready,
  AgentProviderLifecycleState.failed => AgentProviderConnectionState.error,
  _ => null,
};

final class _ObservationHandle {
  _ObservationHandle(this.binding);
  final AgentConversationBinding binding;
  final Object key = Object();
  AgentConversationRuntimeController? controller;
  void Function()? controllerChanged;
  late final void Function() bindingChanged;
  StreamSubscription<AgentEvent>? events;
  int subscriptionGeneration = 0;

  void detachController() {
    subscriptionGeneration++;
    final listener = controllerChanged;
    if (listener != null) {
      controller?.runtimeObservationListenable.removeListener(listener);
    }
    controllerChanged = null;
    controller = null;
  }

  void detach() {
    detachController();
    binding.removeListener(bindingChanged);
    unawaited(events?.cancel());
  }
}

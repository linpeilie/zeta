import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 一个 Binding 对应的切片 store 与 runtime。
///
/// [controller] 在只测切片镜像、没有 runtime 的容器里可以为空；生产装配与
/// AgentPane 命令面必须带上。
final class AgentConversationSessionHandle {
  const AgentConversationSessionHandle({required this.store, this.controller});

  final AgentConversationSliceStore store;
  final AgentConversationRuntimeController? controller;
}

typedef AgentConversationSliceStoreResolver =
    AgentConversationSessionHandle Function(AgentConversationBindingKey key);

/// 组合根持有的 Conversation Slice 注册表。
///
/// Workspace 在 `IdeHome.initState` 创建后同步绑定；首个 Conversation widget
/// build 之前注册表已就绪，因此不需要可变 Riverpod provider 或首帧旧路径。
final class AgentConversationSliceStoreRegistry {
  AgentConversationSliceStoreResolver? _resolver;

  void bind(AgentConversationSliceStoreResolver resolver) {
    if (_resolver != null && !identical(_resolver, resolver)) {
      throw StateError('Conversation slice store registry is already bound');
    }
    _resolver = resolver;
  }

  void unbind() {
    _resolver = null;
  }

  AgentConversationSessionHandle resolve(AgentConversationBindingKey key) {
    final resolver = _resolver;
    if (resolver == null) {
      throw StateError(
        'Conversation slice store registry was read before workspace binding',
      );
    }
    return resolver(key);
  }
}

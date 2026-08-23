import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

typedef AgentConversationSliceStoreResolver =
    AgentConversationSliceStore Function(AgentConversationBindingKey key);

/// 组合根持有的 Conversation Slice store 注册表。
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

  AgentConversationSliceStore resolve(AgentConversationBindingKey key) {
    final resolver = _resolver;
    if (resolver == null) {
      throw StateError(
        'Conversation slice store registry was read before workspace binding',
      );
    }
    return resolver(key);
  }
}

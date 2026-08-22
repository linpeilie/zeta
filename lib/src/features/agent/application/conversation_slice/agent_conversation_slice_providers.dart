import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_ui_state.dart';

/// Phase 2 切片是否启用。
///
/// **按 workspace entry 生效**：组合根在被选中的那个 conversation 子树上覆盖
/// 这个 Provider，其余 entry 仍走旧 ViewModel 直连路径。回退颗粒因此是"一个
/// 会话"，而不是整个应用。
final agentConversationSliceEnabledProvider = Provider<bool>(
  (ref) => false,
  name: 'agentConversationSliceEnabled',
);

/// 当前子树的切片 store。
///
/// 没有覆盖就是**编译期就该发现的接线错误**，因此直接抛错而不是给个空实现：
/// 静默降级会让"切片没生效"变成线上才发现的问题。
final agentConversationSliceStoreProvider =
    Provider<AgentConversationSliceStore>(
      (ref) => throw StateError(
        'agentConversationSliceStoreProvider must be overridden by the '
        'conversation subtree before it is read.',
      ),
      name: 'agentConversationSliceStore',
    );

/// 切片状态。
///
/// 订阅 store 的变化并转成 Riverpod 状态，这样 UI 可以用
/// `ref.watch(provider.select(...))` 做**字段级** selector，避免整棵子树重建。
final agentConversationSliceProvider =
    NotifierProvider<
      AgentConversationSliceNotifier,
      AgentConversationSliceState
    >(AgentConversationSliceNotifier.new, name: 'agentConversationSlice');

/// 把 [AgentConversationSliceStore] 桥接到 Riverpod。
///
/// 它**不拥有状态**：store 才是 source of truth，这里只是镜像 + 提供 selector
/// 入口，避免出现第二个 owner。
final class AgentConversationSliceNotifier
    extends Notifier<AgentConversationSliceState> {
  @override
  AgentConversationSliceState build() {
    final store = ref.watch(agentConversationSliceStoreProvider);
    void listener() => state = store.state;
    store.addListener(listener);
    ref.onDispose(() {
      // store 的生命周期跟随 workspace entry 的 binding lease，不由 Riverpod
      // 释放；这里只摘掉自己的监听。
      if (!store.isClosed) {
        store.removeListener(listener);
      }
    });
    return store.state;
  }
}

// ---------------------------------------------------------------------------
// selector：只暴露 region 粒度，避免 UI 直接依赖整个切片
// ---------------------------------------------------------------------------

/// 头栏 selector。
final agentConversationHeaderProvider = Provider<AgentHeaderState>(
  (ref) =>
      ref.watch(agentConversationSliceProvider.select((state) => state.header)),
  name: 'agentConversationHeader',
);

/// Composer selector。
final agentConversationComposerProvider = Provider<AgentComposerState>(
  (ref) => ref.watch(
    agentConversationSliceProvider.select((state) => state.composer),
  ),
  name: 'agentConversationComposer',
);

/// 待处理交互 selector（四种语义仍在各自字段里，不合并）。
final agentConversationPendingInteractionProvider =
    Provider<AgentPendingInteractionState>(
      (ref) => ref.watch(
        agentConversationSliceProvider.select(
          (state) => state.pendingInteractions,
        ),
      ),
      name: 'agentConversationPendingInteraction',
    );

/// 展开态 selector。
final agentConversationExpansionProvider = Provider<AgentExpansionState>(
  (ref) => ref.watch(
    agentConversationSliceProvider.select((state) => state.expansion),
  ),
  name: 'agentConversationExpansion',
);

/// 历史时间线 selector。
final agentConversationHistoryProvider =
    Provider<AgentConversationHistoryState>(
      (ref) => ref.watch(
        agentConversationSliceProvider.select((state) => state.history),
      ),
      name: 'agentConversationHistory',
    );

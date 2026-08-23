/// Riverpod adapter 层：把 application 的切片 store 接到 UI。
///
/// 目标架构 §6.2 把「Riverpod adapter」单列成一层，并要求
/// **使用 `family` 按 `BindingKey` 隔离实例**。因此这里全部是按
/// [AgentConversationBindingKey] 分键的 family——隔离靠 key，不靠嵌套
/// `ProviderScope`。
///
/// 为什么不用「子树 override」：实测（flutter_riverpod 3.4.2）嵌套 `ProviderScope`
/// 覆盖依赖**不会**让已有 family 重新解析——补 `dependencies:` 也不行。同一个应用
/// 容器里开两个 workspace entry 时，第二个会读到第一个的会话状态。因此隔离靠 key，
/// 不靠 scope；store 的来源是根级注入的 resolver。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store_registry.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 组合根注入的同步 store 注册表。
final agentConversationSliceStoreRegistryProvider =
    Provider<AgentConversationSliceStoreRegistry>(
      (ref) => throw StateError(
        'agentConversationSliceStoreRegistryProvider must be overridden',
      ),
      name: 'agentConversationSliceStoreRegistry',
    );

/// 指定会话的切片 store。
///
/// 未注册身份直接抛错，禁止静默降级到旧 ViewModel 监听路径。
final agentConversationSliceStoreProvider =
    Provider.family<AgentConversationSliceStore, AgentConversationBindingKey>((
      ref,
      key,
    ) {
      return ref
          .watch(agentConversationSliceStoreRegistryProvider)
          .resolve(key);
    }, name: 'agentConversationSliceStore');

/// 指定会话的切片状态。
///
/// `autoDispose`：这些 provider 是**纯 UI 镜像**，释放它们只是摘掉监听，不碰
/// Binding lease、CLI runtime 或 store 本身（§12.11 禁止的是用 autoDispose 决定
/// 那些东西的生命周期）。
final agentConversationSliceProvider =
    NotifierProvider.family<
      AgentConversationSliceNotifier,
      AgentConversationSliceState,
      AgentConversationBindingKey
    >(
      AgentConversationSliceNotifier.new,
      name: 'agentConversationSlice',
      isAutoDispose: true,
    );

/// 把 [AgentConversationSliceStore] 桥接到 Riverpod。
///
/// 它**不拥有状态**：store 才是 source of truth，这里只是镜像 + 提供 selector
/// 入口，避免出现第二个 owner。
final class AgentConversationSliceNotifier
    extends Notifier<AgentConversationSliceState> {
  AgentConversationSliceNotifier(this.key);

  /// 本 notifier 服务的会话身份。
  final AgentConversationBindingKey key;

  @override
  AgentConversationSliceState build() {
    final store = ref.watch(agentConversationSliceStoreProvider(key));
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
final agentConversationHeaderProvider =
    Provider.family<AgentHeaderState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.header),
      ),
      name: 'agentConversationHeader',
      isAutoDispose: true,
    );

/// Composer selector。
final agentConversationComposerProvider =
    Provider.family<AgentComposerState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.composer),
      ),
      name: 'agentConversationComposer',
      isAutoDispose: true,
    );

/// 待处理交互 selector（四种语义仍在各自字段里，不合并）。
final agentConversationPendingInteractionProvider =
    Provider.family<AgentPendingInteractionState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(
          key,
        ).select((state) => state.pendingInteractions),
      ),
      name: 'agentConversationPendingInteraction',
      isAutoDispose: true,
    );

/// 展开态 selector。
final agentConversationExpansionProvider =
    Provider.family<AgentExpansionState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.expansion),
      ),
      name: 'agentConversationExpansion',
      isAutoDispose: true,
    );

/// 历史时间线 selector。
final agentConversationHistoryProvider =
    Provider.family<AgentConversationHistoryState, AgentConversationBindingKey>(
      (ref, key) => ref.watch(
        agentConversationSliceProvider(key).select((state) => state.history),
      ),
      name: 'agentConversationHistory',
      isAutoDispose: true,
    );

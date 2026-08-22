/// Riverpod adapter 层：把 application 的切片 store 接到 UI。
///
/// 目标架构 §6.2 把「Riverpod adapter」单列成一层，并要求
/// **使用 `family` 按 `BindingKey` 隔离实例**。因此这里全部是按
/// [AgentConversationBindingKey] 分键的 family——隔离靠 key，不靠嵌套
/// `ProviderScope`。
///
/// 为什么不用「子树 override」：不带 `dependencies` 的 provider 会在**根容器**
/// 解析，嵌套 scope 里覆盖依赖对它无效。同一个应用容器里开两个 workspace entry
/// 时，第二个会读到第一个的会话状态。family 让隔离是结构性的，不依赖谁记得声明
/// `dependencies`。
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 把 Binding 身份解析成该会话的切片 store。
///
/// 由 app / workspace 组合层在建容器时注入（`overrideWithValue`）。返回 null 表示
/// 这个 entry 没有启用切片，仍走旧 ViewModel 直连路径。
typedef AgentConversationSliceStoreResolver =
    AgentConversationSliceStore? Function(AgentConversationBindingKey key);

/// 默认解析器：任何 key 都没有 store。
///
/// 也就是**默认整个应用都不启用切片**，由组合层显式为某个 entry 打开。
final agentConversationSliceStoreResolverProvider =
    Provider<AgentConversationSliceStoreResolver>(
      (ref) =>
          (_) => null,
      name: 'agentConversationSliceStoreResolver',
    );

/// 该 entry 是否启用 Phase 2 切片。
///
/// **按 workspace entry 生效**：判据就是组合层有没有为这个 key 建 store，
/// 不再单独维护一个开关，省掉两处状态对不齐的可能。
final agentConversationSliceEnabledProvider =
    Provider.family<bool, AgentConversationBindingKey>(
      (ref, key) =>
          ref.watch(agentConversationSliceStoreResolverProvider)(key) != null,
      name: 'agentConversationSliceEnabled',
    );

/// 指定会话的切片 store。
///
/// 没有解析到就**直接抛错**：静默降级会让"切片没生效"变成线上才发现的问题。
/// 调用方应先看 [agentConversationSliceEnabledProvider]。
final agentConversationSliceStoreProvider =
    Provider.family<AgentConversationSliceStore, AgentConversationBindingKey>((
      ref,
      key,
    ) {
      final store = ref.watch(agentConversationSliceStoreResolverProvider)(key);
      if (store == null) {
        throw StateError(
          'No conversation slice store registered for $key. '
          'The composition root must override '
          'agentConversationSliceStoreResolverProvider for this entry.',
        );
      }
      return store;
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

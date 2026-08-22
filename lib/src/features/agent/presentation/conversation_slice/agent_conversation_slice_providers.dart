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
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_store.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 把 Binding 身份解析成该会话的切片 store。
///
/// 由 app / workspace 组合层在建容器时注入（`overrideWithValue`）。返回 null 表示
/// 这个 entry 没有启用切片，仍走旧 ViewModel 直连路径。
typedef AgentConversationSliceStoreResolver =
    AgentConversationSliceStore? Function(AgentConversationBindingKey key);

/// store 解析器。
///
/// **是 `NotifierProvider` 而不是 `Provider`**：解析器的值在运行期确实会变——
/// 根 scope 在 `MainApp` 建立，而 workspace controller 要等 `IdeHome` 才存在，
/// 组合根必须在之后把真正的解析函数 bind 进来。用不可变 `Provider` 建模会让
/// 依赖它的 family **缓存住"尚未就绪"时的否定答案**：某个会话一旦在 bind 之前
/// 被读过一次，就会永久停在旧路径，而且不报任何错。
final agentConversationSliceStoreResolverProvider =
    NotifierProvider<
      AgentConversationSliceStoreResolverNotifier,
      AgentConversationSliceStoreResolver
    >(
      AgentConversationSliceStoreResolverNotifier.new,
      name: 'agentConversationSliceStoreResolver',
    );

/// 持有 store 解析器；由组合根在 controller 就绪后 [bind]。
final class AgentConversationSliceStoreResolverNotifier
    extends Notifier<AgentConversationSliceStoreResolver> {
  AgentConversationSliceStoreResolverNotifier([this._initial]);

  final AgentConversationSliceStoreResolver? _initial;

  /// 默认：任何 key 都没有 store，也就是**默认整个应用不启用切片**。
  @override
  AgentConversationSliceStoreResolver build() => _initial ?? (_) => null;

  /// 组合根在 workspace controller 就绪后调用。
  ///
  /// 写 `state` 会让依赖它的 family 失效重算，因此 bind 之前读到的否定答案
  /// 不会被永久缓存。
  void bind(AgentConversationSliceStoreResolver resolver) => state = resolver;
}

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

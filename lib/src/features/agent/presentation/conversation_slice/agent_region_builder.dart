import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/conversation_slice/agent_conversation_slice_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 订阅一个 conversation region 的**唯一接缝**。
///
/// 切片为这个 workspace entry 启用时走 Riverpod selector；否则回退到 ViewModel
/// 的 `ValueListenable`。两条路径给出的是**同一批不可变 region 对象**——切片只是
/// 它们的只读投影，所以切换不改变渲染结果，只改变订阅机制。
///
/// 回退颗粒因此是"一个会话"：某个 entry 出问题，只把它的 store 撤掉即可，
/// 不影响别的 entry，也不需要重启应用（Phase 2 §9 的 feature flag 决定）。
class AgentRegionBuilder<T> extends ConsumerWidget {
  const AgentRegionBuilder({
    required this.viewModel,
    required this.selector,
    required this.legacyListenable,
    required this.builder,
    super.key,
  });

  /// 本会话的 ViewModel；同时提供 Binding 身份与回退用的 listenable。
  final AgentConversationViewModel viewModel;

  /// 切片路径：按 Binding 身份取该 region 的 selector。
  final Provider<T> Function(AgentConversationBindingKey key) selector;

  /// 回退路径：ViewModel 的 region listenable。
  final ValueListenable<T> legacyListenable;

  final Widget Function(BuildContext context, T state) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final key = viewModel.conversationBinding.key;
    if (ref.watch(agentConversationSliceEnabledProvider(key))) {
      return builder(context, ref.watch(selector(key)));
    }
    return ValueListenableBuilder<T>(
      valueListenable: legacyListenable,
      builder: (context, state, _) => builder(context, state),
    );
  }
}

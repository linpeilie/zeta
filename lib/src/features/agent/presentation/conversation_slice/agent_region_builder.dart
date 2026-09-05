import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 订阅一个 conversation region 的**唯一接缝**。
///
/// 所有 region 只经按 BindingKey 隔离的 Riverpod selector 读取；不存在旧
/// ValueListenable 回退，因此 UI 不会在同一事实之上形成第二条订阅路径。
class AgentRegionBuilder<T> extends ConsumerWidget {
  const AgentRegionBuilder({
    required this.bindingKey,
    required this.selector,
    required this.builder,
    super.key,
  });

  /// 本会话的冻结 Binding 身份。
  final AgentConversationBindingKey bindingKey;

  /// 切片路径：按 Binding 身份取该 region 的 selector。
  final Provider<T> Function(AgentConversationBindingKey key) selector;

  final Widget Function(BuildContext context, T state) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return builder(context, ref.watch(selector(bindingKey)));
  }
}

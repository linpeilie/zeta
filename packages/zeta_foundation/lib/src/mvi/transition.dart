/// 一次同步状态转移的结果：下一个状态 + 待执行的类型化副作用。
///
/// 这是 MVI 切片之间**唯一**共享的结构。它刻意不提供 `BaseStore`、
/// `BaseReducer` 之类的通用基类：审批、提问、Plan、文件树和设置的领域类型
/// 差异很大，强行统一只会造出一层空壳。
///
/// 约定：
///
/// - reducer 必须是纯同步函数 `Transition<S, E> reduce(S state, I intent)`；
/// - [effects] 只是**描述**，执行由 scope-aware 的 effect runner 负责；
/// - 不产生副作用时用 [Transition.stateOnly]，状态没变时用 [Transition.none]。
final class Transition<S, E> {
  Transition(this.state, Iterable<E> effects)
    : effects = List<E>.unmodifiable(effects);

  /// 只更新状态，不产生副作用。
  Transition.stateOnly(this.state) : effects = const [];

  /// 状态不变，也不产生副作用。
  Transition.none(this.state) : effects = const [];

  /// 转移之后的状态。
  final S state;

  /// 本次转移描述的副作用，按声明顺序执行。
  final List<E> effects;

  /// 是否携带副作用。
  bool get hasEffects => effects.isNotEmpty;

  /// 在保持状态不变的前提下追加副作用。
  Transition<S, E> withEffects(Iterable<E> extra) =>
      Transition<S, E>(state, <E>[...effects, ...extra]);

  @override
  String toString() =>
      'Transition(${state.runtimeType}, effects: ${effects.length})';
}

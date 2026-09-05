/// 异步操作的稳定身份。
///
/// 迟到结果必须能被判定为"属于哪一次操作"。[OperationId] 只承载一个稳定的
/// 作用域标签和进程内单调序号：**不含 thread id、文件路径、prompt 或任何
/// 用户内容**，因此可以安全地进入日志与指标。
///
/// 典型用法：发起请求时生成 id 并存进 state；结果返回时先比对 id，再决定
/// 是否写回。
final class OperationId {
  const OperationId({required this.scope, required this.sequence});

  /// 操作所属的稳定作用域标签，例如 `conversation.send`、`threads.load`。
  ///
  /// 只允许写死在代码里的常量，不允许拼入运行期数据。
  final String scope;

  /// 同一 [OperationIdGenerator] 内单调递增的序号。
  final int sequence;

  @override
  bool operator ==(Object other) =>
      other is OperationId &&
      other.scope == scope &&
      other.sequence == sequence;

  @override
  int get hashCode => Object.hash(scope, sequence);

  @override
  String toString() => '$scope#$sequence';
}

/// 单调递增的 [OperationId] 生成器。
///
/// 每个 store / controller 实例持有自己的生成器；序号不跨实例复用，避免两个
/// 切片产生看起来相同的 id。
final class OperationIdGenerator {
  OperationIdGenerator({required this.scope});

  /// 该生成器产出的所有 id 共享的作用域标签。
  final String scope;

  int _sequence = 0;

  /// 已产出的 id 数量。
  int get issuedCount => _sequence;

  /// 生成下一个 id。
  OperationId next() => OperationId(scope: scope, sequence: ++_sequence);

  /// 判断 [candidate] 是否仍是本生成器最近一次产出的 id。
  ///
  /// 这是"只接受最新一次请求结果"的最小判据；需要并发多请求时，调用方应改为
  /// 显式保存自己关心的 id 集合。
  bool isCurrent(OperationId? candidate) =>
      candidate != null &&
      candidate.scope == scope &&
      candidate.sequence == _sequence;
}

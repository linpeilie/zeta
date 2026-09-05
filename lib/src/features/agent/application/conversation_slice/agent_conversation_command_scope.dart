import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 一条命令**发起时**的作用域快照。
///
/// `OperationId` 只能回答"是不是同一次操作"，回答不了"这次操作所属的世界还在不
/// 在"。Provider 进程重启、runtime 换代、Binding 重挂之后，旧命令的结果不该被当
/// 成当前世界的结果写回（目标架构 §6.2：迟到结果提交前必须校验 operation ID、
/// Binding、runtime identity/generation **和** disposed 状态）。
///
/// 纯 Dart：application 层不得 import Flutter。
final class AgentConversationCommandScope {
  const AgentConversationCommandScope({
    required this.bindingKey,
    this.runtimeId,
    this.connectionEpoch,
    this.listenerGeneration,
    this.threadId,
  });

  /// 从内核的 effect scope 拍快照。
  ///
  /// [scope] 为 null 表示发起时还没有绑定 runtime（例如草稿会话的第一条消息），
  /// 这不是错误：此时只锁定 Binding 身份，等命令自己把 runtime 建起来。
  factory AgentConversationCommandScope.fromEffectScope({
    required AgentConversationBindingKey bindingKey,
    required AgentConversationEffectScope? scope,
  }) {
    if (scope == null) {
      return AgentConversationCommandScope(bindingKey: bindingKey);
    }
    return AgentConversationCommandScope(
      bindingKey: bindingKey,
      runtimeId: scope.runtimeId,
      connectionEpoch: scope.connectionEpoch,
      listenerGeneration: scope.listenerGeneration,
      threadId: scope.threadId,
    );
  }

  /// 会话身份。跨 entry 的结果一律不接受。
  final AgentConversationBindingKey bindingKey;

  /// 发起时绑定的 runtime；尚未绑定为 null。
  final String? runtimeId;

  /// runtime 的连接代数。
  final int? connectionEpoch;

  /// 事件监听代数。
  final int? listenerGeneration;

  /// 发起时的 thread；草稿会话为 null。
  final String? threadId;

  /// 是否还没绑定 runtime。
  bool get isUnbound => runtimeId == null;

  /// **执行前**校验：世界必须与发起时完全一致。
  ///
  /// 此时命令还没开始跑，listener 代数没有理由变化，因此一并比对。
  bool matchesForExecution(AgentConversationCommandScope current) {
    if (!_matchesIdentity(current)) {
      return false;
    }
    if (isUnbound) {
      return true;
    }
    return listenerGeneration == current.listenerGeneration;
  }

  /// **结果回写前**校验：只比对世界的身份，不比对 listener 代数。
  ///
  /// 命令自己就可能建立或重挂 listener（草稿首发会创建 session、空闲后重连会
  /// 重新订阅），把代数变化算成失效会把正常流程判成 staleTarget。真正意味着
  /// "换了个世界"的是 Binding 与 runtime identity/epoch。
  bool matchesForCommit(AgentConversationCommandScope current) =>
      _matchesIdentity(current);

  bool _matchesIdentity(AgentConversationCommandScope current) {
    if (!_matchesBinding(current.bindingKey)) {
      return false;
    }
    // 只有**两边都指名了 runtime** 才比较：
    // - 发起时没有 runtime（草稿首发）：命令的职责之一就是把它建起来；
    // - 当前没有 runtime（失败后被拆掉）：那是"现在没有世界"，不是"换了个
    //   世界"，不能因此把命令自己造成的失败改判成 staleTarget。
    if (!isUnbound && !current.isUnbound) {
      if (runtimeId != current.runtimeId ||
          connectionEpoch != current.connectionEpoch) {
        return false;
      }
    }
    // thread 同理：草稿发起时没有 thread，命令会创建它。
    if (threadId != null &&
        current.threadId != null &&
        threadId != current.threadId) {
      return false;
    }
    return true;
  }

  /// draft → thread 是**同一个 Binding 的一次性晋升**（`promoteToThread`），
  /// 不是换了个会话：草稿会话发出第一条消息时必然发生。内核禁止 thread key 再被
  /// 改绑，所以这是唯一一种合法的 key 迁移，其余一律视为换了世界。
  bool _matchesBinding(AgentConversationBindingKey current) {
    if (bindingKey == current) {
      return true;
    }
    final snapshot = bindingKey;
    return snapshot is AgentConversationDraftBindingKey &&
        current is AgentConversationThreadBindingKey &&
        snapshot.providerId == current.providerId;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentConversationCommandScope &&
      other.bindingKey == bindingKey &&
      other.runtimeId == runtimeId &&
      other.connectionEpoch == connectionEpoch &&
      other.listenerGeneration == listenerGeneration &&
      other.threadId == threadId;

  @override
  int get hashCode => Object.hash(
    bindingKey,
    runtimeId,
    connectionEpoch,
    listenerGeneration,
    threadId,
  );

  @override
  String toString() =>
      'AgentConversationCommandScope($bindingKey, runtime=$runtimeId, '
      'epoch=$connectionEpoch, generation=$listenerGeneration, '
      'thread=$threadId)';
}

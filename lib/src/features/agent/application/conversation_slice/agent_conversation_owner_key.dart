import 'package:meta/meta.dart';

/// 仅在内存中使用的 entry 生命周期身份；草稿晋升不改变此值。
@immutable
final class AgentConversationOwnerKey {
  AgentConversationOwnerKey(this.entryId) : lifetimeToken = Object();
  final String entryId;
  final Object lifetimeToken;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationOwnerKey &&
      other.entryId == entryId &&
      identical(other.lifetimeToken, lifetimeToken);
  @override
  int get hashCode => Object.hash(entryId, identityHashCode(lifetimeToken));
}

sealed class AgentConversationOwnerResolution {
  const AgentConversationOwnerResolution();
}

final class AgentConversationOwnerLive
    extends AgentConversationOwnerResolution {
  const AgentConversationOwnerLive(this.ownerKey);
  final AgentConversationOwnerKey ownerKey;
}

final class AgentConversationOwnerClosing
    extends AgentConversationOwnerResolution {
  const AgentConversationOwnerClosing(this.ownerKey);
  final AgentConversationOwnerKey ownerKey;
}

final class AgentConversationOwnerClosed
    extends AgentConversationOwnerResolution {
  const AgentConversationOwnerClosed(this.ownerKey);
  final AgentConversationOwnerKey ownerKey;
}

final class AgentConversationOwnerUnknown
    extends AgentConversationOwnerResolution {
  const AgentConversationOwnerUnknown();
}

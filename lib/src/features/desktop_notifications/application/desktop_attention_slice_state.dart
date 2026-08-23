import 'package:meta/meta.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 一条进程内未读提醒。
@immutable
final class DesktopUnreadAttention {
  const DesktopUnreadAttention({
    required this.attention,
    required this.notificationId,
  });

  final AgentWorkspaceAttention attention;
  final int notificationId;
}

/// Desktop Attention 切片的不可变状态。
///
/// 未读只存在于当前进程，不参与持久化。根状态快照只投影计数和可见性，完整项目
/// 路径不会离开本 feature 的 runner。
@immutable
final class DesktopAttentionSliceState {
  DesktopAttentionSliceState({
    this.initialized = false,
    this.settings = const AgentNotificationSettings(),
    this.visibility = const DesktopAttentionVisibility(),
    Map<String, DesktopUnreadAttention> unreadByIdentity =
        const <String, DesktopUnreadAttention>{},
    this.nextNotificationId = 1000,
  }) : unreadByIdentity = Map<String, DesktopUnreadAttention>.unmodifiable(
         unreadByIdentity,
       );

  final bool initialized;
  final AgentNotificationSettings settings;
  final DesktopAttentionVisibility visibility;
  final Map<String, DesktopUnreadAttention> unreadByIdentity;
  final int nextNotificationId;

  int get unreadCount => unreadByIdentity.length;

  DesktopAttentionSliceState copyWith({
    bool? initialized,
    AgentNotificationSettings? settings,
    DesktopAttentionVisibility? visibility,
    Map<String, DesktopUnreadAttention>? unreadByIdentity,
    int? nextNotificationId,
  }) {
    return DesktopAttentionSliceState(
      initialized: initialized ?? this.initialized,
      settings: settings ?? this.settings,
      visibility: visibility ?? this.visibility,
      unreadByIdentity: unreadByIdentity ?? this.unreadByIdentity,
      nextNotificationId: nextNotificationId ?? this.nextNotificationId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DesktopAttentionSliceState &&
        other.initialized == initialized &&
        other.settings == settings &&
        other.visibility == visibility &&
        zetaMapEquals(other.unreadByIdentity, unreadByIdentity) &&
        other.nextNotificationId == nextNotificationId;
  }

  @override
  int get hashCode => Object.hash(
    initialized,
    settings,
    visibility,
    Object.hashAllUnordered(unreadByIdentity.entries),
    nextNotificationId,
  );
}

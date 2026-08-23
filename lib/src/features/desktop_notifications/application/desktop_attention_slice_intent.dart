import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Desktop Attention 切片意图。
sealed class DesktopAttentionSliceIntent {
  const DesktopAttentionSliceIntent();
}

/// 通知端口和设置来源已经初始化。
final class DesktopAttentionInitialized extends DesktopAttentionSliceIntent {
  const DesktopAttentionInitialized(this.settings);

  final AgentNotificationSettings settings;
}

/// 通知设置发生变化。
final class DesktopAttentionSettingsChanged
    extends DesktopAttentionSliceIntent {
  const DesktopAttentionSettingsChanged(this.settings);

  final AgentNotificationSettings settings;
}

/// Workbench 可见上下文发生变化。
final class DesktopAttentionVisibilityChanged
    extends DesktopAttentionSliceIntent {
  const DesktopAttentionVisibilityChanged(this.visibility);

  final DesktopAttentionVisibility visibility;
}

/// 收到 Provider 中立的注意力信号。
final class DesktopAttentionReceived extends DesktopAttentionSliceIntent {
  const DesktopAttentionReceived(this.attention);

  final AgentWorkspaceAttention attention;
}

/// 用户已经查看指定 thread。
final class DesktopAttentionThreadRead extends DesktopAttentionSliceIntent {
  const DesktopAttentionThreadRead(this.providerId, this.threadId);

  final String providerId;
  final String threadId;
}

/// 删除一条无法再定位的陈旧提醒。
final class DesktopAttentionIdentityRemoved
    extends DesktopAttentionSliceIntent {
  const DesktopAttentionIdentityRemoved(this.identity);

  final String identity;
}

/// 操作系统通知被激活；payload 只交给 data codec 解码。
final class DesktopAttentionNotificationActivated
    extends DesktopAttentionSliceIntent {
  const DesktopAttentionNotificationActivated(this.payload);

  final String payload;
}

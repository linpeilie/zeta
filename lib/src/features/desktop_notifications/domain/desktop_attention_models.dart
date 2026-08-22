import 'package:zeta_agent_core/zeta_agent_core.dart';

typedef DesktopNotificationActivation = void Function(String? payload);

/// 系统通知展示请求。
final class DesktopNotificationRequest {
  const DesktopNotificationRequest({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String title;
  final String body;
  final String payload;
}

/// 系统通知端口，生产实现由桌面通知插件提供。
abstract interface class DesktopNotificationService {
  Future<String?> initialize({
    required DesktopNotificationActivation onActivate,
  });

  Future<bool?> requestPermissions();

  Future<void> show(DesktopNotificationRequest request);

  Future<void> cancel(int id);

  void dispose();
}

/// 任务栏、Dock 或窗口 urgency 提醒端口。
abstract interface class DesktopAttentionIndicator {
  Future<void> setUnreadCount(int count);

  Future<void> requestAttention();
}

/// 非桌面宿主和 Widget 测试使用的空系统通知实现。
final class NoopDesktopNotificationService
    implements DesktopNotificationService {
  const NoopDesktopNotificationService();

  @override
  Future<String?> initialize({
    required DesktopNotificationActivation onActivate,
  }) async => null;

  @override
  Future<bool?> requestPermissions() async => true;

  @override
  Future<void> show(DesktopNotificationRequest request) async {}

  @override
  Future<void> cancel(int id) async {}

  @override
  void dispose() {}
}

/// 非桌面宿主和 Widget 测试使用的空图标提醒实现。
final class NoopDesktopAttentionIndicator implements DesktopAttentionIndicator {
  const NoopDesktopAttentionIndicator();

  @override
  Future<void> requestAttention() async {}

  @override
  Future<void> setUnreadCount(int count) async {}
}

/// Shell 当前能够被用户直接看到的 Agent 上下文。
final class DesktopAttentionVisibility {
  const DesktopAttentionVisibility({
    this.windowFocused = false,
    this.agentCanvasVisible = false,
    this.providerId,
    this.threadId,
  });

  final bool windowFocused;
  final bool agentCanvasVisible;
  final String? providerId;
  final String? threadId;

  bool shows(AgentWorkspaceAttention attention) {
    return windowFocused &&
        agentCanvasVisible &&
        providerId == attention.providerId &&
        threadId == attention.threadId;
  }
}

typedef DesktopAttentionTargetActivator =
    Future<bool> Function(String providerId, String threadId);

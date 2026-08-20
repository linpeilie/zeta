import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:equatable/equatable.dart';
import 'package:settings_repository/settings_repository.dart';

export 'package:desktop_notifications_repository/desktop_notifications_repository.dart'
    show DesktopNotificationOperation;
export 'package:settings_repository/settings_repository.dart'
    show AgentNotificationSettings;

enum DesktopNotificationsStatus { initial, ready, failure }

final class DesktopNotificationsVisibility extends Equatable {
  const DesktopNotificationsVisibility({
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

  @override
  List<Object?> get props => <Object?>[
    windowFocused,
    agentCanvasVisible,
    providerId,
    threadId,
  ];
}

final class DesktopNotificationsActivation extends Equatable {
  const DesktopNotificationsActivation({
    required this.providerId,
    required this.threadId,
  });

  final String providerId;
  final String threadId;

  @override
  List<Object?> get props => <Object?>[providerId, threadId];
}

final class DesktopNotificationsState extends Equatable {
  const DesktopNotificationsState({
    this.status = DesktopNotificationsStatus.initial,
    this.notifications = const AgentNotificationSettings(),
    this.unread = const <String, AgentWorkspaceAttention>{},
    this.visibility = const DesktopNotificationsVisibility(),
    this.activation,
    this.failure,
  });

  final DesktopNotificationsStatus status;
  final AgentNotificationSettings notifications;
  final Map<String, AgentWorkspaceAttention> unread;
  final DesktopNotificationsVisibility visibility;
  final DesktopNotificationsActivation? activation;
  final DesktopNotificationOperation? failure;

  int get badgeCount => unread.length;

  DesktopNotificationsState copyWith({
    DesktopNotificationsStatus? status,
    AgentNotificationSettings? notifications,
    Map<String, AgentWorkspaceAttention>? unread,
    DesktopNotificationsVisibility? visibility,
    DesktopNotificationsActivation? activation,
    DesktopNotificationOperation? failure,
    bool clearActivation = false,
    bool clearFailure = false,
  }) {
    return DesktopNotificationsState(
      status: status ?? this.status,
      notifications: notifications ?? this.notifications,
      unread: unread ?? this.unread,
      visibility: visibility ?? this.visibility,
      activation: clearActivation ? null : (activation ?? this.activation),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    notifications,
    unread,
    visibility,
    activation,
    failure,
  ];
}

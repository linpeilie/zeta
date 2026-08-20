import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:equatable/equatable.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_state.dart';

sealed class DesktopNotificationsEvent extends Equatable {
  const DesktopNotificationsEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class DesktopNotificationsSubscriptionRequested
    extends DesktopNotificationsEvent {
  const DesktopNotificationsSubscriptionRequested();
}

final class DesktopNotificationsSettingsChanged
    extends DesktopNotificationsEvent {
  const DesktopNotificationsSettingsChanged(this.notifications);

  final AgentNotificationSettings notifications;

  @override
  List<Object?> get props => <Object?>[notifications];
}

final class DesktopNotificationsAttentionReceived
    extends DesktopNotificationsEvent {
  const DesktopNotificationsAttentionReceived(this.attention);

  final AgentWorkspaceAttention attention;

  @override
  List<Object?> get props => <Object?>[attention];
}

final class DesktopNotificationsVisibilityUpdated
    extends DesktopNotificationsEvent {
  const DesktopNotificationsVisibilityUpdated(this.visibility);

  final DesktopNotificationsVisibility visibility;

  @override
  List<Object?> get props => <Object?>[visibility];
}

final class DesktopNotificationsThreadMarkedRead
    extends DesktopNotificationsEvent {
  const DesktopNotificationsThreadMarkedRead({
    required this.providerId,
    required this.threadId,
  });

  final String providerId;
  final String threadId;

  @override
  List<Object?> get props => <Object?>[providerId, threadId];
}

final class DesktopNotificationsActivationRequested
    extends DesktopNotificationsEvent {
  const DesktopNotificationsActivationRequested({
    required this.providerId,
    required this.threadId,
  });

  final String providerId;
  final String threadId;

  @override
  List<Object?> get props => <Object?>[providerId, threadId];
}

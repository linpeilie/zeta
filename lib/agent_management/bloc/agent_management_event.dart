import 'package:equatable/equatable.dart';

sealed class AgentManagementEvent extends Equatable {
  const AgentManagementEvent();

  @override
  List<Object?> get props => const <Object?>[];
}

final class AgentManagementStarted extends AgentManagementEvent {
  const AgentManagementStarted({this.providerId});

  final String? providerId;

  @override
  List<Object?> get props => <Object?>[providerId];
}

final class AgentManagementAgentSelected extends AgentManagementEvent {
  const AgentManagementAgentSelected(this.providerId);

  final String providerId;

  @override
  List<Object?> get props => <Object?>[providerId];
}

final class AgentManagementDetectRequested extends AgentManagementEvent {
  const AgentManagementDetectRequested();
}

final class AgentManagementTestRequested extends AgentManagementEvent {
  const AgentManagementTestRequested();
}

final class AgentManagementConfigEdited extends AgentManagementEvent {
  const AgentManagementConfigEdited(this.contents);

  final String contents;

  @override
  List<Object?> get props => <Object?>[contents];
}

final class AgentManagementConfigSaveRequested extends AgentManagementEvent {
  const AgentManagementConfigSaveRequested();
}

final class AgentManagementLogsRequested extends AgentManagementEvent {
  const AgentManagementLogsRequested();
}

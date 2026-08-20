import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:equatable/equatable.dart';

export 'package:agent_management_repository/agent_management_repository.dart'
    show
        AgentConfigurationDocument,
        AgentConfigurationValidation,
        AgentConnectionTest,
        AgentDefinition,
        AgentDetection,
        AgentLogEntry,
        AgentManagementRepositoryFailure;

enum AgentManagementStatus { initial, loading, ready, failure }

final class AgentManagementState extends Equatable {
  const AgentManagementState({
    this.status = AgentManagementStatus.initial,
    this.definitions = const <AgentDefinition>[],
    this.selectedProviderId,
    this.detection,
    this.connectionTest,
    this.document,
    this.editorContents = '',
    this.validation = AgentConfigurationValidation.valid,
    this.logPaths = const <String>[],
    this.logs = const <AgentLogEntry>[],
    this.detecting = false,
    this.testing = false,
    this.saving = false,
    this.failure,
  });

  final AgentManagementStatus status;
  final List<AgentDefinition> definitions;
  final String? selectedProviderId;
  final AgentDetection? detection;
  final AgentConnectionTest? connectionTest;
  final AgentConfigurationDocument? document;
  final String editorContents;
  final AgentConfigurationValidation validation;
  final List<String> logPaths;
  final List<AgentLogEntry> logs;
  final bool detecting;
  final bool testing;
  final bool saving;
  final AgentManagementRepositoryFailure? failure;

  AgentDefinition? get selectedDefinition {
    final providerId = selectedProviderId;
    if (providerId == null) {
      return null;
    }
    return AgentDefinition.byProviderId(providerId);
  }

  AgentManagementState copyWith({
    AgentManagementStatus? status,
    List<AgentDefinition>? definitions,
    String? selectedProviderId,
    AgentDetection? detection,
    AgentConnectionTest? connectionTest,
    AgentConfigurationDocument? document,
    String? editorContents,
    AgentConfigurationValidation? validation,
    List<String>? logPaths,
    List<AgentLogEntry>? logs,
    bool? detecting,
    bool? testing,
    bool? saving,
    AgentManagementRepositoryFailure? failure,
    bool clearSelected = false,
    bool clearDetection = false,
    bool clearTest = false,
    bool clearDocument = false,
    bool clearFailure = false,
  }) {
    return AgentManagementState(
      status: status ?? this.status,
      definitions: definitions ?? this.definitions,
      selectedProviderId: clearSelected
          ? null
          : (selectedProviderId ?? this.selectedProviderId),
      detection: clearDetection ? null : (detection ?? this.detection),
      connectionTest: clearTest
          ? null
          : (connectionTest ?? this.connectionTest),
      document: clearDocument ? null : (document ?? this.document),
      editorContents: editorContents ?? this.editorContents,
      validation: validation ?? this.validation,
      logPaths: logPaths ?? this.logPaths,
      logs: logs ?? this.logs,
      detecting: detecting ?? this.detecting,
      testing: testing ?? this.testing,
      saving: saving ?? this.saving,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    definitions,
    selectedProviderId,
    detection,
    connectionTest,
    document,
    editorContents,
    validation,
    logPaths,
    logs,
    detecting,
    testing,
    saving,
    failure,
  ];

  @override
  String toString() {
    return 'AgentManagementState('
        'status: $status, '
        'definitions: ${definitions.length}, '
        'selectedProviderId: $selectedProviderId, '
        'hasDocument: ${document != null}, '
        'editorLength: ${editorContents.length}, '
        'validation: $validation, '
        'logs: ${logs.length}, '
        'detecting: $detecting, '
        'testing: $testing, '
        'saving: $saving, '
        'failure: $failure'
        ')';
  }
}

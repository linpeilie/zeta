import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:zeta/agent_management/bloc/agent_management_event.dart';
import 'package:zeta/agent_management/bloc/agent_management_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class AgentManagementBloc
    extends Bloc<AgentManagementEvent, AgentManagementState> {
  AgentManagementBloc({
    required AgentManagementRepository agentManagementRepository,
  }) : _agentManagementRepository = agentManagementRepository,
       super(const AgentManagementState()) {
    on<AgentManagementStarted>(_onStarted, transformer: restartable());
    on<AgentManagementAgentSelected>(
      _onAgentSelected,
      transformer: restartable(),
    );
    on<AgentManagementDetectRequested>(
      _onDetectRequested,
      transformer: droppable(),
    );
    on<AgentManagementTestRequested>(
      _onTestRequested,
      transformer: droppable(),
    );
    on<AgentManagementConfigEdited>(
      _onConfigEdited,
      transformer: sequential(),
    );
    on<AgentManagementConfigSaveRequested>(
      _onConfigSaveRequested,
      transformer: sequential(),
    );
    on<AgentManagementLogsRequested>(
      _onLogsRequested,
      transformer: restartable(),
    );
  }

  final AgentManagementRepository _agentManagementRepository;

  Future<void> _onStarted(
    AgentManagementStarted event,
    Emitter<AgentManagementState> emit,
  ) async {
    final definitions = _agentManagementRepository.definitions;
    emit(
      state.copyWith(
        status: AgentManagementStatus.ready,
        definitions: definitions,
        clearFailure: true,
      ),
    );
    if (definitions.isNotEmpty) {
      add(
        AgentManagementAgentSelected(
          event.providerId ?? definitions.first.providerId,
        ),
      );
    }
  }

  Future<void> _onAgentSelected(
    AgentManagementAgentSelected event,
    Emitter<AgentManagementState> emit,
  ) async {
    final providerId = event.providerId.trim();
    if (providerId.isEmpty) {
      return;
    }
    emit(
      state.copyWith(
        status: AgentManagementStatus.loading,
        selectedProviderId: providerId,
        editorContents: '',
        validation: AgentConfigurationValidation.valid,
        logPaths: const <String>[],
        logs: const <AgentLogEntry>[],
        detecting: false,
        testing: false,
        saving: false,
        clearDetection: true,
        clearTest: true,
        clearDocument: true,
        clearFailure: true,
      ),
    );
    try {
      final document = await _agentManagementRepository.readConfiguration(
        providerId,
      );
      if (emit.isDone) {
        return;
      }
      final logPaths = await _agentManagementRepository.discoverLogPaths(
        providerId,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.ready,
          document: document,
          editorContents: document.contents,
          logPaths: logPaths,
          validation: _agentManagementRepository.validateConfiguration(
            format: document.format,
            contents: document.contents,
          ),
          clearFailure: true,
        ),
      );
    } on AgentManagementRepositoryException catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> _onDetectRequested(
    AgentManagementDetectRequested event,
    Emitter<AgentManagementState> emit,
  ) async {
    final providerId = state.selectedProviderId;
    if (providerId == null) {
      return;
    }
    emit(state.copyWith(detecting: true, clearFailure: true));
    try {
      final detection = await _agentManagementRepository.detect(providerId);
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.ready,
          detection: detection,
          detecting: false,
          logPaths: detection.logPaths,
        ),
      );
    } on AgentManagementRepositoryException catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.failure,
          detecting: false,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> _onTestRequested(
    AgentManagementTestRequested event,
    Emitter<AgentManagementState> emit,
  ) async {
    final providerId = state.selectedProviderId;
    if (providerId == null) {
      return;
    }
    emit(state.copyWith(testing: true, clearFailure: true));
    try {
      final result = await _agentManagementRepository.testConnection(
        providerId,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.ready,
          connectionTest: result,
          testing: false,
        ),
      );
    } on AgentManagementRepositoryException catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.failure,
          testing: false,
          failure: error.failure,
        ),
      );
    }
  }

  void _onConfigEdited(
    AgentManagementConfigEdited event,
    Emitter<AgentManagementState> emit,
  ) {
    final format = state.document?.format ?? '';
    emit(
      state.copyWith(
        editorContents: event.contents,
        validation: _agentManagementRepository.validateConfiguration(
          format: format,
          contents: event.contents,
        ),
        clearFailure: true,
      ),
    );
  }

  Future<void> _onConfigSaveRequested(
    AgentManagementConfigSaveRequested event,
    Emitter<AgentManagementState> emit,
  ) async {
    final providerId = state.selectedProviderId;
    if (providerId == null || !state.validation.isValid) {
      return;
    }
    emit(state.copyWith(saving: true, clearFailure: true));
    try {
      final result = await _agentManagementRepository.saveConfiguration(
        providerId,
        contents: state.editorContents,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.ready,
          document: result.document,
          editorContents: result.document.contents,
          saving: false,
          validation: AgentConfigurationValidation.valid,
        ),
      );
    } on AgentManagementRepositoryException catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.failure,
          saving: false,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> _onLogsRequested(
    AgentManagementLogsRequested event,
    Emitter<AgentManagementState> emit,
  ) async {
    final providerId = state.selectedProviderId;
    if (providerId == null) {
      return;
    }
    emit(
      state.copyWith(
        status: AgentManagementStatus.loading,
        clearFailure: true,
      ),
    );
    try {
      final logs = await _agentManagementRepository.readLogs(
        providerId,
        state.logPaths,
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.ready,
          logs: logs,
        ),
      );
    } on AgentManagementRepositoryException catch (error) {
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: AgentManagementStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }
}

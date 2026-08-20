import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_event.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class IdeShellBloc extends Bloc<IdeShellEvent, IdeShellState> {
  IdeShellBloc({
    required WorkspaceRepository workspaceRepository,
    required ProjectSessionRepository projectSessionRepository,
    required DesktopPlatformRepository desktopPlatformRepository,
  }) : _workspaceRepository = workspaceRepository,
       _projectSessionRepository = projectSessionRepository,
       _desktopPlatformRepository = desktopPlatformRepository,
       super(const IdeShellState()) {
    on<IdeShellStarted>(_onStarted, transformer: restartable());
    on<IdeShellSnapshotUpdated>(
      _onSnapshotUpdated,
      transformer: restartable(),
    );
    on<IdeShellOpenProjectRequested>(
      _onOpenProjectRequested,
      transformer: droppable(),
    );
    on<IdeShellProjectPickedConsumed>(_onProjectPickedConsumed);
    on<IdeShellSidebarVisibilityToggled>(
      _onSidebarVisibilityToggled,
      transformer: sequential(),
    );
    on<IdeShellUsageExpandedToggled>(
      _onUsageExpandedToggled,
      transformer: sequential(),
    );
    on<IdeShellSidebarWidthChanged>(
      _onSidebarWidthChanged,
      transformer: sequential(),
    );
    on<IdeShellUsageHeightFractionChanged>(
      _onUsageHeightFractionChanged,
      transformer: sequential(),
    );
    on<IdeShellWindowMinimizeRequested>(
      _onWindowMinimizeRequested,
      transformer: droppable(),
    );
    on<IdeShellWindowMaximizeToggled>(
      _onWindowMaximizeToggled,
      transformer: droppable(),
    );
    on<IdeShellWindowCloseRequested>(
      _onWindowCloseRequested,
      transformer: droppable(),
    );
  }

  final WorkspaceRepository _workspaceRepository;
  final ProjectSessionRepository _projectSessionRepository;
  final DesktopPlatformRepository _desktopPlatformRepository;
  StreamSubscription<ProjectSessionSnapshot?>? _snapshotSubscription;
  StreamSubscription<MenuCommand>? _menuSubscription;

  Future<void> _onStarted(
    IdeShellStarted event,
    Emitter<IdeShellState> emit,
  ) async {
    await _snapshotSubscription?.cancel();
    await _menuSubscription?.cancel();
    _snapshotSubscription = _projectSessionRepository.snapshotChanges.listen(
      (snapshot) => add(IdeShellSnapshotUpdated(snapshot)),
    );
    _menuSubscription = _desktopPlatformRepository.menuCommands.commands.listen(
      (command) {
        if (command == MenuCommand.openProject) {
          add(const IdeShellOpenProjectRequested());
        }
      },
    );
    emit(
      state.copyWith(
        status: IdeShellStatus.ready,
        workbench:
            _projectSessionRepository.snapshot?.workbench ?? state.workbench,
        clearFailure: true,
      ),
    );
  }

  void _onSnapshotUpdated(
    IdeShellSnapshotUpdated event,
    Emitter<IdeShellState> emit,
  ) {
    final workbench = event.snapshot?.workbench;
    if (workbench == null || workbench == state.workbench) {
      return;
    }
    emit(state.copyWith(workbench: workbench, clearFailure: true));
  }

  Future<void> _onOpenProjectRequested(
    IdeShellOpenProjectRequested event,
    Emitter<IdeShellState> emit,
  ) async {
    try {
      final path = await _desktopPlatformRepository.pickDirectory();
      if (path == null || path.trim().isEmpty || emit.isDone) {
        return;
      }
      final root = path.trim();
      await _workspaceRepository.loadChildren(
        rootPath: root,
        directoryPath: root,
      );
      await _persist(
        emit,
        _snapshotWith(
          _projectSessionRepository.snapshot,
          activeProjectPath: root,
          projectPaths: _withProject(
            _projectSessionRepository.snapshot?.projectPaths ?? const [],
            root,
          ),
          workbench: state.workbench,
        ),
      );
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: IdeShellStatus.ready,
          pickedProjectPath: root,
          clearFailure: true,
        ),
      );
    } on Object catch (error) {
      _emitFailure(emit, error);
    }
  }

  void _onProjectPickedConsumed(
    IdeShellProjectPickedConsumed event,
    Emitter<IdeShellState> emit,
  ) {
    emit(state.copyWith(clearPickedProjectPath: true));
  }

  Future<void> _onSidebarVisibilityToggled(
    IdeShellSidebarVisibilityToggled event,
    Emitter<IdeShellState> emit,
  ) {
    return _updateWorkbench(
      emit,
      ProjectWorkbenchSnapshot(
        leftSidebarVisible: !state.workbench.leftSidebarVisible,
        agentUsageExpanded: state.workbench.agentUsageExpanded,
        leftSidebarWidth: state.workbench.leftSidebarWidth,
        agentUsageHeightFraction: state.workbench.agentUsageHeightFraction,
        selectedAgentUsageProviderId:
            state.workbench.selectedAgentUsageProviderId,
      ),
    );
  }

  Future<void> _onUsageExpandedToggled(
    IdeShellUsageExpandedToggled event,
    Emitter<IdeShellState> emit,
  ) {
    return _updateWorkbench(
      emit,
      ProjectWorkbenchSnapshot(
        leftSidebarVisible: state.workbench.leftSidebarVisible,
        agentUsageExpanded: !state.workbench.agentUsageExpanded,
        leftSidebarWidth: state.workbench.leftSidebarWidth,
        agentUsageHeightFraction: state.workbench.agentUsageHeightFraction,
        selectedAgentUsageProviderId:
            state.workbench.selectedAgentUsageProviderId,
      ),
    );
  }

  Future<void> _onSidebarWidthChanged(
    IdeShellSidebarWidthChanged event,
    Emitter<IdeShellState> emit,
  ) {
    return _updateWorkbench(
      emit,
      ProjectWorkbenchSnapshot(
        leftSidebarVisible: state.workbench.leftSidebarVisible,
        agentUsageExpanded: state.workbench.agentUsageExpanded,
        leftSidebarWidth: event.width,
        agentUsageHeightFraction: state.workbench.agentUsageHeightFraction,
        selectedAgentUsageProviderId:
            state.workbench.selectedAgentUsageProviderId,
      ),
    );
  }

  Future<void> _onUsageHeightFractionChanged(
    IdeShellUsageHeightFractionChanged event,
    Emitter<IdeShellState> emit,
  ) {
    return _updateWorkbench(
      emit,
      ProjectWorkbenchSnapshot(
        leftSidebarVisible: state.workbench.leftSidebarVisible,
        agentUsageExpanded: state.workbench.agentUsageExpanded,
        leftSidebarWidth: state.workbench.leftSidebarWidth,
        agentUsageHeightFraction: event.fraction,
        selectedAgentUsageProviderId:
            state.workbench.selectedAgentUsageProviderId,
      ),
    );
  }

  Future<void> _onWindowMinimizeRequested(
    IdeShellWindowMinimizeRequested event,
    Emitter<IdeShellState> emit,
  ) {
    return _runWindow(emit, _desktopPlatformRepository.windowCommands.minimize);
  }

  Future<void> _onWindowMaximizeToggled(
    IdeShellWindowMaximizeToggled event,
    Emitter<IdeShellState> emit,
  ) {
    return _runWindow(
      emit,
      _desktopPlatformRepository.windowCommands.toggleMaximize,
    );
  }

  Future<void> _onWindowCloseRequested(
    IdeShellWindowCloseRequested event,
    Emitter<IdeShellState> emit,
  ) {
    return _runWindow(emit, _desktopPlatformRepository.windowCommands.close);
  }

  Future<void> _updateWorkbench(
    Emitter<IdeShellState> emit,
    ProjectWorkbenchSnapshot workbench,
  ) async {
    emit(state.copyWith(workbench: workbench, clearFailure: true));
    await _persist(
      emit,
      _snapshotWith(
        _projectSessionRepository.snapshot,
        workbench: workbench,
      ),
    );
  }

  Future<void> _persist(
    Emitter<IdeShellState> emit,
    ProjectSessionSnapshot snapshot,
  ) async {
    try {
      await _projectSessionRepository.save(snapshot);
    } on Object catch (error) {
      _emitFailure(emit, error);
    }
  }

  Future<void> _runWindow(
    Emitter<IdeShellState> emit,
    Future<void> Function() action,
  ) async {
    try {
      await action();
      if (emit.isDone) {
        return;
      }
      emit(
        state.copyWith(
          status: IdeShellStatus.ready,
          clearFailure: true,
        ),
      );
    } on Object catch (error) {
      _emitFailure(emit, error);
    }
  }

  void _emitFailure(Emitter<IdeShellState> emit, Object error) {
    if (emit.isDone) {
      return;
    }
    emit(
      state.copyWith(
        status: IdeShellStatus.failure,
        failure: IdeShellFailure(_codeFor(error)),
      ),
    );
  }

  IdeShellFailureCode _codeFor(Object error) {
    if (error is ProjectSessionRepositoryException) {
      return IdeShellFailureCode.sessionPersist;
    }
    return IdeShellFailureCode.platformOperation;
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription?.cancel();
    await _menuSubscription?.cancel();
    return super.close();
  }
}

ProjectSessionSnapshot _snapshotWith(
  ProjectSessionSnapshot? snapshot, {
  required ProjectWorkbenchSnapshot workbench,
  List<String>? projectPaths,
  String? activeProjectPath,
}) {
  final current = snapshot ?? ProjectSessionSnapshot();
  return ProjectSessionSnapshot(
    projectPaths: projectPaths ?? current.projectPaths,
    activeProjectPath: activeProjectPath ?? current.activeProjectPath,
    currentFilePath: current.currentFilePath,
    expandedDirectoryPaths: current.expandedDirectoryPaths,
    selectedTreeKey: current.selectedTreeKey,
    activeAgentProviderId: current.activeAgentProviderId,
    agentThreadIdsByProject: current.agentThreadIdsByProject,
    projectThreadExpansionByProject: current.projectThreadExpansionByProject,
    cachedThreadsByProject: current.cachedThreadsByProject,
    selectedThreadIdsByProject: current.selectedThreadIdsByProject,
    projectLastOpenedAtByPath: current.projectLastOpenedAtByPath,
    projectHomeActive: current.projectHomeActive,
    workbench: workbench,
  );
}

List<String> _withProject(List<String> projectPaths, String path) {
  if (projectPaths.contains(path)) {
    return projectPaths;
  }
  return <String>[...projectPaths, path];
}

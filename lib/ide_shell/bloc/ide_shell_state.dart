import 'package:equatable/equatable.dart';
import 'package:project_session_repository/project_session_repository.dart';

export 'package:project_session_repository/project_session_repository.dart'
    show ProjectWorkbenchSnapshot;

enum IdeShellStatus { initial, ready, failure }

enum IdeShellFailureCode { platformOperation, sessionPersist }

final class IdeShellFailure extends Equatable {
  const IdeShellFailure(this.code);

  final IdeShellFailureCode code;

  @override
  List<Object?> get props => <Object?>[code];
}

final class IdeShellState extends Equatable {
  const IdeShellState({
    this.status = IdeShellStatus.initial,
    this.workbench = const ProjectWorkbenchSnapshot(),
    this.pickedProjectPath,
    this.failure,
  });

  final IdeShellStatus status;
  final ProjectWorkbenchSnapshot workbench;
  final String? pickedProjectPath;
  final IdeShellFailure? failure;

  IdeShellState copyWith({
    IdeShellStatus? status,
    ProjectWorkbenchSnapshot? workbench,
    String? pickedProjectPath,
    IdeShellFailure? failure,
    bool clearPickedProjectPath = false,
    bool clearFailure = false,
  }) {
    return IdeShellState(
      status: status ?? this.status,
      workbench: workbench ?? this.workbench,
      pickedProjectPath: clearPickedProjectPath
          ? null
          : (pickedProjectPath ?? this.pickedProjectPath),
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    workbench,
    pickedProjectPath,
    failure,
  ];
}

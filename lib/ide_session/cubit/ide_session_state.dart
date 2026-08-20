import 'package:equatable/equatable.dart';
import 'package:project_session_repository/project_session_repository.dart';

export 'package:project_session_repository/project_session_repository.dart'
    show
        ProjectSessionRepositoryFailure,
        ProjectSessionSnapshot,
        ProjectWorkbenchSnapshot;

enum IdeSessionStatus { initial, restoring, ready, failure }

final class IdeSessionInitialRoute extends Equatable {
  const IdeSessionInitialRoute({
    this.projectPath,
    this.filePath,
    this.threadId,
    this.projectHomeActive = false,
  });

  final String? projectPath;
  final String? filePath;
  final String? threadId;
  final bool projectHomeActive;

  @override
  List<Object?> get props => <Object?>[
    projectPath,
    filePath,
    threadId,
    projectHomeActive,
  ];
}

final class IdeSessionState extends Equatable {
  const IdeSessionState({
    this.status = IdeSessionStatus.initial,
    this.snapshot,
    this.initialRoute = const IdeSessionInitialRoute(),
    this.failure,
  });

  final IdeSessionStatus status;
  final ProjectSessionSnapshot? snapshot;
  final IdeSessionInitialRoute initialRoute;
  final ProjectSessionRepositoryFailure? failure;

  IdeSessionState copyWith({
    IdeSessionStatus? status,
    ProjectSessionSnapshot? snapshot,
    IdeSessionInitialRoute? initialRoute,
    ProjectSessionRepositoryFailure? failure,
    bool clearSnapshot = false,
    bool clearFailure = false,
  }) {
    return IdeSessionState(
      status: status ?? this.status,
      snapshot: clearSnapshot ? null : (snapshot ?? this.snapshot),
      initialRoute: initialRoute ?? this.initialRoute,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    snapshot,
    initialRoute,
    failure,
  ];
}

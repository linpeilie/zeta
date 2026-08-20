import 'package:equatable/equatable.dart';
import 'package:workspace_repository/workspace_repository.dart';

export 'package:workspace_repository/workspace_repository.dart'
    show WorkspaceIndex, WorkspaceNode, WorkspaceRepositoryFailure;

enum WorkspaceStatus { initial, loading, ready, failure }

final class WorkspaceState extends Equatable {
  const WorkspaceState({
    this.status = WorkspaceStatus.initial,
    this.rootPath,
    this.index,
    this.expandedPaths = const <String>{},
    this.selectedPath,
    this.childrenByPath = const <String, List<WorkspaceNode>>{},
    this.failure,
  });

  final WorkspaceStatus status;
  final String? rootPath;
  final WorkspaceIndex? index;
  final Set<String> expandedPaths;
  final String? selectedPath;
  final Map<String, List<WorkspaceNode>> childrenByPath;
  final WorkspaceRepositoryFailure? failure;

  List<WorkspaceNode> childrenOf(String path) {
    return childrenByPath[path] ?? const <WorkspaceNode>[];
  }

  bool isExpanded(String path) => expandedPaths.contains(path);

  WorkspaceState copyWith({
    WorkspaceStatus? status,
    String? rootPath,
    WorkspaceIndex? index,
    Set<String>? expandedPaths,
    String? selectedPath,
    Map<String, List<WorkspaceNode>>? childrenByPath,
    WorkspaceRepositoryFailure? failure,
    bool clearRoot = false,
    bool clearIndex = false,
    bool clearSelected = false,
    bool clearFailure = false,
  }) {
    return WorkspaceState(
      status: status ?? this.status,
      rootPath: clearRoot ? null : (rootPath ?? this.rootPath),
      index: clearIndex ? null : (index ?? this.index),
      expandedPaths: expandedPaths ?? this.expandedPaths,
      selectedPath: clearSelected ? null : (selectedPath ?? this.selectedPath),
      childrenByPath: childrenByPath ?? this.childrenByPath,
      failure: clearFailure ? null : (failure ?? this.failure),
    );
  }

  @override
  List<Object?> get props => <Object?>[
    status,
    rootPath,
    index,
    expandedPaths,
    selectedPath,
    childrenByPath,
    failure,
  ];
}

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';

sealed class WorkspaceSliceIntent {
  const WorkspaceSliceIntent();
}

final class WorkspaceProjectLoadRequested extends WorkspaceSliceIntent {
  const WorkspaceProjectLoadRequested(this.operationId, this.path);

  final OperationId operationId;
  final String path;
}

final class WorkspaceProjectLoadSucceeded extends WorkspaceSliceIntent {
  const WorkspaceProjectLoadSucceeded({
    required this.operationId,
    required this.path,
    required this.tree,
    required this.openedAt,
  });

  final OperationId operationId;
  final String path;
  final List<WorkspaceNode> tree;
  final DateTime openedAt;
}

final class WorkspaceProjectLoadFailed extends WorkspaceSliceIntent {
  const WorkspaceProjectLoadFailed(
    this.operationId,
    this.error,
    this.stackTrace,
  );

  final OperationId operationId;
  final Object error;
  final StackTrace stackTrace;
}

final class WorkspaceRestoreRequested extends WorkspaceSliceIntent {
  const WorkspaceRestoreRequested(this.operationId, this.snapshot);

  final OperationId operationId;
  final WorkspaceRestoreSnapshot snapshot;
}

final class WorkspaceRestoreSucceeded extends WorkspaceSliceIntent {
  const WorkspaceRestoreSucceeded({
    required this.operationId,
    required this.snapshot,
    required this.tree,
    required this.selectedTreePath,
  });

  final OperationId operationId;
  final WorkspaceRestoreSnapshot snapshot;
  final List<WorkspaceNode> tree;
  final String? selectedTreePath;
}

final class WorkspaceRestoreFailed extends WorkspaceSliceIntent {
  const WorkspaceRestoreFailed(this.operationId, this.error, this.stackTrace);

  final OperationId operationId;
  final Object error;
  final StackTrace stackTrace;
}

final class WorkspaceProjectOpened extends WorkspaceSliceIntent {
  const WorkspaceProjectOpened(this.path, this.openedAt);

  final String path;
  final DateTime openedAt;
}

final class WorkspaceProjectRemoved extends WorkspaceSliceIntent {
  const WorkspaceProjectRemoved(this.path);

  final String path;
}

final class WorkspaceActiveProjectCleared extends WorkspaceSliceIntent {
  const WorkspaceActiveProjectCleared();
}

final class WorkspaceCurrentFileCleared extends WorkspaceSliceIntent {
  const WorkspaceCurrentFileCleared();
}

final class WorkspaceTreeExpansionChanged extends WorkspaceSliceIntent {
  const WorkspaceTreeExpansionChanged(this.path, this.expanded);

  final String path;
  final bool expanded;
}

final class WorkspaceDirectoryLoaded extends WorkspaceSliceIntent {
  const WorkspaceDirectoryLoaded(this.path, this.children);

  final String path;
  final List<WorkspaceNode> children;
}

final class WorkspaceTreeNodeSelected extends WorkspaceSliceIntent {
  const WorkspaceTreeNodeSelected(this.path);

  final String path;
}

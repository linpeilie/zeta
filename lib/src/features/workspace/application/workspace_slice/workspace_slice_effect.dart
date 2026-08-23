import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';

/// Workspace I/O 与 derived-cache 副作用描述。
sealed class WorkspaceSliceEffect {
  const WorkspaceSliceEffect();
}

final class ReadWorkspaceProjectEffect extends WorkspaceSliceEffect {
  const ReadWorkspaceProjectEffect(this.operationId, this.path);

  final OperationId operationId;
  final String path;
}

final class RestoreWorkspaceEffect extends WorkspaceSliceEffect {
  const RestoreWorkspaceEffect(this.operationId, this.snapshot);

  final OperationId operationId;
  final WorkspaceRestoreSnapshot snapshot;
}

final class ReadWorkspaceDirectoryEffect extends WorkspaceSliceEffect {
  const ReadWorkspaceDirectoryEffect({
    required this.path,
    required this.expandedDirectoryPaths,
  });

  final String path;
  final Set<String> expandedDirectoryPaths;
}

final class IndexWorkspaceFilesEffect extends WorkspaceSliceEffect {
  const IndexWorkspaceFilesEffect(this.root);

  final String root;
}

final class InvalidateWorkspaceFilesEffect extends WorkspaceSliceEffect {
  const InvalidateWorkspaceFilesEffect(this.root);

  final String root;
}

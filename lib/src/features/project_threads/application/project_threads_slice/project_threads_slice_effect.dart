import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

/// Project Threads 副作用描述；执行实现只允许位于 app 组合层。
sealed class ProjectThreadsSliceEffect {
  const ProjectThreadsSliceEffect();
}

final class RestoreProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const RestoreProjectThreadsEffect({
    required this.projectPaths,
    required this.activeProjectPath,
    required this.snapshot,
  });

  final List<String> projectPaths;
  final String? activeProjectPath;
  final ProjectThreadsSessionSnapshot snapshot;
}

final class ActivateProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const ActivateProjectThreadsEffect(this.projectPath);

  final String projectPath;
}

final class RetainProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const RetainProjectThreadsEffect(this.projectPaths);

  final List<String> projectPaths;
}

final class ToggleProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const ToggleProjectThreadsEffect(this.operationId, this.projectPath);

  final OperationId operationId;
  final String projectPath;
}

final class SetArchivedProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const SetArchivedProjectThreadsEffect({
    required this.operationId,
    required this.projectPath,
    required this.archived,
  });

  final OperationId operationId;
  final String projectPath;
  final bool archived;
}

final class SetProjectThreadSearchEffect extends ProjectThreadsSliceEffect {
  const SetProjectThreadSearchEffect({
    required this.projectPath,
    required this.searchTerm,
  });

  final String projectPath;
  final String searchTerm;
}

final class LoadInitialProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const LoadInitialProjectThreadsEffect(this.operationId, this.projectPath);

  final OperationId operationId;
  final String projectPath;
}

final class LoadMoreProjectThreadsEffect extends ProjectThreadsSliceEffect {
  const LoadMoreProjectThreadsEffect(this.operationId, this.projectPath);

  final OperationId operationId;
  final String projectPath;
}

final class RenameProjectThreadEffect extends ProjectThreadsSliceEffect {
  const RenameProjectThreadEffect({
    required this.operationId,
    required this.projectPath,
    required this.threadId,
    required this.name,
  });

  final OperationId operationId;
  final String projectPath;
  final String threadId;
  final String name;
}

final class ArchiveProjectThreadEffect extends ProjectThreadsSliceEffect {
  const ArchiveProjectThreadEffect({
    required this.operationId,
    required this.projectPath,
    required this.threadId,
  });

  final OperationId operationId;
  final String projectPath;
  final String threadId;
}

final class UnarchiveProjectThreadEffect extends ProjectThreadsSliceEffect {
  const UnarchiveProjectThreadEffect({
    required this.operationId,
    required this.projectPath,
    required this.threadId,
  });

  final OperationId operationId;
  final String projectPath;
  final String threadId;
}

final class DeleteProjectThreadEffect extends ProjectThreadsSliceEffect {
  const DeleteProjectThreadEffect({
    required this.operationId,
    required this.projectPath,
    required this.threadId,
  });

  final OperationId operationId;
  final String projectPath;
  final String threadId;
}

final class ForkProjectThreadEffect extends ProjectThreadsSliceEffect {
  const ForkProjectThreadEffect({
    required this.operationId,
    required this.projectPath,
    required this.threadId,
    required this.permissionSnapshot,
  });

  final OperationId operationId;
  final String projectPath;
  final String threadId;
  final AgentPermissionRequestSnapshot? permissionSnapshot;
}

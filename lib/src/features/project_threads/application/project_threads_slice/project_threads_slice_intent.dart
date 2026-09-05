import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_effect.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads 切片意图。
sealed class ProjectThreadsSliceIntent {
  const ProjectThreadsSliceIntent();
}

/// 稳定操作 facade 发出的命令；reducer 只把 typed effect 交给 runner。
final class ProjectThreadsEffectRequested extends ProjectThreadsSliceIntent {
  const ProjectThreadsEffectRequested(this.effect);

  final ProjectThreadsSliceEffect effect;
}

final class ProjectThreadStatesReplaced extends ProjectThreadsSliceIntent {
  const ProjectThreadStatesReplaced(this.states);

  final Map<String, ProjectThreadListState> states;
}

final class ProjectThreadProjectsRetained extends ProjectThreadsSliceIntent {
  const ProjectThreadProjectsRetained(this.projectPaths);

  final List<String> projectPaths;
}

final class ProjectThreadStateApplied extends ProjectThreadsSliceIntent {
  const ProjectThreadStateApplied(this.projectPath, this.state);

  final String projectPath;
  final ProjectThreadListState state;
}

final class ProjectThreadSelected extends ProjectThreadsSliceIntent {
  const ProjectThreadSelected(this.projectPath, this.threadId);

  final String projectPath;
  final String threadId;
}

final class ProjectThreadSelectionCleared extends ProjectThreadsSliceIntent {
  const ProjectThreadSelectionCleared(this.projectPath);

  final String projectPath;
}

final class AllProjectThreadSelectionsCleared
    extends ProjectThreadsSliceIntent {
  const AllProjectThreadSelectionsCleared();
}

final class ProjectThreadRunningChanged extends ProjectThreadsSliceIntent {
  const ProjectThreadRunningChanged({
    required this.projectPath,
    required this.threadId,
    required this.isRunning,
    required this.activityAt,
  });

  final String projectPath;
  final String threadId;
  final bool isRunning;
  final DateTime activityAt;
}

final class CompletedProjectThreadDismissed extends ProjectThreadsSliceIntent {
  const CompletedProjectThreadDismissed(this.projectPath, this.threadId);

  final String projectPath;
  final String threadId;
}

final class ProjectThreadRuntimeStatusChanged
    extends ProjectThreadsSliceIntent {
  const ProjectThreadRuntimeStatusChanged({
    required this.projectPath,
    required this.threadId,
    required this.status,
    required this.waitingOnApproval,
    required this.waitingOnUserInput,
    required this.activityAt,
  });

  final String projectPath;
  final String threadId;
  final AgentThreadRuntimeStatus status;
  final bool waitingOnApproval;
  final bool waitingOnUserInput;
  final DateTime activityAt;
}

final class ProjectThreadTitleChanged extends ProjectThreadsSliceIntent {
  const ProjectThreadTitleChanged({
    required this.projectPath,
    required this.threadId,
    required this.title,
  });

  final String projectPath;
  final String threadId;
  final String? title;
}

final class ProjectThreadPreviewChanged extends ProjectThreadsSliceIntent {
  const ProjectThreadPreviewChanged({
    required this.projectPath,
    required this.threadId,
    required this.preview,
  });

  final String projectPath;
  final String threadId;
  final String preview;
}

final class ProjectThreadRemoved extends ProjectThreadsSliceIntent {
  const ProjectThreadRemoved(this.projectPath, this.threadId);

  final String projectPath;
  final String threadId;
}

final class ProjectThreadPrepended extends ProjectThreadsSliceIntent {
  const ProjectThreadPrepended(this.projectPath, this.thread);

  final String projectPath;
  final AgentThreadSummary thread;
}

/// 异步命令完成；不新增 UI 业务事实，只用于结算调用方 Future。
final class ProjectThreadsOperationSucceeded extends ProjectThreadsSliceIntent {
  const ProjectThreadsOperationSucceeded(this.operationId);

  final OperationId operationId;
}

final class ProjectThreadsForkSucceeded extends ProjectThreadsSliceIntent {
  const ProjectThreadsForkSucceeded(this.operationId, this.session);

  final OperationId operationId;
  final AgentSession? session;
}

final class ProjectThreadsOperationFailed extends ProjectThreadsSliceIntent {
  const ProjectThreadsOperationFailed(
    this.operationId,
    this.error,
    this.stackTrace,
  );

  final OperationId operationId;
  final Object error;
  final StackTrace stackTrace;
}

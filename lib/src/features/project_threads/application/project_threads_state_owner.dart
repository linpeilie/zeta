import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads controller 写入列表事实所依赖的纯 application 端口。
///
/// controller 只负责 Provider 查询、能力校验和防抖；具体状态由 MVI store 独占。
/// application 因而不反向 import presentation。
abstract interface class ProjectThreadsStateOwner {
  Map<String, ProjectThreadListState> get states;

  ProjectThreadListState stateFor(String projectPath);

  void applyStatesReplacement(Map<String, ProjectThreadListState> states);

  void applyProjectsRetention(List<String> projectPaths);

  void applyProjectState(String projectPath, ProjectThreadListState state);

  void applyThreadSelection(String projectPath, String threadId);

  void applyThreadSelectionClear(String projectPath);

  void applyAllThreadSelectionsClear();

  void applyThreadRunning({
    required String projectPath,
    required String threadId,
    required bool isRunning,
  });

  void applyCompletedThreadDismissal({
    required String projectPath,
    required String threadId,
  });

  void applyThreadRuntimeStatus({
    required String projectPath,
    required String threadId,
    required AgentThreadRuntimeStatus status,
    required bool waitingOnApproval,
    required bool waitingOnUserInput,
  });

  void applyThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  });

  void applyThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  });

  bool applyThreadRemoval({
    required String projectPath,
    required String threadId,
  });

  void applyThreadPrepend({
    required String projectPath,
    required AgentThreadSummary thread,
  });

  void Function() subscribe(void Function() listener);
}

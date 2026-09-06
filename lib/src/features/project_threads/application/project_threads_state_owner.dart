import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';

/// Project Threads effect runner 写入列表事实所依赖的纯 application 端口。
///
/// runner 只负责 Provider 查询、能力校验、防抖与分页；具体状态由 application Notifier 独占。
/// application 因而不反向 import presentation。
abstract interface class ProjectThreadsStateOwner {
  Map<String, ProjectThreadListState> get states;

  ProjectThreadListState stateFor(String projectPath);

  /// 当前项目列表中第一个匹配的摘要；不根据活跃 Provider 推断归属。
  AgentThreadSummary? threadFor(String projectPath, String threadId);

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

  /// Selection removal has committed; notify the attached Shell once.
  void activeThreadCleared(String projectPath, String threadId);

  /// effect 的成功回执。
  void operationSucceeded(OperationId operationId);

  /// fork effect 的 typed 成功回执。
  void forkSucceeded(OperationId operationId, AgentSession? session);

  /// effect 的失败回执；错误只用于结算调用方 Future，不进入 state。
  void operationFailed(
    OperationId operationId,
    Object error,
    StackTrace stackTrace,
  );
}

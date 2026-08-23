import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_threads_session_snapshot.dart';

/// Project Threads MVI store 对 Shell 暴露的稳定操作面。
abstract interface class ProjectThreadsOperations {
  ProjectThreadListState stateFor(String projectPath);

  ProjectThreadsSessionSnapshot get sessionSnapshot;

  void restoreSession({
    required List<String> projectPaths,
    required String? activeProjectPath,
    required ProjectThreadsSessionSnapshot snapshot,
  });

  void activateProject(String projectPath);

  void retainProjects(List<String> projectPaths);

  Future<void> toggleProject(String projectPath);

  Future<void> setArchivedView({
    required String projectPath,
    required bool archived,
  });

  void setSearchTerm({required String projectPath, required String searchTerm});

  Future<void> loadInitial(String projectPath);

  Future<void> loadMore(String projectPath);

  void selectThread(String projectPath, AgentThreadSummary thread);

  void selectThreadId(String projectPath, String threadId);

  void clearSelectedThread(String projectPath);

  void clearAllSelectedThreads();

  void registerThreadMapping(String projectPath, String threadId);

  AgentThreadSummary registerSession(
    String projectPath,
    AgentSession session, {
    String? preview,
    bool markRunning = false,
  });

  void setThreadRunning(String threadId, {required bool isRunning});

  void dismissCompletedThread({
    required String projectPath,
    required String threadId,
  });

  void syncRuntimeSnapshot({
    required String projectPath,
    required AgentConversationThreadSnapshot snapshot,
  });

  void updateThreadTitle({
    required String projectPath,
    required String threadId,
    required String? title,
  });

  void updateThreadPreview({
    required String projectPath,
    required String threadId,
    required String preview,
  });

  Future<void> renameThread({
    required String projectPath,
    required String threadId,
    required String name,
  });

  Future<void> archiveThread({
    required String projectPath,
    required String threadId,
  });

  Future<void> unarchiveThread({
    required String projectPath,
    required String threadId,
  });

  Future<void> deleteThread({
    required String projectPath,
    required String threadId,
  });

  Future<AgentSession?> forkThread({
    required String projectPath,
    required String threadId,
    AgentPermissionRequestSnapshot? permissionSnapshot,
  });

  void Function(String projectPath, String threadId)? onActiveThreadCleared;

  void dispose();
}

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// Project Threads 模块的可持久化快照。
///
/// 页面层只需在恢复和保存时传递这个对象，不再手动拼装多个 project map。
class ProjectThreadsSessionSnapshot {
  const ProjectThreadsSessionSnapshot({
    this.expansionByProject = const <String, bool>{},
    this.cachedThreadsByProject = const <String, List<AgentThreadSummary>>{},
    this.selectedThreadIdsByProject = const <String, String>{},
  });

  /// 项目下 thread 列表的展开状态。
  final Map<String, bool> expansionByProject;

  /// 项目下 thread 列表的轻量缓存。
  final Map<String, List<AgentThreadSummary>> cachedThreadsByProject;

  /// 每个项目当前选中的 thread id。
  final Map<String, String> selectedThreadIdsByProject;
}

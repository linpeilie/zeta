import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/agent_plan_revision_drafts.dart';

/// 随 entry（controller 身份）存废的 presentation 级缓存。
///
/// 与 [AgentPaneRetention] 同模式：Expando 弱键不延长宿主寿命。
/// pane `dispose` 或 controller 换代不得销毁这批缓存；entry 关闭才 [closeEntry]。
final class AgentPanePresentationCache {
  AgentPanePresentationCache({
    AgentMarkdownCache? markdownCache,
    AgentPlanRevisionDraftStore? planRevisionDrafts,
  }) : markdownCache = markdownCache ?? AgentMarkdownCache(),
       planRevisionDrafts = planRevisionDrafts ?? AgentPlanRevisionDraftStore();

  final AgentMarkdownCache markdownCache;
  final AgentPlanRevisionDraftStore planRevisionDrafts;

  void dispose() {
    markdownCache.dispose();
    planRevisionDrafts.dispose();
  }
}

final class AgentPanePresentationStore {
  final Expando<AgentPanePresentationCache> _caches =
      Expando<AgentPanePresentationCache>();

  AgentPanePresentationCache cacheFor(Object identity) =>
      _caches[identity] ??= AgentPanePresentationCache();

  void closeEntry(Object identity) {
    _caches[identity]?.dispose();
    _caches[identity] = null;
  }
}

final agentPanePresentationStoreProvider = Provider<AgentPanePresentationStore>(
  (ref) => AgentPanePresentationStore(),
);

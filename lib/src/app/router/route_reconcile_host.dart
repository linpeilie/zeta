/// 路由资源 reconcile 委托给 Shell 的窄端口。
///
/// Coordinator 只做分发、串行化与过期检查；打开语义仍由 [IdeShellController]
/// 既有方法承担。本文件不 import `go_router`。
abstract interface class RouteReconcileHost {
  /// 启动恢复完成。深链在恢复未就绪时排队等这个 Future。
  Future<void> get initialRestoreDone;

  /// 由 threadId（及可选 provider 归属）解析项目路径；找不到返回 `null`。
  String? projectPathForThread({
    required String threadId,
    String? providerIdHint,
  });

  Future<void> openProjectHomeFromRoute(String projectPath);

  Future<void> startNewThreadForProject(
    String projectPath, {
    required String providerId,
  });

  Future<bool> openThreadFromRoute(String projectPath, String threadId);
}

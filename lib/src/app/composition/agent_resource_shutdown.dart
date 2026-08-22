/// 按依赖反序关闭 Agent 相关资源。
///
/// 顺序是硬要求，不是风格问题：
///
/// 1. **runtime registry** 拥有 CLI 进程与 JSON-RPC transport，必须先退出；
/// 2. **plugin catalog** 提供 registry 使用的 bundle 工厂，是 runtime 的上游
///    依赖，只能在 runtime 全部退出之后关闭；
/// 3. 日志与窗口由 `window_bootstrap` 在全部 hook 结束后收尾。
///
/// 抽成独立函数是为了让顺序可测：窗口关闭 hook 与 `MainApp.dispose` 共用同一个
/// 入口，避免两条退出路径各写一遍、顺序还不一样。
///
/// 每一步都必须 `await`：并发关闭会让插件先于仍在退出的 runtime 消失。
Future<void> shutdownAgentResourcesInOrder({
  Future<void> Function()? closeRuntimeRegistry,
  Future<void> Function()? closePluginCatalog,
}) async {
  if (closeRuntimeRegistry != null) {
    await closeRuntimeRegistry();
  }
  if (closePluginCatalog != null) {
    await closePluginCatalog();
  }
}

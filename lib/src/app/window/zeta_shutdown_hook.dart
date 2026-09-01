/// 窗口真正关闭前必须等待的清理任务。
///
/// 登记进窗口宿主的是对象，不是 `Future Function()`：注销按实例同一性。
/// 关日志不走这条接口，仍接在全部 hook 跑完之后。
abstract interface class ZetaShutdownHook {
  /// 执行清理。抛错由宿主吞掉，不能挡住关窗。
  Future<void> run();
}

/// 宿主运行模式。
///
/// 在此之前，这套语义是从 `MainApp.sessionLoader` / `sessionSaver` 是否为 null
/// **推断**出来的：传了回调就意味着"这是 widget test / 嵌入宿主"。推断藏在两个
/// 私有 getter 里，一处改动就可能让 widget test 开始写用户真实的 `~/.zeta`，
/// 或者去扫描本机安装的 Agent CLI。现在把它变成显式取值。
///
/// 行为对照见 `test/src/app/main_app_host_persistence_characterization_test.dart`。
enum ZetaHostMode {
  /// 生产模式：由 `ZetaStorageBindings.file` 落盘，探测本机 CLI，读取本机用量历史。
  local,

  /// 临时宿主模式：widget test 与嵌入宿主使用。
  ///
  /// 三条硬约束——**改动这里等于改动用户数据安全边界**：
  ///
  /// 1. 未注入 `ZetaStorageBindings` 时使用内存文档，一个字节都不写 `~/.zeta`；
  /// 2. 不探测本机安装的 Agent CLI（用无安装结果的 stub 顶掉）；
  /// 3. 不自动刷新 Agent 用量（否则会读本机 CLI 的历史记录）。
  ///
  /// 第 3 条在调用方显式注入统计仓储时可以恢复——那时数据来源已经是注入的假实现，
  /// 不再触碰本机。
  ephemeral;

  /// 是否把持久化落到本机文件。
  bool get usesFilePersistence => this == ZetaHostMode.local;

  /// 是否允许读取本机 Agent CLI 的安装状态与历史记录。
  bool get allowsLocalCliAccess => this == ZetaHostMode.local;
}

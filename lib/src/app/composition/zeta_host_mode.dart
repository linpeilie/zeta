import 'package:flutter_riverpod/flutter_riverpod.dart';

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
  /// 3. 不自动刷新 Agent 用量（否则会读本机 CLI 的历史记录）；
  /// 4. 不装本机原生对话框（目录选择器由调用方经 `MainApp.overrides` 注入）。
  ///
  /// 第 3 条在调用方显式注入统计仓储时可以恢复——那时数据来源已经是注入的假实现，
  /// 不再触碰本机。
  ephemeral;

  /// 是否把持久化落到本机文件。
  bool get usesFilePersistence => this == ZetaHostMode.local;

  /// 是否允许读取本机 Agent CLI 的安装状态与历史记录。
  bool get allowsLocalCliAccess => this == ZetaHostMode.local;

  /// 是否允许弹本机原生对话框（目前只有系统目录选择器）。
  ///
  /// ephemeral 宿主返回 false：原生对话框在 widget test 里要么弹不出来、要么把
  /// 测试挂在系统 UI 上，选择器一律由调用方注入。
  bool get usesNativeDialogs => this == ZetaHostMode.local;

  /// 是否接管原生窗口与随之而来的系统集成。
  ///
  /// 覆盖窗口事件监听、关闭前的资源回收、原生 File 菜单、桌面通知与任务栏
  /// 指示：这些在 widget test 里要么打不到平台通道、要么把用例挂住，因此
  /// ephemeral 宿主一律换成不做事的实现（见 `ZetaWindowHost`）。
  bool get usesNativeDesktopIntegration => this == ZetaHostMode.local;

  /// 显示语言是否要等持久化的常规设置读完再定。
  ///
  /// 生产必须等：先按默认语言挂一次 UI 再跳变，用户会看到文案闪一下。测试不
  /// 等——除非用例本身就在验证这个等待过程，那时自己覆盖显示语言来源。
  bool get waitsForPersistedDisplayLanguage => this == ZetaHostMode.local;
}

/// 宿主运行模式的容器入口。
///
/// 组合根按 `ZetaAppComposition.create(hostMode:)` 覆盖它，之后所有"这台机器能
/// 不能碰"的默认值都从这里派生（窗口宿主、显示语言来源、桌面通知、用量自动
/// 刷新）。**不要再经 `overrides` 覆盖它**：组合根已经装过一次，同容器重复
/// override 会被 Riverpod 断言拦下。
final zetaHostModeProvider = Provider<ZetaHostMode>(
  (ref) => ZetaHostMode.local,
  name: 'zetaHostMode',
);

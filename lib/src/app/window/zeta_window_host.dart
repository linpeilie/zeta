import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/window_bootstrap.dart';

/// 桌面窗口宿主。
///
/// 取代了此前贯穿组合根、`MainApp` 与 `IdeHome` 的 `enableNativeWindowFrame`
/// 布尔开关。"接管原生窗口"从来不是一个标志位，而是一整套只有桌面宿主才成立的
/// 实现：窗口事件监听、关闭前的资源回收、原生 File 菜单、把窗口抢到前台。把它
/// 们收进一个端口之后，调用点不再各自写 `if (enableNativeWindowFrame)`——那种
/// 写法每加一个平台调用就要记得补一次分支，漏掉一处就会在 widget test 里打到
/// 真实平台通道。
///
/// 实现只有两个：[NativeDesktopWindowHost]（生产默认）与 [HeadlessWindowHost]
/// （widget test）。要换实现就覆盖 [zetaWindowHostProvider]；测试入口
/// `zetaTestComposition` 会自动装无头实现。
abstract interface class ZetaWindowHost {
  /// 是否由原生窗口框架渲染标题栏与菜单栏。
  ///
  /// 为 false 时窗口菜单退化为空列表，标题栏由 Flutter 自绘。
  bool get rendersNativeChrome;

  /// 是否绘制窗口控制按钮（最小化 / 最大化 / 关闭）。
  bool get showsWindowControls;

  /// 订阅窗口事件（最小化 / 恢复 / 聚焦 / 全屏）。
  void addListener(WindowListener listener);

  /// 取消订阅窗口事件。
  void removeListener(WindowListener listener);

  /// 注册窗口真正关闭前必须等待的资源清理任务。
  void addShutdownHook(Future<void> Function() hook);

  /// 移除此前注册的清理任务。
  void removeShutdownHook(Future<void> Function() hook);

  /// 把当前显示语言的 File / Open Project 标签发给原生菜单。
  Future<void> configureNativeMenu({
    required String fileMenuLabel,
    required String openProjectLabel,
  });

  /// 恢复窗口并抢到前台，用于桌面通知点击后的 thread 激活。
  Future<void> revealWindow();

  /// 关闭窗口（菜单栏「文件 - 退出」）。
  Future<void> closeWindow();
}

/// 生产实现：真正接管 `window_manager` 与原生菜单通道。
final class NativeDesktopWindowHost implements ZetaWindowHost {
  const NativeDesktopWindowHost({this.showsWindowControls = true});

  @override
  bool get rendersNativeChrome => true;

  @override
  final bool showsWindowControls;

  @override
  void addListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  void addShutdownHook(Future<void> Function() hook) =>
      addDesktopWindowShutdownHook(hook);

  @override
  void removeShutdownHook(Future<void> Function() hook) =>
      removeDesktopWindowShutdownHook(hook);

  @override
  Future<void> configureNativeMenu({
    required String fileMenuLabel,
    required String openProjectLabel,
  }) async {
    await MenuActionBridge.instance.configure(
      fileMenuLabel: fileMenuLabel,
      openProjectLabel: openProjectLabel,
    );
  }

  @override
  Future<void> revealWindow() async {
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
  }

  @override
  Future<void> closeWindow() => windowManager.close();
}

/// 无窗口实现：widget test 用，一个平台通道都不碰。
///
/// [showsWindowControls] 仍然可调：控制按钮是纯绘制，不经平台通道，用例按自己
/// 要断言的布局决定画不画。
final class HeadlessWindowHost implements ZetaWindowHost {
  const HeadlessWindowHost({this.showsWindowControls = true});

  @override
  bool get rendersNativeChrome => false;

  @override
  final bool showsWindowControls;

  @override
  void addListener(WindowListener listener) {}

  @override
  void removeListener(WindowListener listener) {}

  @override
  void addShutdownHook(Future<void> Function() hook) {}

  @override
  void removeShutdownHook(Future<void> Function() hook) {}

  @override
  Future<void> configureNativeMenu({
    required String fileMenuLabel,
    required String openProjectLabel,
  }) async {}

  @override
  Future<void> revealWindow() async {}

  @override
  Future<void> closeWindow() async {}
}

/// 当前窗口宿主。
///
/// 生产默认接管原生窗口。widget test 由 `zetaTestComposition` 换成
/// [HeadlessWindowHost]；要改窗口控制按钮可见性，覆盖成
/// `HeadlessWindowHost(showsWindowControls: …)`。
final zetaWindowHostProvider = Provider<ZetaWindowHost>(
  (ref) => const NativeDesktopWindowHost(),
  name: 'zetaWindowHost',
);

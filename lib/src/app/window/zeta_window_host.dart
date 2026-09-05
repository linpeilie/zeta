import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:macos_window_utils/window_manipulator.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app_constants.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/app/menu_action_bridge.dart';
import 'package:zeta/src/app/window/zeta_shutdown_hook.dart';
import 'package:zeta/src/app/window/zeta_window_frame_color.dart';

/// 桌面窗口宿主。
///
/// 取代了此前贯穿组合根、`MainApp` 与 `IdeHome` 的 `enableNativeWindowFrame`
/// 布尔开关。"接管原生窗口"从来不是一个标志位，而是一整套只有桌面宿主才成立的
/// 实现：窗口事件监听、关闭前的资源回收、原生 File 菜单、把窗口抢到前台。把它
/// 们收进一个端口之后，调用点不再各自写 `if (enableNativeWindowFrame)`——那种
/// 写法每加一个平台调用就要记得补一次分支，漏掉一处就会在 widget test 里打到
/// 真实平台通道。
///
/// 实现只有两个：[NativeDesktopWindowHost] 与 [HeadlessWindowHost]。
/// 本 provider **fail-closed**：生产由 `lib/main.dart` 注入已经
/// [NativeDesktopWindowHost.prepareDesktopWindow] 过的那一份，测试由
/// `zetaTestComposition` 装无头实现。构造函数不得自动装关窗拦截——有的
/// widget test 只为画标题栏才注入 native host。
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

  /// 注册窗口真正关闭前必须等待的清理任务。
  void addShutdownHook(ZetaShutdownHook hook);

  /// 移除此前登记的同一 [ZetaShutdownHook] 实例。
  void removeShutdownHook(ZetaShutdownHook hook);

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
///
/// 关窗拦截与 hook 表在这一份实例上，不再经过 `window_bootstrap` 的全局表。
/// 只有 [prepareDesktopWindow] 才会 `setPreventClose` 并装上关窗 listener——
/// 必须由 `main` 在 `runApp` 之前对**随后注入容器的那一份**调用。
final class NativeDesktopWindowHost implements ZetaWindowHost {
  NativeDesktopWindowHost({this.showsWindowControls = true});

  @override
  bool get rendersNativeChrome => true;

  @override
  final bool showsWindowControls;

  final Set<ZetaShutdownHook> _shutdownHooks = <ZetaShutdownHook>{};

  late final _NativeWindowCloseListener _closeListener =
      _NativeWindowCloseListener(this);

  var _processCloseAttached = false;

  /// 亮窗、藏标题栏，并装上进程级关窗拦截。
  ///
  /// 需要在 `runApp` 之前、且已经 `windowManager.ensureInitialized` 之后调用。
  Future<void> prepareDesktopWindow({Brightness? preferredBrightness}) async {
    if (!_processCloseAttached) {
      addListener(_closeListener);
      await windowManager.setPreventClose(true);
      _processCloseAttached = true;
    }
    final frameColor = launchWindowFrameColor(
      systemBrightness:
          WidgetsBinding.instance.platformDispatcher.platformBrightness,
      preferredBrightness: preferredBrightness,
    );
    final options = WindowOptions(
      size: const Size(1280, 800),
      minimumSize: const Size(900, 560),
      center: true,
      title: appTitle,
      // 隐藏原生标题栏：macOS 下交通灯按钮仍保留，内容会延伸到窗口顶部。
      titleBarStyle: TitleBarStyle.hidden,
      backgroundColor: frameColor,
    );

    if (Platform.isMacOS) {
      await WindowManipulator.initialize(enableWindowDelegate: true);
    }

    await windowManager.waitUntilReadyToShow(options, () async {
      if (Platform.isMacOS) {
        // 保留全尺寸内容区与隐藏原生标题，由 Flutter 自绘不透明标题栏；
        // 不再启用透明背景与 NSVisualEffectView 毛玻璃。
        await WindowManipulator.enableFullSizeContentView();
        await WindowManipulator.hideTitle();
        await WindowManipulator.makeTitlebarTransparent();
      }
      await windowManager.show();
      await windowManager.focus();
    });
  }

  @override
  void addListener(WindowListener listener) =>
      windowManager.addListener(listener);

  @override
  void removeListener(WindowListener listener) =>
      windowManager.removeListener(listener);

  @override
  void addShutdownHook(ZetaShutdownHook hook) {
    _shutdownHooks.add(hook);
  }

  @override
  void removeShutdownHook(ZetaShutdownHook hook) {
    _shutdownHooks.remove(hook);
  }

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

  /// 按登记顺序跑 hook。测试用来覆盖登记/移除，不关窗、不关日志。
  @visibleForTesting
  Future<void> flushShutdownHooks() async {
    for (final hook in _shutdownHooks.toList(growable: false)) {
      try {
        await hook.run();
      } catch (_) {
        // 单个资源关闭失败不能阻止窗口退出。
      }
    }
  }

  Future<void> _flushAndClose() async {
    try {
      await flushShutdownHooks();
      await shutdownAppLogging();
    } finally {
      await windowManager.setPreventClose(false);
      await windowManager.close();
    }
  }
}

final class _NativeWindowCloseListener with WindowListener {
  _NativeWindowCloseListener(this._host);

  final NativeDesktopWindowHost _host;
  var _isClosing = false;

  @override
  void onWindowClose() {
    if (_isClosing) {
      return;
    }
    _isClosing = true;
    unawaited(_host._flushAndClose());
  }
}

/// 无窗口实现：widget test 用，一个平台通道都不碰。
///
/// [showsWindowControls] 仍然可调：控制按钮是纯绘制，不经平台通道，用例按自己
/// 要断言的布局决定画不画。
///
/// 会记下 [addListener] 的订阅者，测试经 `emit*` 把窗口事件打进
/// 窗口表面快照，不要再去调 `MainApp` 的 State。
final class HeadlessWindowHost implements ZetaWindowHost {
  HeadlessWindowHost({this.showsWindowControls = true});

  @override
  bool get rendersNativeChrome => false;

  @override
  final bool showsWindowControls;

  final List<WindowListener> _listeners = <WindowListener>[];

  @override
  void addListener(WindowListener listener) {
    if (!_listeners.contains(listener)) {
      _listeners.add(listener);
    }
  }

  @override
  void removeListener(WindowListener listener) {
    _listeners.remove(listener);
  }

  void emitMinimize() => _emit((listener) => listener.onWindowMinimize());

  void emitRestore() => _emit((listener) => listener.onWindowRestore());

  void emitMaximize() => _emit((listener) => listener.onWindowMaximize());

  void emitUnmaximize() => _emit((listener) => listener.onWindowUnmaximize());

  void emitFocus() => _emit((listener) => listener.onWindowFocus());

  void emitBlur() => _emit((listener) => listener.onWindowBlur());

  void emitEnterFullScreen() =>
      _emit((listener) => listener.onWindowEnterFullScreen());

  void emitEvent(String eventName) =>
      _emit((listener) => listener.onWindowEvent(eventName));

  void _emit(void Function(WindowListener listener) notify) {
    for (final listener in List<WindowListener>.of(_listeners)) {
      notify(listener);
    }
  }

  @override
  void addShutdownHook(ZetaShutdownHook hook) {}

  @override
  void removeShutdownHook(ZetaShutdownHook hook) {}

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
/// 未覆盖就读到这里是接线漏了：生产必须注入已经
/// [NativeDesktopWindowHost.prepareDesktopWindow] 的实例，测试装
/// [HeadlessWindowHost]。
final zetaWindowHostProvider = Provider<ZetaWindowHost>(
  (ref) => throw StateError('Window host is not installed'),
  name: 'zetaWindowHost',
);

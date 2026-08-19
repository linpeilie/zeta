import 'dart:async';
import 'dart:ui';

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/app/platform/window_command_adapter.dart';

/// Production facade over an injected [WindowManager].
final class FlutterWindowManagerFacade
    with WindowListener
    implements WindowManagerFacade {
  /// Creates a facade and installs its plugin listener.
  FlutterWindowManagerFacade(this._manager) {
    _manager.addListener(this);
  }

  final WindowManager _manager;
  final StreamController<WindowLifecycleEvent> _lifecycle =
      StreamController<WindowLifecycleEvent>.broadcast();

  @override
  Stream<WindowLifecycleEvent> get lifecycle => _lifecycle.stream;

  @override
  Future<void> close() => _manager.close();

  @override
  Future<void> dispose() async {
    _manager.removeListener(this);
    await _lifecycle.close();
  }

  @override
  Future<void> ensureInitialized() => _manager.ensureInitialized();

  @override
  Future<void> focus() => _manager.focus();

  @override
  Future<bool> isMaximized() => _manager.isMaximized();

  @override
  Future<void> maximize() => _manager.maximize();

  @override
  Future<void> minimize() => _manager.minimize();

  @override
  Future<void> prepare(WindowBootstrapConfiguration configuration) =>
      _manager.waitUntilReadyToShow(
        WindowOptions(
          size: Size(configuration.size.width, configuration.size.height),
          minimumSize: Size(
            configuration.minimumSize.width,
            configuration.minimumSize.height,
          ),
          center: configuration.center,
          title: configuration.title,
          titleBarStyle: TitleBarStyle.hidden,
          backgroundColor: configuration.backgroundColorArgb == null
              ? null
              : Color(configuration.backgroundColorArgb!),
        ),
      );

  @override
  Future<void> show() => _manager.show();

  @override
  Future<void> unmaximize() => _manager.unmaximize();

  @override
  void onWindowBlur() => _emit(WindowLifecycleEvent.blurred);

  @override
  void onWindowClose() => _emit(WindowLifecycleEvent.closeRequested);

  @override
  void onWindowFocus() => _emit(WindowLifecycleEvent.focused);

  @override
  void onWindowMaximize() => _emit(WindowLifecycleEvent.maximized);

  @override
  void onWindowMinimize() => _emit(WindowLifecycleEvent.minimized);

  @override
  void onWindowRestore() => _emit(WindowLifecycleEvent.restored);

  @override
  void onWindowUnmaximize() => _emit(WindowLifecycleEvent.unmaximized);

  void _emit(WindowLifecycleEvent event) {
    if (!_lifecycle.isClosed) {
      _lifecycle.add(event);
    }
  }
}

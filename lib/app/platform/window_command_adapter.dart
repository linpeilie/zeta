import 'package:desktop_platform_api/desktop_platform_api.dart';

/// Injectable facade for `window_manager`.
abstract interface class WindowManagerFacade {
  /// Plugin lifecycle notifications.
  Stream<WindowLifecycleEvent> get lifecycle;

  /// Initializes the plugin.
  Future<void> ensureInitialized();

  /// Applies configuration while the window remains hidden.
  Future<void> prepare(WindowBootstrapConfiguration configuration);

  /// Shows the window.
  Future<void> show();

  /// Focuses the window.
  Future<void> focus();

  /// Whether the window is maximized.
  Future<bool> isMaximized();

  /// Maximizes the window.
  Future<void> maximize();

  /// Leaves the maximized state.
  Future<void> unmaximize();

  /// Minimizes the window.
  Future<void> minimize();

  /// Closes the window.
  Future<void> close();

  /// Holds or releases the native close request.
  Future<void> setPreventClose({required bool preventClose});

  /// Releases plugin listeners.
  Future<void> dispose();
}

/// Injectable facade for macOS title-bar configuration.
abstract interface class MacOsWindowFacade {
  /// Initializes macOS window delegation when supported.
  Future<void> initialize();

  /// Extends Flutter content under a hidden transparent native title bar.
  Future<void> configureTitleBar();
}

/// Implements window bootstrap and commands through injected facades.
final class WindowCommandAdapter
    implements WindowBootstrapApi, WindowCommandApi {
  /// Creates an adapter.
  const WindowCommandAdapter(this._windowManager, this._macOsWindow);

  final WindowManagerFacade _windowManager;
  final MacOsWindowFacade _macOsWindow;

  @override
  Stream<WindowLifecycleEvent> get lifecycle => _windowManager.lifecycle;

  @override
  Future<void> initialize(
    WindowBootstrapConfiguration configuration,
  ) async {
    await _windowManager.ensureInitialized();
    await _macOsWindow.initialize();
    await _windowManager.prepare(configuration);
    await _macOsWindow.configureTitleBar();
    // Held before the window is visible so no close can bypass shutdown.
    await _windowManager.setPreventClose(preventClose: true);
    await _windowManager.show();
    await _windowManager.focus();
  }

  @override
  Future<void> setPreventClose({required bool preventClose}) =>
      _windowManager.setPreventClose(preventClose: preventClose);

  @override
  Future<void> minimize() => _windowManager.minimize();

  @override
  Future<void> toggleMaximize() async {
    if (await _windowManager.isMaximized()) {
      await _windowManager.unmaximize();
    } else {
      await _windowManager.maximize();
    }
  }

  @override
  Future<void> close() => _windowManager.close();

  /// Releases plugin listeners owned by this adapter.
  Future<void> dispose() => _windowManager.dispose();
}

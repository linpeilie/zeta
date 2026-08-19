import 'package:macos_window_utils/window_manipulator.dart';

import 'package:zeta/app/platform/window_command_adapter.dart';

typedef _WindowAction = Future<void> Function();

/// Production facade over `macos_window_utils`.
final class MacOsWindowManipulatorFacade implements MacOsWindowFacade {
  /// Creates a facade; [enabled] is false on non-macOS platforms.
  MacOsWindowManipulatorFacade({
    required this.enabled,
    Future<void> Function()? initialize,
    Future<void> Function()? enableFullSizeContentView,
    Future<void> Function()? hideTitle,
    Future<void> Function()? makeTitlebarTransparent,
  }) : _initialize = initialize ?? _initializeWindowManipulator,
       _enableFullSizeContentView =
           enableFullSizeContentView ??
           WindowManipulator.enableFullSizeContentView,
       _hideTitle = hideTitle ?? WindowManipulator.hideTitle,
       _makeTitlebarTransparent =
           makeTitlebarTransparent ?? WindowManipulator.makeTitlebarTransparent;

  /// Whether macOS-specific plugin calls should run.
  final bool enabled;
  final _WindowAction _initialize;
  final _WindowAction _enableFullSizeContentView;
  final _WindowAction _hideTitle;
  final _WindowAction _makeTitlebarTransparent;

  @override
  Future<void> configureTitleBar() async {
    if (!enabled) {
      return;
    }
    await _enableFullSizeContentView();
    await _hideTitle();
    await _makeTitlebarTransparent();
  }

  @override
  Future<void> initialize() async {
    if (enabled) {
      await _initialize();
    }
  }
}

Future<void> _initializeWindowManipulator() =>
    WindowManipulator.initialize(enableWindowDelegate: true);

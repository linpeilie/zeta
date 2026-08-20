import 'package:equatable/equatable.dart';

/// Window lifecycle notifications exposed to repositories.
enum WindowLifecycleEvent {
  /// The window gained focus.
  focused,

  /// The window lost focus.
  blurred,

  /// The window was minimized.
  minimized,

  /// The window was restored from a minimized state.
  restored,

  /// The window became maximized.
  maximized,

  /// The window left the maximized state.
  unmaximized,

  /// The platform requested that the window close.
  closeRequested,
}

/// A logical window size without Flutter geometry types.
final class WindowSize extends Equatable {
  /// Creates a logical window size.
  const WindowSize({required this.width, required this.height});

  /// Logical width.
  final double width;

  /// Logical height.
  final double height;

  @override
  List<Object?> get props => [width, height];
}

/// Configuration used before showing the primary desktop window.
final class WindowBootstrapConfiguration extends Equatable {
  /// Creates primary-window configuration.
  const WindowBootstrapConfiguration({
    required this.size,
    required this.minimumSize,
    required this.title,
    this.center = true,
    this.backgroundColorArgb,
  });

  /// Initial logical size.
  final WindowSize size;

  /// Minimum logical size.
  final WindowSize minimumSize;

  /// Native window title.
  final String title;

  /// Whether the native window should be centered.
  final bool center;

  /// Optional 32-bit ARGB frame color.
  final int? backgroundColorArgb;

  @override
  List<Object?> get props => [
    size,
    minimumSize,
    title,
    center,
    backgroundColorArgb,
  ];
}

/// Performs primary-window setup and owns the native close handshake.
///
/// This surface stays separate from [WindowCommandApi] so the close handshake
/// is reachable from the composition root only: a Bloc must never be able to
/// hold the window open.
abstract interface class WindowBootstrapApi {
  /// Initializes plugins, applies [configuration], then shows and focuses.
  ///
  /// Implementations must start holding the native close request before the
  /// window becomes visible, so no close can bypass application shutdown.
  Future<void> initialize(WindowBootstrapConfiguration configuration);

  /// Holds or releases the native close request.
  ///
  /// While held, a close request surfaces as
  /// [WindowLifecycleEvent.closeRequested] instead of closing the window, which
  /// lets the composition root release its resources first.
  Future<void> setPreventClose({required bool preventClose});
}

/// Sends commands to and observes the primary window.
abstract interface class WindowCommandApi {
  /// Minimizes the window.
  Future<void> minimize();

  /// Maximizes or unmaximizes the window.
  Future<void> toggleMaximize();

  /// Closes the window.
  Future<void> close();

  /// Window lifecycle notifications.
  Stream<WindowLifecycleEvent> get lifecycle;
}

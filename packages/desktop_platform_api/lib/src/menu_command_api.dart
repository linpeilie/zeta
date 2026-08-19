import 'package:equatable/equatable.dart';

/// Commands emitted by the native application menu.
enum MenuCommand {
  /// Open a project.
  openProject,
}

/// Localized labels used to configure the native application menu.
final class MenuConfiguration extends Equatable {
  /// Creates a native menu configuration.
  const MenuConfiguration({
    required this.fileMenuLabel,
    required this.openProjectLabel,
  });

  /// Localized File menu label.
  final String fileMenuLabel;

  /// Localized Open Project item label.
  final String openProjectLabel;

  @override
  List<Object?> get props => [fileMenuLabel, openProjectLabel];
}

/// Configures and receives commands from the native application menu.
abstract interface class MenuCommandApi {
  /// Native menu selections.
  Stream<MenuCommand> get commands;

  /// Installs or updates the native File menu.
  Future<bool> configure(MenuConfiguration configuration);

  /// Enables or disables a native command by stable ID.
  Future<void> setMenuEnabled({
    required String commandId,
    required bool enabled,
  });
}

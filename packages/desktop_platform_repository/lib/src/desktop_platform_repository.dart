// Named public dependency parameters intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'dart:typed_data';

import 'package:desktop_platform_api/desktop_platform_api.dart';

/// The platform operation that failed.
enum DesktopPlatformOperation {
  /// Select a directory.
  pickDirectory,

  /// Select one or more files.
  pickFiles,

  /// Copy plain text.
  copyText,

  /// Read plain text.
  readText,

  /// Read image bytes.
  readImage,

  /// Read copied file paths.
  readFilePaths,

  /// Open a directory in the operating system file manager.
  openDirectory,

  /// Minimize the primary window.
  minimize,

  /// Toggle the primary window's maximized state.
  toggleMaximize,

  /// Close the primary window.
  closeWindow,

  /// Configure the native menu.
  configureMenu,

  /// Enable or disable a native menu command.
  setMenuEnabled,
}

/// A typed failure from a desktop platform port.
final class DesktopPlatformException implements Exception {
  /// Creates a platform failure.
  const DesktopPlatformException({
    required this.operation,
    required this.cause,
  });

  /// Failed operation.
  final DesktopPlatformOperation operation;

  /// Original error retained for sanitized diagnostics.
  final Object cause;

  @override
  String toString() => 'DesktopPlatformException($operation)';
}

/// Window commands exposed without leaking the platform port to Bloc code.
final class DesktopWindowCommands {
  /// Creates a window-command facade.
  const DesktopWindowCommands(this._api);

  final WindowCommandApi _api;

  /// Window lifecycle events.
  Stream<WindowLifecycleEvent> get lifecycle => _api.lifecycle;

  /// Minimizes the primary window.
  Future<void> minimize() => _translate(
    DesktopPlatformOperation.minimize,
    _api.minimize,
  );

  /// Toggles the maximized state.
  Future<void> toggleMaximize() => _translate(
    DesktopPlatformOperation.toggleMaximize,
    _api.toggleMaximize,
  );

  /// Closes the primary window.
  Future<void> close() => _translate(
    DesktopPlatformOperation.closeWindow,
    _api.close,
  );
}

/// Native menu commands exposed without leaking the platform port to Bloc code.
final class DesktopMenuCommands {
  /// Creates a native-menu facade.
  const DesktopMenuCommands(this._api);

  final MenuCommandApi _api;

  /// Native menu selections.
  Stream<MenuCommand> get commands => _api.commands;

  /// Installs or updates the localized native menu.
  Future<bool> configure(MenuConfiguration configuration) => _translate(
    DesktopPlatformOperation.configureMenu,
    () => _api.configure(configuration),
  );

  /// Enables or disables a command by stable identifier.
  Future<void> setEnabled({
    required String commandId,
    required bool enabled,
  }) => _translate(
    DesktopPlatformOperation.setMenuEnabled,
    () => _api.setMenuEnabled(commandId: commandId, enabled: enabled),
  );
}

/// Pure-Dart domain boundary for picker, clipboard, window, and native-menu IO.
class DesktopPlatformRepository {
  /// Creates a repository backed by platform-neutral ports.
  DesktopPlatformRepository({
    required DirectoryPickerApi directoryPicker,
    required ClipboardApi clipboard,
    required WindowCommandApi window,
    required MenuCommandApi menu,
    FilePickerApi? filePicker,
    SystemFileManagerApi? fileManager,
  }) : _directoryPicker = directoryPicker,
       _clipboard = clipboard,
       _filePicker = filePicker,
       _fileManager = fileManager,
       windowCommands = DesktopWindowCommands(window),
       menuCommands = DesktopMenuCommands(menu);

  final DirectoryPickerApi _directoryPicker;
  final ClipboardApi _clipboard;
  final FilePickerApi? _filePicker;
  final SystemFileManagerApi? _fileManager;

  /// Window command facade for Bloc consumption.
  final DesktopWindowCommands windowCommands;

  /// Native menu command facade for Bloc consumption.
  final DesktopMenuCommands menuCommands;

  /// Selects a directory, returning `null` when the user cancels.
  Future<String?> pickDirectory({String? initialDirectory}) => _translate(
    DesktopPlatformOperation.pickDirectory,
    () => _directoryPicker.pickDirectory(initialDirectory: initialDirectory),
  );

  /// Selects files, returning an empty list when the user cancels.
  Future<List<String>> pickFiles({
    List<FileTypeFilter> acceptedTypes = const <FileTypeFilter>[],
  }) {
    final filePicker = _filePicker;
    if (filePicker == null) {
      throw StateError('File picker is not configured');
    }
    return _translate(
      DesktopPlatformOperation.pickFiles,
      () => filePicker.pickFiles(acceptedTypes: acceptedTypes),
    );
  }

  /// Copies plain text.
  Future<void> copyText(String text) => _translate(
    DesktopPlatformOperation.copyText,
    () => _clipboard.writeText(text),
  );

  /// Reads plain text when present.
  Future<String?> readText() => _translate(
    DesktopPlatformOperation.readText,
    _clipboard.readText,
  );

  /// Reads image bytes when present.
  Future<Uint8List?> readImage() => _translate(
    DesktopPlatformOperation.readImage,
    _clipboard.readImage,
  );

  /// Reads copied file paths.
  Future<List<String>> readFilePaths() => _translate(
    DesktopPlatformOperation.readFilePaths,
    _clipboard.readFilePaths,
  );

  /// Opens an existing directory in the operating system file manager.
  Future<void> openDirectory(String path) {
    final fileManager = _fileManager;
    if (fileManager == null) {
      throw StateError('System file manager is not configured');
    }
    return _translate(
      DesktopPlatformOperation.openDirectory,
      () => fileManager.openDirectory(path),
    );
  }
}

Future<T> _translate<T>(
  DesktopPlatformOperation operation,
  Future<T> Function() action,
) async {
  try {
    return await action();
  } on Object catch (error) {
    throw DesktopPlatformException(operation: operation, cause: error);
  }
}

import 'package:desktop_platform_api/desktop_platform_api.dart';

/// Injectable facade for directory checks and detached process launches.
abstract interface class SystemFileManagerFacade {
  /// Current operating system identifier.
  String get operatingSystem;

  /// Whether [path] identifies an existing directory.
  Future<bool> directoryExists(String path);

  /// Starts a detached process.
  Future<void> startDetached(String executable, List<String> arguments);
}

/// Implements [SystemFileManagerApi] through an injected IO facade.
final class SystemFileManagerAdapter implements SystemFileManagerApi {
  /// Creates an adapter.
  const SystemFileManagerAdapter(this._facade);

  final SystemFileManagerFacade _facade;

  @override
  Future<void> openDirectory(String path) async {
    if (!await _facade.directoryExists(path)) {
      throw ArgumentError.value(path, 'path', 'Directory does not exist');
    }
    final executable = switch (_facade.operatingSystem) {
      'windows' => 'explorer.exe',
      'macos' => 'open',
      _ => 'xdg-open',
    };
    await _facade.startDetached(executable, <String>[path]);
  }
}

import 'dart:io';

import 'package:zeta/app/platform/system_file_manager_adapter.dart';

/// Production IO facade for the operating system's file manager.
final class IoSystemFileManagerFacade implements SystemFileManagerFacade {
  /// Creates the production facade with injectable IO entrypoints.
  IoSystemFileManagerFacade({
    String? operatingSystem,
    bool Function(String path)? directoryExists,
    Future<void> Function(String executable, List<String> arguments)?
    startDetached,
  }) : _operatingSystem = operatingSystem ?? Platform.operatingSystem,
       _directoryExists = directoryExists ?? _directoryExistsOnDisk,
       _startDetached = startDetached ?? _startDetachedProcess;

  final String _operatingSystem;
  final bool Function(String path) _directoryExists;
  final Future<void> Function(String executable, List<String> arguments)
  _startDetached;

  @override
  String get operatingSystem => _operatingSystem;

  @override
  Future<bool> directoryExists(String path) =>
      Future<bool>.value(_directoryExists(path));

  @override
  Future<void> startDetached(
    String executable,
    List<String> arguments,
  ) async {
    await _startDetached(executable, arguments);
  }
}

bool _directoryExistsOnDisk(String path) => Directory(path).existsSync();

Future<void> _startDetachedProcess(
  String executable,
  List<String> arguments,
) async {
  await Process.start(
    executable,
    arguments,
    mode: ProcessStartMode.detached,
  );
}

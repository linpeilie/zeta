import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:file_selector/file_selector.dart' as file_selector;
import 'package:zeta/app/platform/file_selector_adapter.dart';

/// Injectable `file_selector.openFiles` signature.
typedef FileSelectorOpenFiles = Future<List<file_selector.XFile>> Function({
  List<file_selector.XTypeGroup> acceptedTypeGroups,
});

/// Injectable `file_selector.getDirectoryPath` signature.
typedef FileSelectorGetDirectoryPath = Future<String?> Function({
  String? initialDirectory,
});

/// Production facade over `file_selector` top-level functions.
final class FlutterFileSelectorFacade implements FileSelectorFacade {
  /// Creates a facade with optionally injected plugin entrypoints.
  FlutterFileSelectorFacade({
    FileSelectorOpenFiles? openFiles,
    FileSelectorGetDirectoryPath? getDirectoryPath,
  }) : _openFiles = openFiles ?? file_selector.openFiles,
       _getDirectoryPath = getDirectoryPath ?? file_selector.getDirectoryPath;

  final FileSelectorOpenFiles _openFiles;
  final FileSelectorGetDirectoryPath _getDirectoryPath;

  @override
  Future<String?> getDirectoryPath({String? initialDirectory}) =>
      _getDirectoryPath(initialDirectory: initialDirectory);

  @override
  Future<List<String>> openFiles({
    required List<FileTypeFilter> acceptedTypes,
  }) async {
    final files = await _openFiles(
      acceptedTypeGroups: acceptedTypes
          .map(
            (type) => file_selector.XTypeGroup(
              label: type.label,
              extensions: type.extensions,
              mimeTypes: type.mimeTypes,
              uniformTypeIdentifiers: type.uniformTypeIdentifiers,
            ),
          )
          .toList(growable: false),
    );
    return files.map((file) => file.path).toList(growable: false);
  }
}

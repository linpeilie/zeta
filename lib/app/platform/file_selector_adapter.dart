import 'dart:collection';

import 'package:desktop_platform_api/desktop_platform_api.dart';

/// Injectable facade for the file-selector plugin.
abstract interface class FileSelectorFacade {
  /// Selects files matching [acceptedTypes].
  Future<List<String>> openFiles({
    required List<FileTypeFilter> acceptedTypes,
  });

  /// Selects a directory.
  Future<String?> getDirectoryPath({String? initialDirectory});
}

/// Implements file and directory picker ports through an injected facade.
final class FileSelectorAdapter implements FilePickerApi, DirectoryPickerApi {
  /// Creates an adapter.
  const FileSelectorAdapter(this._facade);

  final FileSelectorFacade _facade;

  @override
  Future<String?> pickDirectory({String? initialDirectory}) =>
      _facade.getDirectoryPath(initialDirectory: initialDirectory);

  @override
  Future<List<String>> pickFiles({
    List<FileTypeFilter> acceptedTypes = const <FileTypeFilter>[],
  }) async {
    final paths = await _facade.openFiles(acceptedTypes: acceptedTypes);
    return UnmodifiableListView<String>(List<String>.of(paths));
  }
}

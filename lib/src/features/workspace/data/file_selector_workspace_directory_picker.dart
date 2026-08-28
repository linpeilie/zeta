import 'package:file_selector/file_selector.dart';

import 'package:zeta/src/features/workspace/domain/workspace_directory_picker.dart';

/// 基于 `file_selector` 的原生目录选择器。
final class FileSelectorWorkspaceDirectoryPicker
    implements WorkspaceDirectoryPicker {
  const FileSelectorWorkspaceDirectoryPicker();

  @override
  Future<String?> pickDirectory() => getDirectoryPath();
}

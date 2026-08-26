import 'package:file_selector/file_selector.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/data/io_workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_tree_notifier.dart';

/// workspace 组合根装配：目录选择器与本机目录 catalog。
List<Override> workspaceOverrides({
  Future<String?> Function()? directoryPicker,
}) {
  return <Override>[
    workspaceDirectoryPickerProvider.overrideWithValue(
      directoryPicker ?? getDirectoryPath,
    ),
    workspaceDirectoryCatalogProvider.overrideWithValue(
      const IoWorkspaceDirectoryCatalog(),
    ),
  ];
}

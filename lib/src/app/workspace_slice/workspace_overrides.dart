import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/data/file_selector_workspace_directory_picker.dart';
import 'package:zeta/src/features/workspace/data/io_workspace_directory_catalog.dart';
import 'package:zeta/src/features/workspace/application/workspace_file_tree_notifier.dart';

/// workspace 组合根装配：本机目录 catalog。
///
/// 目录选择器**不在这里装**：只要 `MainApp` 内部装了它，测试就再也覆盖不了同一个
/// provider（Riverpod 对同容器内的重复 override 直接断言失败）。真实实现改由唯一的
/// 生产入口经 [systemDirectoryPickerOverride] 传进 `MainApp.overrides`。
List<Override> workspaceOverrides() {
  return <Override>[
    workspaceDirectoryCatalogProvider.overrideWithValue(
      const IoWorkspaceDirectoryCatalog(),
    ),
  ];
}

/// 真实系统目录选择器。只有 `lib/main.dart` 装它，测试装 fake。
Override systemDirectoryPickerOverride() {
  return workspaceDirectoryPickerProvider.overrideWithValue(
    const FileSelectorWorkspaceDirectoryPicker(),
  );
}

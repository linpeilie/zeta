import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/features/workspace/application/workspace_notifier.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_picker.dart';

/// 假目录选择器：构造时给定要"选中"的路径，调用时立即返回，不弹原生对话框。
final class FakeWorkspaceDirectoryPicker implements WorkspaceDirectoryPicker {
  /// 每次都返回同一个 [path]。传 null 等价于用户取消。
  FakeWorkspaceDirectoryPicker(String? path)
    : _results = <String?>[path],
      _repeatLast = true;

  /// 用户始终取消。
  FakeWorkspaceDirectoryPicker.cancelled()
    : _results = const <String?>[null],
      _repeatLast = true;

  /// 按顺序返回 [paths]；用完之后继续调用返回 null（等价于取消）。
  FakeWorkspaceDirectoryPicker.sequence(List<String?> paths)
    : _results = List<String?>.of(paths),
      _repeatLast = false;

  final List<String?> _results;
  final bool _repeatLast;

  /// 被调用次数，供"没弹选择器"这类断言使用。
  int callCount = 0;

  @override
  Future<String?> pickDirectory() async {
    final index = callCount;
    callCount += 1;
    if (index < _results.length) {
      return _results[index];
    }
    return _repeatLast && _results.isNotEmpty ? _results.last : null;
  }
}

/// `MainApp.overrides` 用的糖：装一个恒定返回 [path] 的假选择器。
List<Override> fakeDirectoryPickerOverrides(String? path) {
  return fakeDirectoryPickerOverridesOf(FakeWorkspaceDirectoryPicker(path));
}

/// `MainApp.overrides` 用的糖：装入调用方自己持有的 [picker]，便于事后断言。
List<Override> fakeDirectoryPickerOverridesOf(WorkspaceDirectoryPicker picker) {
  return <Override>[workspaceDirectoryPickerProvider.overrideWithValue(picker)];
}

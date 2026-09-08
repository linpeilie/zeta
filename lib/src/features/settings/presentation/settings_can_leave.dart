import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置 Canvas 当前是否允许离开（例如 Agent 配置有未保存修改）。
typedef SettingsCanLeaveCallback = Future<bool> Function();

/// 可变回调槽：initState/dispose 里改字段，不通知 listener，避免 Riverpod 3
/// 禁止在构建期改 provider。
final class SettingsCanLeaveRegistry {
  SettingsCanLeaveCallback? _callback;

  SettingsCanLeaveCallback? get callback => _callback;

  void register(SettingsCanLeaveCallback callback) {
    _callback = callback;
  }

  void unregister(SettingsCanLeaveCallback callback) {
    if (_callback == callback) {
      _callback = null;
    }
  }
}

final settingsCanLeaveRegistryProvider = Provider<SettingsCanLeaveRegistry>(
  (ref) => SettingsCanLeaveRegistry(),
  name: 'settingsCanLeaveRegistry',
);

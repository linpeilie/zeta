import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 设置 Canvas 当前是否允许离开（例如 Agent 配置有未保存修改）。
typedef SettingsCanLeaveCallback = Future<bool> Function();

/// 可变回调槽：initState/dispose 里改字段，不通知 listener，避免 Riverpod 3
/// 禁止在构建期改 provider。
final class SettingsCanLeaveRegistry {
  SettingsCanLeaveCallback? _callback;
  Future<bool>? _confirmation;

  SettingsCanLeaveCallback? get callback => _callback;

  /// 多条导航共享同一次未保存确认；每条请求自行复核是否仍有效。
  Future<bool> confirm() {
    final pending = _confirmation;
    if (pending != null) return pending;
    final future = Future<bool>.sync(() => _callback?.call() ?? true);
    _confirmation = future;
    return future.whenComplete(() {
      if (identical(_confirmation, future)) _confirmation = null;
    });
  }

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

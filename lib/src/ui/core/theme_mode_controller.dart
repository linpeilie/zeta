import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 主题模式偏好：跟随系统 / 浅色 / 深色。
///
/// 默认 [ThemeMode.system]，通过 [SharedPreferences] 持久化。设置面板可调用
/// [setMode] 切换；UI 通过 [listenable] 订阅变化后交给 [MaterialApp] 的
/// `themeMode`。
class ThemeModeController extends ChangeNotifier {
  ThemeModeController({this.preferences});

  static const String _storageKey = 'zeta.theme.mode.v1';

  final SharedPreferencesAsync? preferences;

  ThemeMode _mode = ThemeMode.system;

  /// 当前主题模式。
  ThemeMode get mode => _mode;

  /// 供 [MaterialApp] / [ValueListenableBuilder] 订阅的监听器。
  ValueListenable<ThemeMode> get listenable => _modeNotifier;

  final ValueNotifier<ThemeMode> _modeNotifier = ValueNotifier<ThemeMode>(
    ThemeMode.system,
  );

  /// 从持久化存储加载已保存的偏好；缺失或损坏时回退到 [ThemeMode.system]。
  ///
  /// 未配置 [preferences]（测试场景）时直接保留内存默认值，避免触碰真实
  /// shared_preferences。
  Future<void> load() async {
    final store = preferences;
    if (store == null) {
      return;
    }
    final raw = await store.getString(_storageKey);
    _setMode(_parseMode(raw), notify: false);
  }

  /// 切换主题模式并持久化。
  Future<void> setMode(ThemeMode mode) async {
    if (_mode == mode) {
      return;
    }
    _setMode(mode, notify: true);
    final store = preferences;
    if (store == null) {
      return;
    }
    await store.setString(_storageKey, _encodeMode(mode));
  }

  void _setMode(ThemeMode mode, {required bool notify}) {
    _mode = mode;
    _modeNotifier.value = mode;
    if (notify) {
      notifyListeners();
    }
  }

  static String _encodeMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
  }

  static ThemeMode _parseMode(String? raw) {
    return switch (raw) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      'system' => ThemeMode.system,
      _ => ThemeMode.system,
    };
  }

  @override
  void dispose() {
    _modeNotifier.dispose();
    super.dispose();
  }
}

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

final _log = loggerFor('zeta.settings.general_controller');

/// 加载、发布并持久化全局常规设置。
class GeneralSettingsController extends ChangeNotifier {
  GeneralSettingsController({required this.store});

  final GeneralSettingsStore store;

  GeneralSettings _settings = const GeneralSettings();
  Future<GeneralSettings>? _loadFuture;
  bool _disposed = false;

  final ValueNotifier<GeneralSettings> _settingsNotifier =
      ValueNotifier<GeneralSettings>(const GeneralSettings());

  GeneralSettings get settings => _settings;

  ValueListenable<GeneralSettings> get listenable => _settingsNotifier;

  Future<GeneralSettings> load() {
    final existing = _loadFuture;
    if (existing != null) {
      return existing;
    }
    final future = _loadOnce();
    _loadFuture = future;
    return future;
  }

  /// 更新消息发送快捷键并立即持久化。
  Future<void> setMessageSendShortcut(MessageSendShortcut shortcut) async {
    await load();
    if (_settings.sendMessageShortcut == shortcut) {
      return;
    }
    await _applySettings(_settings.copyWith(sendMessageShortcut: shortcut));
  }

  /// 更新 Agent 系统通知总开关。
  Future<void> setNotificationsEnabled(bool enabled) =>
      _updateNotifications((value) => value.copyWith(enabled: enabled));

  /// 更新 turn 终态通知分类开关。
  Future<void> setTurnTerminalNotificationsEnabled(bool enabled) =>
      _updateNotifications(
        (value) => value.copyWith(turnTerminalEnabled: enabled),
      );

  /// 更新需要用户确认的通知分类开关。
  Future<void> setActionRequiredNotificationsEnabled(bool enabled) =>
      _updateNotifications(
        (value) => value.copyWith(actionRequiredEnabled: enabled),
      );

  Future<void> _updateNotifications(
    AgentNotificationSettings Function(AgentNotificationSettings value) update,
  ) async {
    await load();
    final next = update(_settings.notifications);
    if (next == _settings.notifications) {
      return;
    }
    await _applySettings(_settings.copyWith(notifications: next));
  }

  Future<GeneralSettings> _loadOnce() async {
    _settings = await store.load();
    _notify();
    return _settings;
  }

  Future<void> _applySettings(GeneralSettings value) async {
    _settings = value;
    try {
      await store.save(value);
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist general settings',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _notify();
  }

  void _notify() {
    if (_disposed) {
      return;
    }
    _settingsNotifier.value = _settings;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _settingsNotifier.dispose();
    super.dispose();
  }
}

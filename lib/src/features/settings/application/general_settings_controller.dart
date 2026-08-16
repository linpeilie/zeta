import 'dart:async';

import 'package:flutter/foundation.dart';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/settings/application/general_settings_update_result.dart';
import 'package:zeta/src/features/settings/data/general_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

final _log = loggerFor('zeta.settings.general_controller');

/// 加载、发布并持久化全局常规设置。
class GeneralSettingsController extends ChangeNotifier {
  GeneralSettingsController({required this.store});

  final GeneralSettingsStore store;

  GeneralSettings _settings = const GeneralSettings();
  var _loaded = false;
  var _disposed = false;
  Future<void> _queue = Future<void>.value();

  final ValueNotifier<GeneralSettings> _settingsNotifier =
      ValueNotifier<GeneralSettings>(const GeneralSettings());

  GeneralSettings get settings => _settings;

  ValueListenable<GeneralSettings> get listenable => _settingsNotifier;

  Future<GeneralSettings> load() {
    return _enqueue(() async {
      if (_loaded) {
        return _settings;
      }
      _settings = await store.load();
      _loaded = true;
      _notify();
      return _settings;
    });
  }

  /// 更新消息发送快捷键并立即持久化。
  Future<void> setMessageSendShortcut(MessageSendShortcut shortcut) {
    return _enqueue(() async {
      await _ensureLoaded();
      if (_settings.sendMessageShortcut == shortcut) {
        return;
      }
      await _persistFirst(_settings.copyWith(sendMessageShortcut: shortcut));
    });
  }

  /// 更新下次启动使用的界面语言；当前进程 Locale 不变。
  Future<GeneralSettingsUpdateResult> setAppLanguage(AppLanguage language) {
    return _enqueue(() async {
      await _ensureLoaded();
      if (_settings.appLanguage == language) {
        return GeneralSettingsUpdateResult.unchanged;
      }
      return _persistFirst(_settings.copyWith(appLanguage: language));
    });
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
  ) {
    return _enqueue(() async {
      await _ensureLoaded();
      final next = update(_settings.notifications);
      if (next == _settings.notifications) {
        return;
      }
      await _persistFirst(_settings.copyWith(notifications: next));
    });
  }

  Future<void> _ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _settings = await store.load();
    _loaded = true;
    _notify();
  }

  Future<GeneralSettingsUpdateResult> _persistFirst(
    GeneralSettings value,
  ) async {
    try {
      await store.save(value);
    } catch (error, stackTrace) {
      _log.w(
        'Could not persist general settings',
        error: error,
        stackTrace: stackTrace,
      );
      return GeneralSettingsUpdateResult.persistenceFailed;
    }
    _settings = value;
    _notify();
    return GeneralSettingsUpdateResult.applied;
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _queue = _queue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
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

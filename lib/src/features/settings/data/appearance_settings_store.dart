import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// 外观设置 shared_preferences key。
const String appearanceSettingsStorageKey = 'zeta.appearance.settings.v1';

/// 旧版仅主题模式时的存储 key。
const String legacyThemeModeStorageKey = 'zeta.theme.mode.v1';

/// 外观设置仓库。
abstract class AppearanceSettingsStore {
  Future<AppearanceSettings> load();

  Future<void> save(AppearanceSettings settings);
}

/// 基于 shared_preferences 的生产外观设置仓库。
class SharedPreferencesAppearanceSettingsStore
    implements AppearanceSettingsStore {
  SharedPreferencesAppearanceSettingsStore({
    this.preferences,
    this.readString,
    this.writeString,
  });

  final SharedPreferencesAsync? preferences;
  final Future<String?> Function(String key)? readString;
  final Future<void> Function(String key, String value)? writeString;

  @override
  Future<AppearanceSettings> load() async {
    final value = await _read(appearanceSettingsStorageKey);
    if (value == null || value.isEmpty) {
      return AppearanceSettings.fromLegacyThemeMode(
        await _read(legacyThemeModeStorageKey),
      );
    }
    return _decodeAppearanceSettings(value);
  }

  @override
  Future<void> save(AppearanceSettings settings) async {
    await _write(appearanceSettingsStorageKey, jsonEncode(settings.toJson()));
  }

  Future<String?> _read(String key) {
    final customRead = readString;
    if (customRead != null) {
      return customRead(key);
    }
    return (preferences ?? SharedPreferencesAsync()).getString(key);
  }

  Future<void> _write(String key, String value) {
    final customWrite = writeString;
    if (customWrite != null) {
      return customWrite(key, value);
    }
    return (preferences ?? SharedPreferencesAsync()).setString(key, value);
  }
}

/// 通过回调读写 JSON 的外观设置仓库。
class CallbackAppearanceSettingsStore implements AppearanceSettingsStore {
  const CallbackAppearanceSettingsStore({
    required this.loadJson,
    required this.saveJson,
    this.loadLegacyThemeMode,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;
  final Future<String?> Function()? loadLegacyThemeMode;

  @override
  Future<AppearanceSettings> load() async {
    final value = await loadJson();
    if (value == null || value.isEmpty) {
      return AppearanceSettings.fromLegacyThemeMode(
        await loadLegacyThemeMode?.call(),
      );
    }
    return _decodeAppearanceSettings(value);
  }

  @override
  Future<void> save(AppearanceSettings settings) {
    return saveJson(jsonEncode(settings.toJson()));
  }
}

/// 内存版外观设置仓库。
class MemoryAppearanceSettingsStore implements AppearanceSettingsStore {
  MemoryAppearanceSettingsStore([AppearanceSettings? settings])
    : _settings = settings ?? const AppearanceSettings();

  AppearanceSettings _settings;

  @override
  Future<AppearanceSettings> load() async => _settings;

  @override
  Future<void> save(AppearanceSettings settings) async {
    _settings = settings;
  }
}

AppearanceSettings _decodeAppearanceSettings(String? value) {
  if (value == null || value.isEmpty) {
    return const AppearanceSettings();
  }

  try {
    return AppearanceSettings.tryDecode(jsonDecode(value));
  } catch (_) {
    return const AppearanceSettings();
  }
}

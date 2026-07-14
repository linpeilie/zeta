import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// 外观设置的旧版 shared_preferences key。
const String appearanceSettingsStorageKey = 'zeta.appearance.settings.v1';

/// 旧版仅主题模式时的存储 key。
const String legacyThemeModeStorageKey = 'zeta.theme.mode.v1';

/// 外观设置仓库。
abstract class AppearanceSettingsStore {
  Future<AppearanceSettings> load();

  Future<void> save(AppearanceSettings settings);
}

/// 基于 JSON 文件的生产外观设置仓库。
class FileAppearanceSettingsStore implements AppearanceSettingsStore {
  FileAppearanceSettingsStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;

  @override
  Future<AppearanceSettings> load() async {
    try {
      return _decodeAppearanceSettings(await _storage.read());
    } on IOException {
      // 外观文件不可读时使用默认主题与字体，保证根组件可继续构建。
      return const AppearanceSettings();
    } on FormatException {
      // 外观文件不可读时使用默认主题与字体，保证根组件可继续构建。
      return const AppearanceSettings();
    }
  }

  @override
  Future<void> save(AppearanceSettings settings) async {
    await _storage.write(jsonEncode(settings.toJson()));
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

import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';

/// 外观设置仓库。
abstract class AppearanceSettingsStore {
  Future<AppearanceSettings> load();

  Future<void> save(AppearanceSettings settings);
}

/// 基于 JSON 文件的生产外观设置仓库。
///
/// 具体文件实例（[ZetaTextFile]）由 app 组合层注入；本类只做编解码与宽容回退。
class FileAppearanceSettingsStore implements AppearanceSettingsStore {
  FileAppearanceSettingsStore({required this._storage});

  final ZetaTextFile _storage;

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

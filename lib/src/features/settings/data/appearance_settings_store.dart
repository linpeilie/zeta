import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings_repository.dart';

/// 基于 JSON 文件的外观设置仓库。
///
/// 具体文档实例（[StorageService]）由 app 组合层注入；本类只做编解码与宽容回退，
/// 不缓存。文档格式仍是版本化的 `appearance.json`。
class FileAppearanceSettingsRepository implements AppearanceSettingsRepository {
  FileAppearanceSettingsRepository({required this.storage});

  final StorageService storage;

  @override
  Future<AppearanceSettings> load() async {
    try {
      return _decodeAppearanceSettings(await storage.read());
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
    await storage.write(jsonEncode(settings.toJson()));
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

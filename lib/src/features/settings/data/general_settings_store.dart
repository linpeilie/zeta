import 'dart:convert';
import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/settings/data/general_settings_codec.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 常规设置仓库。
abstract class GeneralSettingsStore {
  Future<GeneralSettings> load();

  Future<void> save(GeneralSettings settings);
}

/// 基于版本化 JSON 文件的常规设置仓库。
class FileGeneralSettingsStore implements GeneralSettingsStore {
  FileGeneralSettingsStore({
    required this._storage,
    required this.fallbackLanguage,
    this.codec = const GeneralSettingsCodec(),
  });

  final StorageService _storage;
  final AppLanguage fallbackLanguage;
  final GeneralSettingsCodec codec;

  @override
  Future<GeneralSettings> load() async {
    try {
      return _decode(await _storage.read());
    } on IOException {
      return GeneralSettings(appLanguage: fallbackLanguage);
    } on FormatException {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
  }

  @override
  Future<void> save(GeneralSettings settings) async {
    await _storage.write(jsonEncode(codec.encode(settings)));
  }

  GeneralSettings _decode(String? value) {
    if (value == null || value.isEmpty) {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
    try {
      return codec.decode(
        jsonDecode(value),
        fallbackLanguage: fallbackLanguage,
      );
    } catch (_) {
      return GeneralSettings(appLanguage: fallbackLanguage);
    }
  }
}

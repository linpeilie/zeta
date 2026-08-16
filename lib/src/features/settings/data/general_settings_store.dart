import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
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
    required File file,
    required this.fallbackLanguage,
    this.codec = const GeneralSettingsCodec(),
  }) : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;
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

/// 内存版常规设置仓库，供测试和无文件宿主使用。
class MemoryGeneralSettingsStore implements GeneralSettingsStore {
  MemoryGeneralSettingsStore([
    GeneralSettings? settings,
    AppLanguage fallbackLanguage = AppLanguage.simplifiedChinese,
  ]) : _settings = settings ?? GeneralSettings(appLanguage: fallbackLanguage);

  GeneralSettings _settings;

  @override
  Future<GeneralSettings> load() async => _settings;

  @override
  Future<void> save(GeneralSettings settings) async {
    _settings = settings;
  }
}

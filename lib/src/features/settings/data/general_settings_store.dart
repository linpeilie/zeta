import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 常规设置仓库。
abstract class GeneralSettingsStore {
  Future<GeneralSettings> load();

  Future<void> save(GeneralSettings settings);
}

/// 基于版本化 JSON 文件的常规设置仓库。
class FileGeneralSettingsStore implements GeneralSettingsStore {
  FileGeneralSettingsStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;

  @override
  Future<GeneralSettings> load() async {
    try {
      return _decodeGeneralSettings(await _storage.read());
    } on IOException {
      return const GeneralSettings();
    } on FormatException {
      return const GeneralSettings();
    }
  }

  @override
  Future<void> save(GeneralSettings settings) async {
    await _storage.write(jsonEncode(settings.toJson()));
  }
}

/// 内存版常规设置仓库，供测试和无文件宿主使用。
class MemoryGeneralSettingsStore implements GeneralSettingsStore {
  MemoryGeneralSettingsStore([GeneralSettings? settings])
    : _settings = settings ?? const GeneralSettings();

  GeneralSettings _settings;

  @override
  Future<GeneralSettings> load() async => _settings;

  @override
  Future<void> save(GeneralSettings settings) async {
    _settings = settings;
  }
}

GeneralSettings _decodeGeneralSettings(String? value) {
  if (value == null || value.isEmpty) {
    return const GeneralSettings();
  }
  try {
    return GeneralSettings.tryDecode(jsonDecode(value));
  } catch (_) {
    return const GeneralSettings();
  }
}

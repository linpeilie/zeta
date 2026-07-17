import 'dart:convert';
import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_index_store.dart';

/// 当前 Zeta 自有存储迁移版本。
const int zetaStorageMigrationVersion = 1;

/// 旧版 Zeta 偏好读取边界。
///
/// 迁移只读取 Zeta 自己的 SharedPreferences key，不访问任何 Agent CLI 目录。
abstract interface class LegacyZetaPreferences {
  Future<String?> getString(String key);
}

/// 基于 shared_preferences 的旧版 Zeta 偏好读取器。
class SharedPreferencesLegacyZetaPreferences implements LegacyZetaPreferences {
  SharedPreferencesLegacyZetaPreferences({
    SharedPreferencesAsync? preferences,
    Future<String?> Function(String key)? asyncReadString,
    Future<String?> Function(String key)? legacyReadString,
  }) : _asyncReadString =
           asyncReadString ??
           (preferences ?? SharedPreferencesAsync()).getString,
       _legacyReadString = legacyReadString ?? _readLegacyPreference;

  final Future<String?> Function(String key) _asyncReadString;
  final Future<String?> Function(String key) _legacyReadString;

  @override
  Future<String?> getString(String key) async {
    final value = await _asyncReadString(key);
    if (value != null) {
      return value;
    }
    // usage_statistics.index.v2 曾使用 SharedPreferences legacy API；桌面端
    // 通常共享同一后端，但显式回退可覆盖插件后端差异和旧缓存。
    return _legacyReadString(key);
  }
}

Future<String?> _readLegacyPreference(String key) async {
  final preferences = await SharedPreferences.getInstance();
  await preferences.reload();
  return preferences.getString(key);
}

/// 一次迁移的可观测结果，主要用于启动日志与单元测试。
class ZetaStorageMigrationResult {
  const ZetaStorageMigrationResult({
    required this.alreadyCompleted,
    this.migratedKeys = const <String>[],
    this.existingTargetKeys = const <String>[],
  });

  /// 启动前是否已存在有效的迁移标记。
  final bool alreadyCompleted;

  /// 本次成功复制到文件的旧版 Zeta key。
  final List<String> migratedKeys;

  /// 因目标文件已存在而跳过的旧版 Zeta key。
  final List<String> existingTargetKeys;
}

/// 将旧 SharedPreferences 中的 Zeta 自有数据一次性复制到 `~/.zeta`。
///
/// 目标文件一旦存在便拥有更高优先级，迁移不会用旧偏好覆盖它。只有全部目标处理
/// 成功后才写 marker；任一文件写入失败时，下次启动可以安全重试。旧偏好保持只读，
/// 便于用户临时降级到旧版 Zeta。
class ZetaStorageMigrator {
  ZetaStorageMigrator({
    required this.paths,
    LegacyZetaPreferences? preferences,
    DateTime Function()? clock,
  }) : _preferences = preferences ?? SharedPreferencesLegacyZetaPreferences(),
       _clock = clock ?? DateTime.now;

  /// 迁移目标的 Zeta 自有路径集合。
  final ZetaDataPaths paths;
  final LegacyZetaPreferences _preferences;
  final DateTime Function() _clock;

  /// 执行幂等迁移；有效 marker 存在时不会再次读取旧偏好。
  Future<ZetaStorageMigrationResult> migrate() async {
    if (await _hasCompletedMarker()) {
      return const ZetaStorageMigrationResult(alreadyCompleted: true);
    }

    await paths.ensureDirectories();
    final migratedKeys = <String>[];
    final existingTargetKeys = <String>[];

    await _copyJsonPreference(
      key: agentProviderConfigStorageKey,
      target: AtomicTextFile(paths.providersFile),
      migratedKeys: migratedKeys,
      existingTargetKeys: existingTargetKeys,
    );
    await _copyAppearance(
      migratedKeys: migratedKeys,
      existingTargetKeys: existingTargetKeys,
    );
    await _copyJsonPreference(
      key: sessionStorageKey,
      target: AtomicTextFile(paths.ideSessionFile),
      migratedKeys: migratedKeys,
      existingTargetKeys: existingTargetKeys,
    );
    await _copyUsageStatisticsIndex(
      migratedKeys: migratedKeys,
      existingTargetKeys: existingTargetKeys,
    );

    final marker = <String, Object?>{
      'version': zetaStorageMigrationVersion,
      'completedAt': _clock().toUtc().toIso8601String(),
      'migratedKeys': migratedKeys,
      'existingTargetKeys': existingTargetKeys,
    };
    await AtomicTextFile(paths.migrationMarkerFile).write(jsonEncode(marker));

    return ZetaStorageMigrationResult(
      alreadyCompleted: false,
      migratedKeys: List<String>.unmodifiable(migratedKeys),
      existingTargetKeys: List<String>.unmodifiable(existingTargetKeys),
    );
  }

  Future<void> _copyAppearance({
    required List<String> migratedKeys,
    required List<String> existingTargetKeys,
  }) async {
    final target = AtomicTextFile(paths.appearanceFile);
    if (await target.file.exists()) {
      existingTargetKeys.add(appearanceSettingsStorageKey);
      return;
    }

    final current = _nonEmpty(
      await _preferences.getString(appearanceSettingsStorageKey),
    );
    if (current != null) {
      await target.write(current);
      migratedKeys.add(appearanceSettingsStorageKey);
      return;
    }

    final legacy = _nonEmpty(
      await _preferences.getString(legacyThemeModeStorageKey),
    );
    if (legacy == null) {
      return;
    }
    final settings = AppearanceSettings.fromLegacyThemeMode(legacy);
    await target.write(jsonEncode(settings.toJson()));
    migratedKeys.add(legacyThemeModeStorageKey);
  }

  Future<void> _copyJsonPreference({
    required String key,
    required AtomicTextFile target,
    required List<String> migratedKeys,
    required List<String> existingTargetKeys,
  }) async {
    if (await target.file.exists()) {
      existingTargetKeys.add(key);
      return;
    }
    final value = _nonEmpty(await _preferences.getString(key));
    if (value == null) {
      return;
    }
    await target.write(value);
    migratedKeys.add(key);
  }

  Future<void> _copyUsageStatisticsIndex({
    required List<String> migratedKeys,
    required List<String> existingTargetKeys,
  }) async {
    final target = AtomicTextFile(paths.usageStatisticsIndexFile);
    if (await target.file.exists()) {
      existingTargetKeys.add(usageStatisticsIndexStorageKey);
      return;
    }
    final value = _nonEmpty(
      await _preferences.getString(usageStatisticsIndexStorageKey),
    );
    if (value == null) {
      return;
    }

    UsageStatisticsIndexSnapshot snapshot;
    try {
      snapshot = UsageStatisticsIndexSnapshot.tryDecode(jsonDecode(value));
    } catch (_) {
      // 派生索引损坏时迁移为空快照，后续统计加载会从 Codex 历史重建。
      snapshot = const UsageStatisticsIndexSnapshot();
    }
    await target.write(jsonEncode(snapshot.toJson()));
    migratedKeys.add(usageStatisticsIndexStorageKey);
  }

  Future<bool> _hasCompletedMarker() async {
    String? encoded;
    try {
      encoded = await AtomicTextFile(paths.migrationMarkerFile).read();
    } on FileSystemException {
      return false;
    } on FormatException {
      return false;
    }
    if (encoded == null || encoded.trim().isEmpty) {
      return false;
    }
    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) {
        return false;
      }
      final rawVersion = decoded['version'];
      final version = switch (rawVersion) {
        int() => rawVersion,
        num() => rawVersion.toInt(),
        String() => int.tryParse(rawVersion),
        _ => null,
      };
      return version != null && version >= zetaStorageMigrationVersion;
    } catch (_) {
      return false;
    }
  }
}

String? _nonEmpty(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : value;
}

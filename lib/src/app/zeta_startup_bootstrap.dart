import 'dart:io';

import 'package:zeta/src/app/storage/zeta_data_file_system.dart';
import 'package:zeta/src/app/zeta_storage_migrator.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/usage_statistics/data/usage_statistics_partition_store.dart';

/// 启动存储编排判定的安装队列。
enum ZetaStorageCohort { fresh, existing }

/// 启动存储编排的可观察结果。
class ZetaStartupBootstrapResult {
  const ZetaStartupBootstrapResult({
    required this.filePersistenceEnabled,
    required this.fallbackLanguage,
    required this.cohort,
  });

  /// 本次是否可以使用 `~/.zeta` 文件持久化。
  final bool filePersistenceEnabled;

  /// 文件缺失、损坏或未知版本时 store 使用的语言。
  final AppLanguage fallbackLanguage;

  /// 只读判定得到的安装队列。
  final ZetaStorageCohort cohort;
}

/// 判定 fresh/existing，升级 marker/general，并给出 store fallback。
class ZetaStartupBootstrap {
  ZetaStartupBootstrap({
    required this.paths,
    required this.firstSystemLanguage,
  });

  final ZetaDataPaths paths;
  final AppLanguage firstSystemLanguage;

  Future<ZetaStartupBootstrapResult> run() async {
    var cohort = ZetaStorageCohort.fresh;
    var fallback = firstSystemLanguage;
    try {
      await ensureZetaDataDirectories(paths);
      cohort = await inspectZetaStorageCohort(paths: paths);
      fallback = cohort == ZetaStorageCohort.existing
          ? AppLanguage.simplifiedChinese
          : firstSystemLanguage;
      await ZetaStorageMigrator(
        paths: paths,
        missingGeneralLanguage: fallback,
      ).migrate();
      return ZetaStartupBootstrapResult(
        filePersistenceEnabled: true,
        fallbackLanguage: fallback,
        cohort: cohort,
      );
    } catch (error, stackTrace) {
      loggerFor('zeta.storage').w(
        'Could not prepare the Zeta data directory',
        error: error,
        stackTrace: stackTrace,
      );
      return ZetaStartupBootstrapResult(
        filePersistenceEnabled: false,
        fallbackLanguage: fallback,
        cohort: cohort,
      );
    }
  }
}

/// 只读判定：有效 marker、已知 target 或旧偏好即 existing。
Future<ZetaStorageCohort> inspectZetaStorageCohort({
  required ZetaDataPaths paths,
  LegacyZetaPreferences? preferences,
}) async {
  final markerVersion = await readZetaStorageMarkerVersion(paths);
  if (markerVersion != null &&
      markerVersion >= zetaStorageExistingCohortMarkerVersion) {
    return ZetaStorageCohort.existing;
  }

  for (final path in <String>[
    paths.providersFilePath,
    paths.appearanceFilePath,
    paths.generalSettingsFilePath,
    paths.ideSessionFilePath,
    paths.usageStatisticsIndexFilePath,
  ]) {
    if (await File(path).exists()) {
      return ZetaStorageCohort.existing;
    }
  }

  final legacyPreferences =
      preferences ?? SharedPreferencesLegacyZetaPreferences();
  for (final key in const <String>[
    agentProviderConfigStorageKey,
    appearanceSettingsStorageKey,
    legacyThemeModeStorageKey,
    sessionStorageKey,
    usageStatisticsIndexStorageKey,
  ]) {
    final value = await legacyPreferences.getString(key);
    if (value != null && value.trim().isNotEmpty) {
      return ZetaStorageCohort.existing;
    }
  }
  return ZetaStorageCohort.fresh;
}

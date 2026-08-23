import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/app/zeta_startup_bootstrap.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/settings/application/app_language_resolver.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/presentation/appearance_theme_mode_mapper.dart';
import 'package:zeta_ui/zeta_ui.dart';

export 'package:zeta/src/app/app.dart' show MainApp;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      final firstLocale = PlatformDispatcher.instance.locales.isEmpty
          ? null
          : PlatformDispatcher.instance.locales.first;
      final firstSystemLanguage = resolveAppLanguageFromFirstSystemLocale(
        languageCode: firstLocale?.languageCode,
        scriptCode: firstLocale?.scriptCode,
        countryCode: firstLocale?.countryCode,
      );
      ZetaDataPaths? dataPaths;
      var fallbackLanguage = firstSystemLanguage;
      Object? pathError;
      StackTrace? pathStackTrace;
      try {
        dataPaths = ZetaDataPaths.fromEnvironment(
          environment: Platform.environment,
          isWindows: Platform.isWindows,
        );
      } catch (error, stackTrace) {
        pathError = error;
        pathStackTrace = stackTrace;
      }
      configureAppLogging(
        logDirectory: dataPaths == null
            ? null
            : Directory(dataPaths.logsDirectoryPath),
      );
      _installGlobalErrorLogging();
      if (pathError != null) {
        loggerFor('zeta.storage').w(
          'Could not resolve the Zeta data directory; persistence is disabled',
          error: pathError,
          stackTrace: pathStackTrace,
        );
      } else if (dataPaths != null) {
        final bootstrap = await _prepareZetaStorage(
          dataPaths,
          firstSystemLanguage,
        );
        fallbackLanguage = bootstrap.fallbackLanguage;
        if (!bootstrap.filePersistenceEnabled) {
          // 避免迁移半途失败后，本次运行用空状态覆盖尚未迁入的旧偏好。
          dataPaths = null;
        }
      }
      await windowManager.ensureInitialized();
      final appearance = await _loadLaunchAppearance(dataPaths);
      await bootstrapDesktopWindow(
        preferredBrightness: resolveBrightnessForThemeMode(
          themeModeForPreference(appearance.themeMode),
        ),
      );
      // 阶段 0：只挂脱敏观察器与指标端口，不迁移任何业务状态到 Riverpod。
      final observability = ZetaObservability.fromEnvironment();
      // 根 `ProviderScope` 在 MainApp 内部，测试 pump MainApp 时无需重复接线。
      runApp(
        MainApp(
          dataPaths: dataPaths,
          initialAppearanceSettings: appearance,
          fallbackLanguage: fallbackLanguage,
          waitForGeneralSettings: true,
          observability: observability,
          // Phase 2：生产全量启用 conversation 切片路径，开始积累真实使用证据。
          // 回退时改回 false 即回到旧 ViewModel 直连路径，无需数据迁移。
          conversationSliceEnabled: true,
          // Phase 3 第 1 批：经显式确认后生产启用 settings 切片，进入三天观察。
          // 回退时改回 false 即恢复旧 controller 直连路径，无需数据迁移。
          settingsSliceEnabled: true,
          // Phase 3 第 2 批：经显式确认后生产启用 Provider 配置/管理切片，
          // 进入中高风险批次观察；回退时改回 false，无需数据迁移。
          providerManagementSliceEnabled: true,
          // Phase 3 第 3 批 3a：经显式确认后生产启用 Project Threads 切片，
          // 进入中风险观察；回退时改回 false，无需数据迁移。
          projectThreadsSliceEnabled: true,
          // Phase 3 第 3 批 3b：先挂默认关闭 flag 做双路径对照；尚未授权生产翻旗。
          usageStatisticsSliceEnabled: false,
        ),
      );
    },
    (error, stackTrace) {
      loggerFor(
        'zeta.app',
      ).e('Unhandled zone error', error: error, stackTrace: stackTrace);
    },
  );
}

Future<AppearanceSettings> _loadLaunchAppearance(ZetaDataPaths? paths) async {
  if (paths == null) {
    return const AppearanceSettings();
  }
  try {
    return await FileAppearanceSettingsStore(
      storage: AtomicTextFile(File(paths.appearanceFilePath)),
    ).load();
  } catch (error, stackTrace) {
    loggerFor('zeta.storage').w(
      'Could not load appearance settings before showing the window',
      error: error,
      stackTrace: stackTrace,
    );
    return const AppearanceSettings();
  }
}

Future<ZetaStartupBootstrapResult> _prepareZetaStorage(
  ZetaDataPaths paths,
  AppLanguage firstSystemLanguage,
) async {
  final result = await ZetaStartupBootstrap(
    paths: paths,
    firstSystemLanguage: firstSystemLanguage,
  ).run();
  return result;
}

void _installGlobalErrorLogging() {
  final log = loggerFor('zeta.app');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.e(
      'Flutter framework error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.e('Unhandled platform error', error: error, stackTrace: stackTrace);
    return true;
  };
}

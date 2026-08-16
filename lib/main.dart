import 'dart:async';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/app/zeta_startup_bootstrap.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/settings/application/app_language_resolver.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/app_theme.dart';

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
        dataPaths = ZetaDataPaths.fromEnvironment();
      } catch (error, stackTrace) {
        pathError = error;
        pathStackTrace = stackTrace;
      }
      configureAppLogging(logDirectory: dataPaths?.logsDirectory);
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
          appearance.themeMode,
        ),
      );
      runApp(
        MainApp(
          dataPaths: dataPaths,
          initialAppearanceSettings: appearance,
          fallbackLanguage: fallbackLanguage,
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
    return await FileAppearanceSettingsStore(file: paths.appearanceFile).load();
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

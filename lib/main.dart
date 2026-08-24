import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zeta_foundation/platform.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/storage/atomic_text_file.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/app/zeta_startup_bootstrap.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
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
      final firstSystemLanguage = ZetaSystemLanguage.getSystemLanguage(
        english: AppLanguage.english,
        simplifiedChinese: AppLanguage.simplifiedChinese,
      );
      ZetaDataPaths? dataPaths = ZetaDataPaths.fromHomeDirectory(
        await ZetaUserDirectory.getUserDirectory(),
        isWindows: Platform.isWindows,
      );
      configureAppLogging(logDirectory: Directory(dataPaths.logsDirectoryPath));
      _installGlobalErrorLogging();
      final bootstrap = await _prepareZetaStorage(dataPaths);
      if (!bootstrap.filePersistenceEnabled) {
        // 存储目录准备失败时，本次运行退回内存状态，避免继续写入不完整的文件存储。
        dataPaths = null;
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
          fallbackLanguage: firstSystemLanguage,
          waitForGeneralSettings: true,
          observability: observability,
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
) async {
  final result = await ZetaStartupBootstrap(paths: paths).run();
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

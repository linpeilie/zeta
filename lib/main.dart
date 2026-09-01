import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';
import 'package:zeta_foundation/platform.dart';

import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/storage/zeta_data_file_system.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/app/workspace_slice/workspace_overrides.dart';
import 'package:zeta/src/app/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/settings/data/appearance_settings_store.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
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
      final dataPaths = ZetaDataPaths.fromHomeDirectory(
        await ZetaUserDirectory.getUserDirectory(),
        isWindows: Platform.isWindows,
      );
      await ensureZetaDataDirectories(dataPaths);
      final storage = ZetaStorageBindings.file(dataPaths);
      configureAppLogging(logDirectory: Directory(dataPaths.logsDirectoryPath));
      _installGlobalErrorLogging();
      await windowManager.ensureInitialized();
      final appearance = await _loadLaunchAppearance(storage.appearance);
      final windowHost = NativeDesktopWindowHost();
      await windowHost.prepareDesktopWindow(
        preferredBrightness: resolveBrightnessForThemeMode(
          themeModeForPreference(appearance.themeMode),
        ),
      );
      // 容器由组合根建，MainApp 只消费——测试同样自己建一份并注入 fake。
      // 窗口宿主必须注入已经 prepare 过的那一份，否则关窗会跳过 shutdown hook。
      final composition = ZetaAppComposition.create(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(windowHost),
          ...storage.providerOverrides,
          settingsFallbackLanguageProvider.overrideWithValue(
            firstSystemLanguage,
          ),
          appearanceSettingsRepositoryOverride(),
          appearanceFontCatalogProvider.overrideWith(
            (ref) => DesktopSystemFontCatalogService(),
          ),
          systemDirectoryPickerOverride(),
          initialAppearanceSettingsProvider.overrideWithValue(appearance),
        ],
      );
      runApp(MainApp(composition: composition));
    },
    (error, stackTrace) {
      loggerFor(
        'zeta.app',
      ).e('Unhandled zone error', error: error, stackTrace: stackTrace);
    },
  );
}

Future<AppearanceSettings> _loadLaunchAppearance(
  StorageService appearanceStorage,
) async {
  try {
    return await FileAppearanceSettingsRepository(
      storage: appearanceStorage,
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

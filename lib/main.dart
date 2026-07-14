import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/app/zeta_storage_migrator.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';

export 'package:zeta/src/app/app.dart' show MainApp;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      ZetaDataPaths? dataPaths;
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
        loggerFor('zeta.storage').warning(
          'Could not resolve the Zeta data directory; persistence is disabled',
          pathError,
          pathStackTrace,
        );
      } else if (dataPaths != null) {
        final storageReady = await _prepareZetaStorage(dataPaths);
        if (!storageReady) {
          // 避免迁移半途失败后，本次运行用空状态覆盖尚未迁入的旧偏好。
          dataPaths = null;
        }
      }
      await windowManager.ensureInitialized();
      await bootstrapDesktopWindow();
      runApp(MainApp(dataPaths: dataPaths));
    },
    (error, stackTrace) {
      loggerFor('zeta.app').severe('Unhandled zone error', error, stackTrace);
    },
  );
}

Future<bool> _prepareZetaStorage(ZetaDataPaths paths) async {
  final log = loggerFor('zeta.storage');
  try {
    await paths.ensureDirectories();
    final result = await ZetaStorageMigrator(paths: paths).migrate();
    if (!result.alreadyCompleted) {
      log.info('Migrated ${result.migratedKeys.length} Zeta storage entries');
    }
    return true;
  } catch (error, stackTrace) {
    // 目录或旧偏好迁移失败不能阻断启动；本次运行改用内存状态，留待下次重试。
    log.warning('Could not prepare the Zeta data directory', error, stackTrace);
    return false;
  }
}

void _installGlobalErrorLogging() {
  final log = loggerFor('zeta.app');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe('Flutter framework error', details.exception, details.stack);
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.severe('Unhandled platform error', error, stackTrace);
    return true;
  };
}

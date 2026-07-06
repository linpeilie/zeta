import 'dart:async';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/window_bootstrap.dart';
import 'package:zeta/src/core/logging/app_logging.dart';

export 'package:zeta/src/app/app.dart' show MainApp;

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await windowManager.ensureInitialized();
      configureAppLogging();
      _installGlobalErrorLogging();
      await bootstrapDesktopWindow();
      runApp(const MainApp());
    },
    (error, stackTrace) {
      loggerFor('zeta.app').severe('Unhandled zone error', error, stackTrace);
    },
  );
}

void _installGlobalErrorLogging() {
  final log = loggerFor('zeta.app');
  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe(
      'Flutter framework error: ${details.exceptionAsString()}',
      details.exception,
      details.stack,
    );
  };
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    log.severe('Unhandled platform error', error, stackTrace);
    return true;
  };
}

import 'dart:async';
import 'dart:developer';

import 'package:bloc/bloc.dart';
import 'package:flutter/widgets.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/app/app.dart';
import 'package:zeta/l10n/l10n.dart';

class AppBlocObserver extends BlocObserver {
  const AppBlocObserver();

  @override
  void onChange(BlocBase<dynamic> bloc, Change<dynamic> change) {
    super.onChange(bloc, change);
    log('onChange(${bloc.runtimeType}, $change)');
  }

  @override
  void onError(BlocBase<dynamic> bloc, Object error, StackTrace stackTrace) {
    log('onError(${bloc.runtimeType}, $error, $stackTrace)');
    super.onError(bloc, error, stackTrace);
  }
}

/// Starts the app with locale-dependent services frozen before the first frame.
Future<void> bootstrap(
  FutureOr<Widget> Function(AppDependencies dependencies) builder, {
  Locale? platformLocale,
  void Function(Widget app) appRunner = runApp,
}) async {
  final binding = WidgetsFlutterBinding.ensureInitialized();
  FlutterError.onError = (details) {
    log(details.exceptionAsString(), stackTrace: details.stack);
  };

  Bloc.observer = const AppBlocObserver();

  final systemLocale = platformLocale ?? binding.platformDispatcher.locale;
  final language = resolveAppLanguageFromFirstSystemLocale(
    languageCode: systemLocale.languageCode,
    scriptCode: systemLocale.scriptCode,
    countryCode: systemLocale.countryCode,
  );
  final frozenLocale = switch (language) {
    AppLanguage.english => const Locale('en'),
    AppLanguage.simplifiedChinese => const Locale.fromSubtags(
      languageCode: 'zh',
      scriptCode: 'Hans',
    ),
  };
  final l10n = lookupAppLocalizations(frozenLocale);
  final dependencies = AppDependencies(
    locale: frozenLocale,
    failureMessages: FailureMessages(l10n),
    desktopNotificationCopyResolver: DesktopNotificationCopyResolver(l10n),
  );

  appRunner(await builder(dependencies));
}

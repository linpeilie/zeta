import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_stable_overlay_handler.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';
import 'package:zeta/src/ui/localization/zeta_shadcn_localizations.dart';

/// 带 App/Global 本地化 delegates 的 Widget 测试宿主。
///
/// 步骤 6 之前生产 [MainApp] 仍不挂这些 delegates；测试可显式指定 [locale]。
Future<void> pumpLocalizedWidget(
  WidgetTester tester, {
  required Widget child,
  Locale locale = const Locale('en'),
  Size size = const Size(800, 600),
  ThemeMode themeMode = ThemeMode.dark,
}) async {
  tester.view.devicePixelRatio = 1;
  await tester.binding.setSurfaceSize(size);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    return tester.binding.setSurfaceSize(null);
  });

  final lightTheme = buildIdeThemeData(
    brightness: Brightness.light,
    uiFontFamily: 'JetBrainsMono',
    codeFontFamily: 'JetBrainsMono',
  );
  final darkTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    uiFontFamily: 'JetBrainsMono',
    codeFontFamily: 'JetBrainsMono',
  );
  final currentTheme = themeMode == ThemeMode.dark ? darkTheme : lightTheme;
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: themeMode,
      lightTheme: lightTheme,
      darkTheme: darkTheme,
      child: sf.ShadcnApp(
        locale: locale,
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: const [
          AppLocalizations.delegate,
          ZetaShadcnLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        popoverHandler: ideStablePopoverOverlayHandler,
        tooltipHandler: ideStablePopoverOverlayHandler,
        menuHandler: ideStablePopoverOverlayHandler,
        theme: buildShadcnTheme(lightTheme),
        darkTheme: buildShadcnTheme(darkTheme),
        materialTheme: buildMaterialTheme(currentTheme),
        themeMode: resolveShadcnThemeMode(themeMode),
        home: sf.Scaffold(child: SizedBox.expand(child: child)),
      ),
    ),
  );
}

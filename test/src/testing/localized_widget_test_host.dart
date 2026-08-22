import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';
import 'package:zeta_ui/zeta_ui.dart';

/// 带 App/Global/Zeta shadcn 本地化 delegates 的 Widget 测试宿主。
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
    IdeUiTextScope(
      catalog: AppZetaUiTextCatalog(lookupAppLocalizations(locale)),
      child: IdeThemeScope(
        themeMode: themeMode,
        lightTheme: lightTheme,
        darkTheme: darkTheme,
        child: sf.ShadcnApp(
          locale: locale,
          supportedLocales: ZetaLocalization.supportedLocales,
          localizationsDelegates: ZetaLocalization.delegates,
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
    ),
  );
}

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/ui/core/ide_stable_overlay_handler.dart';

/// ui/core 组件测试的统一主题与窗口宿主。
Future<void> pumpIdeComponent(
  WidgetTester tester, {
  required Widget child,
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
        locale: ZetaLocalization.simplifiedChinese,
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
  );
}

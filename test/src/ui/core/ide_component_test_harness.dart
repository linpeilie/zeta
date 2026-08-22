import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// ui/core 组件测试的统一主题与窗口宿主。
Future<void> pumpIdeComponent(
  WidgetTester tester, {
  required Widget child,
  Size size = const Size(800, 600),
  ThemeMode themeMode = ThemeMode.dark,
  double uiFontSize = defaultUiFontSize,
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
    uiFontSize: uiFontSize,
  );
  final darkTheme = buildIdeThemeData(
    brightness: Brightness.dark,
    uiFontFamily: 'JetBrainsMono',
    codeFontFamily: 'JetBrainsMono',
    uiFontSize: uiFontSize,
  );
  final currentTheme = themeMode == ThemeMode.dark ? darkTheme : lightTheme;
  await tester.pumpWidget(
    // 与生产一致：设计系统文案由宿主注入，测试才能断言本地化后的无障碍标签。
    IdeUiTextScope(
      catalog: AppZetaUiTextCatalog(
        lookupAppLocalizations(ZetaLocalization.simplifiedChinese),
      ),
      child: IdeThemeScope(
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
    ),
  );
}

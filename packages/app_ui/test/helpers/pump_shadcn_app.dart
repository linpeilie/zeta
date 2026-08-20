import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Pumps components inside matching Material and shadcn themes.
extension PumpShadcnApp on WidgetTester {
  /// Pumps [widget] in a desktop-sized shadcn application.
  Future<void> pumpShadcnApp(
    Widget widget, {
    Brightness brightness = Brightness.light,
    Size size = const Size(800, 600),
  }) async {
    view.devicePixelRatio = 1;
    await binding.setSurfaceSize(size);
    addTearDown(() async {
      view.resetDevicePixelRatio();
      await binding.setSurfaceSize(null);
    });
    final isDark = brightness == Brightness.dark;
    await pumpWidget(
      sf.ShadcnApp(
        popoverHandler: ideStablePopoverOverlayHandler,
        theme: AppTheme.shadcnLight,
        darkTheme: AppTheme.shadcnDark,
        materialTheme: isDark ? AppTheme.dark : AppTheme.light,
        themeMode: isDark ? sf.ThemeMode.dark : sf.ThemeMode.light,
        home: sf.Scaffold(child: Center(child: widget)),
      ),
    );
  }
}

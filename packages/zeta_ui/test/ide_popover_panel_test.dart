import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets('IdePopoverPanel 使用 Composer 同款表面', (tester) async {
    final lightTheme = buildIdeThemeData(brightness: Brightness.light);
    final darkTheme = buildIdeThemeData(brightness: Brightness.dark);
    await tester.pumpWidget(
      IdeThemeScope(
        themeMode: ThemeMode.dark,
        lightTheme: lightTheme,
        darkTheme: darkTheme,
        child: sf.ShadcnApp(
          theme: buildShadcnTheme(lightTheme),
          darkTheme: buildShadcnTheme(darkTheme),
          themeMode: sf.ThemeMode.dark,
          home: const sf.Scaffold(
            child: Center(child: IdePopoverPanel(child: Text('Popover'))),
          ),
        ),
      ),
    );

    final card = tester.widget<PanelCard>(find.byType(PanelCard));
    expect(card.color, IdeColors.dark.panel);
    expect(card.borderColor, IdeColors.dark.border);
    expect(card.borderRadius, IdeRadius.allMedium);
    expect(card.boxShadow, IdeEffects.overlayShadow(Brightness.dark));
    expect(find.byType(sf.Card), findsNothing);
  });
}

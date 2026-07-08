import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/theme_mode_controller.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('title bar settings action opens settings page', (tester) async {
    await _pumpIdeWithSettings(tester);

    expect(
      find.byKey(const ValueKey('titlebar-settings-action')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-page')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-detail-panel')), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-back-button')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-nav-appearance')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-theme-tabs')), findsOneWidget);
    expect(find.text('外观'), findsNWidgets(2));
  });

  testWidgets('returning from settings preserves ide panel state', (
    tester,
  ) async {
    await _pumpIdeWithSettings(tester);

    await tester.tap(find.byKey(const ValueKey('left-projects-action')));
    await tester.pump();
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('settings-page')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-back-button')));
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('settings-page')), findsNothing);
    expect(find.byKey(const ValueKey('projects-panel-card')), findsNothing);
    expect(find.byKey(const ValueKey('agent-pane-host')), findsOneWidget);
  });

  testWidgets('theme selection updates controller and selected option', (
    tester,
  ) async {
    final controller = ThemeModeController();
    await _pumpIdeWithSettings(tester, controller: controller);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.system);
    expect(
      find.byKey(const ValueKey('settings-theme-system-selected-indicator')),
      findsOneWidget,
    );
    expect(find.text('使用系统当前的浅色或深色偏好。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-theme-dark')));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.dark);
    expect(
      find.byKey(const ValueKey('settings-theme-dark-selected-indicator')),
      findsOneWidget,
    );
    expect(find.text('使用深底、高对比度面板和明亮强调色。'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('settings-theme-light')));
    await tester.pumpAndSettle();

    expect(controller.mode, ThemeMode.light);
    expect(
      find.byKey(const ValueKey('settings-theme-light-selected-indicator')),
      findsOneWidget,
    );
    expect(find.text('使用浅底、低对比度边框和绿色强调色。'), findsOneWidget);
  });
}

Future<void> _pumpIdeWithSettings(
  WidgetTester tester, {
  ThemeModeController? controller,
  Size size = const Size(1400, 900),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final themeModeController = controller ?? ThemeModeController();
  final session = MemorySessionStore();
  final provider = FakeAgentProvider();

  await tester.pumpWidget(
    ValueListenableBuilder<ThemeMode>(
      valueListenable: themeModeController.listenable,
      builder: (context, mode, _) {
        return MaterialApp(
          theme: buildIdeTheme(brightness: Brightness.light),
          darkTheme: buildIdeTheme(brightness: Brightness.dark),
          themeMode: mode,
          home: IdeHome(
            directoryPicker: () async => null,
            enableNativeWindowFrame: true,
            showWindowControls: false,
            sessionStore: CallbackIdeSessionStore(
              loadJson: session.load,
              saveJson: session.save,
            ),
            agentProviderFactory: FakeAgentProviderFactory(provider),
            agentProviderConfigStore: MemoryAgentProviderConfigStore(),
            projectLocationOpener: (_) async {},
            themeModeController: themeModeController,
          ),
        );
      },
    ),
  );
  await tester.pump();
}

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/router/pages/settings_route_page.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/settings/presentation/settings_can_leave.dart';
import 'package:zeta/src/features/settings/presentation/settings_page.dart';
import 'package:zeta/src/ui/features/ide/views/global_home_page.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/zeta_test_app.dart';

void main() {
  testWidgets('settings section deep-link shows that section', (tester) async {
    await _pumpShell(tester);

    final router = GoRouter.of(tester.element(find.byType(IdeHome)));
    unawaited(router.push('/settings/appearance'));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SettingsRoutePage), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-appearance-group')),
      findsOneWidget,
    );
    expect(router.state.uri.path, '/settings/appearance');
    expect(tester.takeException(), isNull);
  });

  testWidgets('section switch updates the canvas in place', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-general-group')),
      findsOneWidget,
    );
    final canvas = tester.element(find.byType(SettingsPageCanvas));

    await tester.tap(find.byKey(const ValueKey('settings-nav-appearance')));
    await tester.pump();
    await tester.pump();

    expect(
      find.byKey(const ValueKey('settings-appearance-group')),
      findsOneWidget,
    );
    expect(tester.element(find.byType(SettingsPageCanvas)), same(canvas));
    expect(
      GoRouter.of(
        tester.element(find.byType(SettingsRoutePage)),
      ).state.uri.path,
      '/settings/appearance',
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('onExit blocks leave when canLeave is false', (tester) async {
    await _pumpShell(tester);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pump();
    await tester.pump();

    final container = ProviderScope.containerOf(
      tester.element(find.byType(SettingsRoutePage)),
    );
    container
        .read(settingsCanLeaveRegistryProvider)
        .register(() async => false);

    await tester.tap(find.byKey(const ValueKey('titlebar-back-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SettingsRoutePage), findsOneWidget);
    expect(find.byKey(const ValueKey('settings-nav-panel')), findsOneWidget);

    container.read(settingsCanLeaveRegistryProvider).register(() async => true);
    await tester.tap(find.byKey(const ValueKey('titlebar-back-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SettingsRoutePage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning from settings keeps the shell content State', (
    tester,
  ) async {
    await _pumpShell(tester);

    final home = tester.element(find.byType(GlobalHomePage));
    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SettingsRoutePage), findsOneWidget);
    expect(home.mounted, isTrue);
    expect(TickerMode.valuesOf(home).enabled, isTrue);

    await tester.tap(find.byKey(const ValueKey('titlebar-back-action')));
    await tester.pump();
    await tester.pump();

    expect(find.byType(SettingsRoutePage), findsNothing);
    expect(tester.element(find.byType(GlobalHomePage)), same(home));
    expect(tester.takeException(), isNull);
  });
}

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  await tester.pumpWidget(
    zetaTestApp(
      overrides: <Override>[
        zetaWindowHostProvider.overrideWithValue(
          NativeDesktopWindowHost(showsWindowControls: false),
        ),
        ideSessionStoreProvider.overrideWithValue(MemorySessionStore(null)),
        agentProviderBundleFactoryProvider.overrideWithValue(
          FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
        ),
        agentProviderConfigStoreProvider.overrideWithValue(
          MemoryAgentProviderConfigStore(),
        ),
      ],
    ),
  );
  await tester.pump();
  await pumpUntilCondition(
    tester,
    () => find
        .byKey(const ValueKey('titlebar-settings-action'))
        .evaluate()
        .isNotEmpty,
    failureMessage: 'Settings title-bar action did not appear',
  );
}

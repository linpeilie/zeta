import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../testing/ide_test_harness.dart';

void main() {
  testWidgets('already-migrated IdeHome chrome follows the pumped locale', (
    tester,
  ) async {
    await _pumpIdeHome(tester);
    await tester.pump();

    expect(find.byType(IdeHome), findsOneWidget);
    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    expect(find.text('已安装 Provider'), findsOneWidget);
    expect(find.text('打开项目'), findsOneWidget);
    expect(find.text('Welcome to Zeta'), findsNothing);
    expect(find.text('Installed providers'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pump();

    expect(find.text('常规'), findsOneWidget);
    expect(find.text('外观'), findsOneWidget);
    expect(find.text('Agent 管理'), findsOneWidget);
    expect(find.text('General'), findsNothing);
    expect(find.text('Appearance'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-nav-agents')));
    await tester.pump();
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-management-page')), findsOneWidget);
    expect(find.text('已安装'), findsWidgets);
    expect(find.text('全部支持'), findsOneWidget);
    expect(find.text('自动检测 Agent'), findsOneWidget);
    expect(find.text('Installed'), findsNothing);
    expect(find.text('All supported'), findsNothing);
    expect(find.text('Auto-detect Agents'), findsNothing);
  });

  testWidgets('English IdeHome override only changes migrated Zeta chrome', (
    tester,
  ) async {
    await _pumpIdeHome(tester, language: AppLanguage.english);
    await tester.pump();

    expect(find.text('Welcome to Zeta'), findsOneWidget);
    expect(find.text('Installed providers'), findsOneWidget);
    expect(find.text('Open project'), findsOneWidget);
    expect(find.text('欢迎使用 Zeta'), findsNothing);
    expect(find.text('已安装 Provider'), findsNothing);
    expect(find.text('打开项目'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('titlebar-settings-action')));
    await tester.pump();

    expect(find.text('General'), findsOneWidget);
    expect(find.text('Appearance'), findsOneWidget);
    expect(find.text('Agent management'), findsOneWidget);
    expect(find.text('常规'), findsNothing);
    expect(find.text('外观'), findsNothing);
    expect(find.text('Agent 管理'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('settings-nav-agents')));
    await tester.pump();
    await tester.pump();

    expect(find.text('Installed'), findsWidgets);
    expect(find.text('All supported'), findsOneWidget);
    expect(find.text('Auto-detect Agents'), findsOneWidget);
    expect(find.text('已安装'), findsNothing);
    expect(find.text('全部支持'), findsNothing);
    expect(find.text('自动检测 Agent'), findsNothing);
  });

  testWidgets('provider names stay literal while status labels follow locale', (
    tester,
  ) async {
    final providerKey = const ValueKey<String>('global-home-provider-codex');

    await _pumpIdeHome(
      tester,
      homeProviderDetectionLoader: () async => <ManagedAgent>[
        _installedAgent(AgentDefinition.codex),
      ],
    );
    await pumpUntilCondition(
      tester,
      () => find.byKey(providerKey).evaluate().isNotEmpty,
      failureMessage: 'Installed provider did not appear on Chinese home',
    );

    expect(find.text('欢迎使用 Zeta'), findsOneWidget);
    // 品牌名与厂商名是标识符，不随语言变；状态标签才走 ARB。
    expect(find.text('Codex'), findsOneWidget);
    expect(find.textContaining('OpenAI'), findsOneWidget);
    expect(find.text('可用'), findsOneWidget);
    expect(find.text('Available'), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await _pumpIdeHome(
      tester,
      language: AppLanguage.english,
      homeProviderDetectionLoader: () async => <ManagedAgent>[
        _installedAgent(AgentDefinition.codex),
      ],
    );
    await pumpUntilCondition(
      tester,
      () => find.byKey(providerKey).evaluate().isNotEmpty,
      failureMessage: 'Installed provider did not appear on English home',
    );

    expect(find.text('Welcome to Zeta'), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.textContaining('OpenAI'), findsOneWidget);
    expect(find.text('Available'), findsOneWidget);
    expect(find.text('可用'), findsNothing);
  });
}

Future<void> _pumpIdeHome(
  WidgetTester tester, {
  AppLanguage? language,
  Future<List<ManagedAgent>> Function()? homeProviderDetectionLoader,
}) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });

  final session = MemorySessionStore(null);
  await tester.pumpWidget(
    MainApp(
      enableNativeWindowFrame: true,
      showWindowControls: false,
      sessionLoader: session.load,
      sessionSaver: session.save,
      agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
        FakeAgentProvider(),
      ),
      agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      homeProviderDetectionLoader: homeProviderDetectionLoader,
      displayLanguageOverride: language,
      agentUsagePanelRepository: const _EmptyAgentUsageRepository(),
    ),
  );
  await tester.pump(const Duration(milliseconds: 1));
  await tester.idle();
  await tester.pump();
}

ManagedAgent _installedAgent(AgentDefinition definition) {
  return ManagedAgent.forDefinition(
    definition: definition,
    enabled: true,
  ).copyWith(
    installationState: AgentInstallationState.installed,
    runtimeState: AgentRuntimeState.idle,
    currentVersion: '1.0.0',
  );
}

class _EmptyAgentUsageRepository implements AgentUsagePanelRepository {
  const _EmptyAgentUsageRepository();

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async =>
      const <AgentUsagePanelProvider>[];

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    return null;
  }
}

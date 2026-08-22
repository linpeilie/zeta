import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_configuration_editor.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/ide_test_harness.dart';

/// 按字段名定位一条 [IdeKeyValueRow]。
Finder _keyValueRowFor(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(IdeKeyValueRow));

void main() {
  testWidgets('renders list and opens responsive Codex detail page', (
    tester,
  ) async {
    final harness = _ManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(
      tester,
      controller: harness.managementController,
      size: const Size(680, 760),
    );

    expect(find.byKey(const ValueKey('agent-management-page')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-row-codex')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-detect-button')), findsOneWidget);
    expect(find.text('Codex'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-list')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-provider-icon-svg-codex')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-row-status-compact')),
      findsOneWidget,
    );
    // 去卡片化的回归锁：列表页不再有 IdeToolbar 条带，也不再被 pane 表面框住。
    expect(find.byType(IdeToolbar), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is IdeSurface && widget.level == IdeSurfaceLevel.pane,
      ),
      findsNothing,
    );
    // 整行可点击已由 hover 高亮表达，右端不再画指向箭头。
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-row-codex')));
    await tester.pump();

    expect(
      find.byKey(const ValueKey('agent-detail-back-button')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-test-connection-button')),
      findsOneWidget,
    );
    expect(find.text('基础信息'), findsWidgets);
    expect(find.text('模型'), findsOneWidget);
    expect(find.text('配置'), findsOneWidget);
    expect(find.byType(IdeSection), findsNWidgets(2));
    expect(tester.takeException(), isNull);
  });

  testWidgets('详情页键值对同行阅读且机器数据走等宽', (tester) async {
    final harness = _ManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(
      tester,
      controller: harness.managementController,
      size: const Size(1280, 900),
    );
    await tester.tap(find.byKey(const ValueKey('agent-row-codex')));
    await tester.pump();

    expect(find.byType(IdeKeyValueRow), findsWidgets);

    // Key 与 Value 必须在同一条水平线上——这正是重构要消灭的「Z」形动线。
    final nameRow = find.ancestor(
      of: find.text('名称'),
      matching: find.byType(IdeKeyValueRow),
    );
    expect(nameRow, findsOneWidget);
    final labelBox = tester.getRect(
      find.descendant(of: nameRow, matching: find.text('名称')),
    );
    final valueBox = tester.getRect(
      find.descendant(of: nameRow, matching: find.text('Codex')),
    );
    expect((labelBox.top - valueBox.top).abs(), lessThan(1));
    // 值紧跟 Key 起排：Key 列宽 92 + 间隙 8，视线只需横移这一段。
    expect(
      valueBox.left - labelBox.left,
      IdeMetrics.keyValueLabelWidth + IdeSpacing.space8,
    );

    // 排版分工：名称/版本这类机器数据走等宽，厂商这类人类文案走 UI 字体。
    String fontOf(String label, String value) => tester
        .widget<Text>(
          find.descendant(
            of: _keyValueRowFor(label),
            matching: find.text(value),
          ),
        )
        .style!
        .fontFamily!;

    final identifierFont = fontOf('名称', 'Codex');
    expect(fontOf('启动命令', 'codex'), identifierFont);
    expect(fontOf('通信协议', 'JSON-RPC'), identifierFont);
    expect(fontOf('厂商', 'OpenAI'), isNot(identifierFont));
    expect(tester.takeException(), isNull);
  });

  testWidgets('wide Agent rows keep neutral status columns', (tester) async {
    final harness = _ManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(tester, controller: harness.managementController);

    expect(find.byKey(const ValueKey('agent-row-status-wide')), findsOneWidget);
    expect(find.byType(StateLabel), findsNothing);
    expect(find.byIcon(Icons.chevron_right_rounded), findsNothing);

    // 三个状态列等宽：宽度一旦按内容浮动，相邻两行的列轴就会错开。
    final statusRow = find.byKey(const ValueKey('agent-row-status-wide'));
    final columns = tester
        .widgetList<SizedBox>(
          find.descendant(of: statusRow, matching: find.byType(SizedBox)),
        )
        .where((box) => box.width != null && box.child != null)
        .map((box) => box.width!)
        .toList(growable: false);
    expect(columns.where((width) => width == 96).length, 3);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'Claude quota details enhancement defaults on and can be disabled',
    (tester) async {
      final harness = _ClaudeManagementHarness.create();
      addTearDown(harness.dispose);
      await tester.runAsync(harness.managementController.initialize);

      await _pumpManagementPage(
        tester,
        controller: harness.managementController,
      );
      expect(find.text('Claude'), findsOneWidget);
      expect(
        find.byKey(
          const ValueKey<String>('agent-provider-icon-svg-claude_code'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
      await tester.pump();

      final switchFinder = find.byKey(
        const ValueKey('claude-account-data-enrichment-switch'),
      );
      await tester.ensureVisible(switchFinder);
      await tester.pump();
      expect(find.text('额度详情增强'), findsOneWidget);
      expect(find.text('OAuth 凭据 · Usage REST'), findsOneWidget);
      expect(find.textContaining('模型列表与套餐名称始终来自 Claude CLI'), findsOneWidget);
      expect(find.textContaining('claude auth login'), findsOneWidget);
      expect(find.textContaining('claude login'), findsNothing);
      expect(tester.widget<IdeSwitch>(switchFinder).value, isTrue);
      expect(tester.widget<IdeSwitch>(switchFinder).onChanged, isNotNull);

      await tester.runAsync(
        () => harness.managementController
            .setClaudeCodeAccountDataEnrichmentEnabled(false),
      );
      await tester.pump();

      final disabledConfig = harness.providerController.providerConfigById(
        defaultClaudeCodeProviderId,
      );
      expect(
        disabledConfig?.extra[claudeCodeAccountDataEnrichmentKey],
        isFalse,
      );
      expect(tester.widget<IdeSwitch>(switchFinder).value, isFalse);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Claude legacy false keeps quota details enhancement disabled', (
    tester,
  ) async {
    final harness = _ClaudeManagementHarness.create(
      accountDataEnrichmentEnabled: false,
    );
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(tester, controller: harness.managementController);
    await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
    await tester.pump();

    final switchFinder = find.byKey(
      const ValueKey('claude-account-data-enrichment-switch'),
    );
    await tester.ensureVisible(switchFinder);
    await tester.pump();

    expect(tester.widget<IdeSwitch>(switchFinder).value, isFalse);
    expect(
      harness.providerController
          .providerConfigById(defaultClaudeCodeProviderId)
          ?.extra[claudeCodeAccountDataEnrichmentKey],
      isFalse,
    );
    expect(find.textContaining('模型列表与套餐名称始终来自 Claude CLI'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Claude connection test confirms no-Prompt initialize effects', (
    tester,
  ) async {
    final harness = _ClaudeManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(tester, controller: harness.managementController);
    await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
    await tester.pump();

    final testButton = find.byKey(
      const ValueKey('agent-test-connection-button'),
    );
    await tester.tap(testButton);
    await tester.pumpAndSettle();

    expect(find.text('测试 Claude Code 连接'), findsOneWidget);
    expect(find.textContaining('无 Prompt'), findsOneWidget);
    expect(find.textContaining('不调用模型'), findsOneWidget);
    expect(find.textContaining('bootstrap 缓存'), findsOneWidget);
    expect(find.textContaining('可能产生少量模型用量'), findsNothing);
    expect(harness.repository.testConnectionCalls, 0);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(harness.repository.testConnectionCalls, 0);

    await tester.tap(testButton);
    await tester.pumpAndSettle();
    await tester.tap(find.text('继续测试'));
    await tester.pumpAndSettle();

    expect(harness.repository.testConnectionCalls, 1);
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  testWidgets(
    'Claude logged-out evidence remains visible after initialize succeeds',
    (tester) async {
      final harness = _ClaudeManagementHarness.create(
        accountState: AgentAccountState.loggedOut,
        accountLabel: '未检测到 Claude.ai OAuth 或 API key 登录证据',
      );
      addTearDown(harness.dispose);
      await tester.runAsync(harness.managementController.initialize);
      await tester.runAsync(harness.managementController.detect);

      await _pumpManagementPage(
        tester,
        controller: harness.managementController,
      );
      await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
      await tester.pump();

      expect(
        find.text('未检测到 Claude.ai OAuth 或 API key 登录证据'),
        findsNWidgets(2),
      );
      final testButton = find.byKey(
        const ValueKey('agent-test-connection-button'),
      );
      await tester.tap(testButton);
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续测试'));
      await tester.pumpAndSettle();

      expect(harness.repository.testConnectionCalls, 1);
      expect(find.text('未检测到 Claude.ai OAuth 或 API key 登录证据'), findsOneWidget);
      expect(
        find.text('Claude Code initialize 成功，CLI 与当前认证路径可用。'),
        findsOneWidget,
      );
      expect(find.text('连接可用'), findsOneWidget);
      expect(find.text('连接正常'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    },
  );

  testWidgets('edits, validates, and safely saves Codex TOML configuration', (
    tester,
  ) async {
    final harness = _ManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);
    final config = File(harness.repository.configPath);
    config.writeAsStringSync('model = "old"\n');
    await tester.runAsync(harness.managementController.loadConfiguration);

    await _pumpManagementPage(tester, controller: harness.managementController);
    await tester.tap(find.byKey(const ValueKey('agent-row-codex')));
    await tester.pump();
    await tester.tap(find.text('配置'));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pump();

    expect(find.byKey(const ValueKey('agent-config-editor')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('agent-config-reveal-button')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('agent-config-editor')),
      'model = "new"\n',
    );
    await tester.pump();
    expect(
      tester
          .widget<sf.TextField>(
            find.byKey(const ValueKey('agent-config-editor')),
          )
          .controller
          ?.text,
      'model = "new"\n',
    );
    final saveButton = find.byKey(const ValueKey('agent-config-save-button'));
    await tester.ensureVisible(saveButton);
    await tester.pump();
    expect(tester.widget<sf.PrimaryButton>(saveButton).onPressed, isNotNull);
    FocusManager.instance.primaryFocus?.unfocus();
    tester.testTextInput.hide();
    await tester.pump();
    final editorState = tester.state<AgentConfigurationEditorState>(
      find.byType(AgentConfigurationEditor),
    );
    await tester.runAsync(editorState.save);
    await tester.pump();

    expect(config.readAsStringSync(), 'model = "new"\n');
    expect(
      config.parent.listSync().whereType<File>().any(
        (file) => file.path.contains('.zeta-backup-'),
      ),
      isTrue,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 600));
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}

class _ManagementHarness {
  _ManagementHarness({
    required this.root,
    required this.repository,
    required this.providerController,
    required this.managementController,
    required this._registry,
  });

  final Directory root;
  final CodexAgentManagementRepository repository;
  final AgentProviderSettingsController providerController;
  final AgentManagementController managementController;
  final AgentProviderRuntimeRegistry _registry;

  static _ManagementHarness create() {
    final root = Directory.systemTemp.createTempSync(
      'zeta-agent-management-widget-',
    );
    final provider = FakeAgentProvider();
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
    );
    final providerController = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(
              extra: <String, Object?>{
                'cliPath': Platform.isWindows
                    ? r'C:\tools\codex.exe'
                    : '/usr/local/bin/codex',
                'detectedCurrentVersion': '0.130.0',
                'detectedLatestVersion': '0.131.0',
                'detectedAccountState': 'loggedIn',
                'lastDetectedAt': DateTime.now().toIso8601String(),
              },
            ),
          ],
        ),
      ),
    );
    final repository = CodexAgentManagementRepository(
      runtimeRegistry: registry,
      codexHomeProvider: () => root.path,
    );
    final managementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        AgentDefinition.codex.id: repository,
      },
      providerController: providerController,
    );
    return _ManagementHarness(
      root: root,
      repository: repository,
      providerController: providerController,
      managementController: managementController,
      registry: registry,
    );
  }

  Future<void> dispose() async {
    managementController.dispose();
    providerController.dispose();
    await _registry.close();
    for (var attempt = 0; attempt < 5 && await root.exists(); attempt++) {
      try {
        await root.delete(recursive: true);
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  }
}

class _ClaudeManagementHarness {
  _ClaudeManagementHarness({
    required this.repository,
    required this.providerController,
    required this.managementController,
    required this._registry,
  });

  final _FakeClaudeManagementRepository repository;
  final AgentProviderSettingsController providerController;
  final AgentManagementController managementController;
  final AgentProviderRuntimeRegistry _registry;

  static _ClaudeManagementHarness create({
    bool? accountDataEnrichmentEnabled,
    AgentAccountState accountState = AgentAccountState.loggedIn,
    String? accountLabel,
  }) {
    final provider = FakeAgentProvider();
    final repository = _FakeClaudeManagementRepository(
      accountState: accountState,
      accountLabel: accountLabel,
    );
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderBundleBuilder.fromFake(provider),
    );
    final providerController = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultClaudeCode.copyWith(
              extra: <String, Object?>{
                'cliPath': Platform.isWindows
                    ? r'C:\tools\claude.exe'
                    : '/usr/local/bin/claude',
                'detectedCurrentVersion': '2.1.224',
                'detectedAccountState': accountState.name,
                'lastDetectedAt': DateTime.utc(2026, 8, 11).toIso8601String(),
                claudeCodeAccountDataEnrichmentKey:
                    ?accountDataEnrichmentEnabled,
              },
            ),
          ],
          activeProviderId: defaultClaudeCodeProviderId,
        ),
      ),
    );
    final managementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        defaultClaudeCodeProviderId: repository,
      },
      providerController: providerController,
    );
    return _ClaudeManagementHarness(
      repository: repository,
      providerController: providerController,
      managementController: managementController,
      registry: registry,
    );
  }

  Future<void> dispose() async {
    managementController.dispose();
    providerController.dispose();
    await _registry.close();
  }
}

class _FakeClaudeManagementRepository implements AgentCliManagementRepository {
  _FakeClaudeManagementRepository({
    this.accountState = AgentAccountState.loggedIn,
    this.accountLabel,
  });

  final AgentAccountState accountState;
  final String? accountLabel;
  int testConnectionCalls = 0;

  @override
  String get agentId => defaultClaudeCodeProviderId;

  @override
  String get configPath => '/test-user/.claude/settings.json';

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    return ManagedAgent.claudeCode(enabled: enabled).copyWith(
      installationState: AgentInstallationState.installed,
      accountState: accountState,
      accountLabel: accountLabel,
      currentVersion: '2.1.224',
    );
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    testConnectionCalls += 1;
    return (
      AgentConnectionTestResult(
        success: true,
        testedAt: DateTime.utc(2026, 8, 11),
        elapsed: const Duration(milliseconds: 5),
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
        message: 'Claude Code initialize 成功，CLI 与当前认证路径可用。',
        protocolVersion: 'stream-json',
        agentName: 'Claude Code',
        agentVersion: '2.1.224',
      ),
      const <AgentModelInfo>[],
    );
  }

  @override
  Future<AgentProviderConfig> providerConfigForPath({
    required AgentProviderConfig current,
    required String path,
  }) async => current.copyWith(command: path);

  @override
  Future<AgentConfigurationDocument> readConfiguration() async {
    return AgentConfigurationDocument(
      path: configPath,
      format: 'JSON',
      content: '',
      maskedContent: '',
      exists: false,
      loadedAt: DateTime.utc(2026, 8, 11),
      signature: 'missing',
    );
  }

  @override
  String? validateConfiguration(String content) => null;

  @override
  Future<AgentConfigurationSaveResult> saveConfiguration({
    required AgentConfigurationDocument original,
    required String content,
    bool overwriteExternalChanges = false,
  }) async => AgentConfigurationSaveResult(document: original);

  @override
  Future<List<String>> discoverLogPaths() async => const <String>[];

  @override
  Future<List<AgentLogEntry>> readLogs(
    List<String> paths, {
    int maxLines = 1000,
  }) async => const <AgentLogEntry>[];
}

Future<void> _pumpManagementPage(
  WidgetTester tester, {
  required AgentManagementController controller,
  Size size = const Size(1200, 820),
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final ideTheme = buildIdeThemeData(
    brightness: Brightness.light,
    codeFontFamily: 'JetBrainsMono',
  );
  await tester.pumpWidget(
    IdeThemeScope(
      themeMode: ThemeMode.light,
      lightTheme: ideTheme,
      darkTheme: buildIdeThemeData(
        brightness: Brightness.dark,
        codeFontFamily: 'JetBrainsMono',
      ),
      child: sf.ShadcnApp(
        locale: ZetaLocalization.simplifiedChinese,
        supportedLocales: ZetaLocalization.supportedLocales,
        localizationsDelegates: ZetaLocalization.delegates,
        theme: buildShadcnTheme(ideTheme),
        materialTheme: buildMaterialTheme(ideTheme),
        home: sf.Scaffold(
          child: AgentManagementPage(controller: controller, autoDetect: false),
        ),
      ),
    ),
  );
  await tester.pump();
}

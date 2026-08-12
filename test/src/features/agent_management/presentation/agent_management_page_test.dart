import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/data/codex_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_cli_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_configuration_editor.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_section.dart';
import 'package:zeta/src/ui/core/workbench/ide_toolbar.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../testing/ide_test_harness.dart';

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
    expect(find.byType(IdeToolbar), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-list-pane')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('agent-provider-icon-svg-codex')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-row-status-compact')),
      findsOneWidget,
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is IdeSurface && widget.level == IdeSurfaceLevel.pane,
      ),
      findsOneWidget,
    );

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

  testWidgets('wide Agent rows keep neutral status columns', (tester) async {
    final harness = _ManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(harness.managementController.initialize);

    await _pumpManagementPage(tester, controller: harness.managementController);

    expect(find.byKey(const ValueKey('agent-row-status-wide')), findsOneWidget);
    expect(find.byType(StateLabel), findsNothing);
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
      expect(tester.widget<sf.Switch>(switchFinder).value, isTrue);
      expect(tester.widget<sf.Switch>(switchFinder).onChanged, isNotNull);

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
      expect(tester.widget<sf.Switch>(switchFinder).value, isFalse);
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

    expect(tester.widget<sf.Switch>(switchFinder).value, isFalse);
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

  testWidgets('removes every Cursor Agent management entry', (tester) async {
    final harness = _CursorManagementHarness.create();
    addTearDown(harness.dispose);
    await tester.runAsync(
      () => harness.managementController.initialize(autoDetect: true),
    );
    await tester.pump();

    await _pumpManagementPage(tester, controller: harness.managementController);
    expect(find.byKey(const ValueKey('agent-row-cursor')), findsNothing);
    expect(find.textContaining('Cursor'), findsNothing);
    expect(find.text('Beta'), findsNothing);
    expect(find.byKey(const ValueKey('agent-open-logs-button')), findsNothing);
    expect(
      find.byKey(const ValueKey('cursor-config-boundary-notice')),
      findsNothing,
    );
    expect(harness.managementController.agents, isEmpty);
    expect(harness.repository.detectCalls, 0);
    expect(tester.takeException(), isNull);
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
      providerFactory: FakeAgentProviderFactory(provider),
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

class _CursorManagementHarness {
  _CursorManagementHarness({
    required this.repository,
    required this.providerController,
    required this.managementController,
    required this._registry,
  });

  final _FakeCursorManagementRepository repository;
  final AgentProviderSettingsController providerController;
  final AgentManagementController managementController;
  final AgentProviderRuntimeRegistry _registry;

  static _CursorManagementHarness create() {
    final provider = FakeAgentProvider();
    final repository = _FakeCursorManagementRepository();
    final registry = AgentProviderRuntimeRegistry(
      providerFactory: FakeAgentProviderFactory(provider),
    );
    final providerController = AgentProviderSettingsController(
      runtimeRegistry: registry,
      configStore: MemoryAgentProviderConfigStore(
        AgentProviderSettings(
          providers: <AgentProviderConfig>[
            AgentProviderConfig.defaultCursor.copyWith(enabled: true),
          ],
          activeProviderId: cursorAgentProviderId,
        ),
      ),
    );
    final managementController = AgentManagementController(
      repositories: <String, AgentCliManagementRepository>{
        cursorAgentProviderId: repository,
      },
      providerController: providerController,
    );
    return _CursorManagementHarness(
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
      providerFactory: FakeAgentProviderFactory(provider),
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

class _FakeCursorManagementRepository implements AgentCliManagementRepository {
  int detectCalls = 0;

  @override
  String get agentId => cursorAgentProviderId;

  @override
  String get configPath => '~/.cursor/cli-config.json';

  @override
  Future<ManagedAgent> detect({
    required AgentProviderConfig providerConfig,
    required bool enabled,
    AgentDetectionProgressCallback? onProgress,
  }) async {
    detectCalls += 1;
    return ManagedAgent.forDefinition(
      definition: _retiredCursorDefinition,
      enabled: enabled,
    ).copyWith(
      installationState: AgentInstallationState.installed,
      accountState: AgentAccountState.loggedIn,
      runtimeState: enabled
          ? AgentRuntimeState.notRunning
          : AgentRuntimeState.disabled,
      currentVersion: '1.5.0',
      executablePath: '/usr/local/bin/agent',
      configPath: configPath,
      connectionTest: AgentConnectionTestResult(
        success: true,
        testedAt: DateTime.utc(2026, 7, 14),
        elapsed: const Duration(milliseconds: 10),
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
        protocolVersion: '1',
        agentName: 'Cursor Agent',
      ),
    );
  }

  @override
  Future<(AgentConnectionTestResult, List<AgentModelInfo>)> testConnection({
    required AgentProviderConfig providerConfig,
  }) async {
    return (
      AgentConnectionTestResult(
        success: true,
        testedAt: DateTime.utc(2026, 7, 14),
        elapsed: const Duration(milliseconds: 10),
        cliCallable: true,
        accountValid: true,
        protocolReady: true,
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
      content: '{"mode":"ask"}',
      maskedContent: '{"mode":"ask"}',
      exists: true,
      loadedAt: DateTime.utc(2026, 7, 14),
      signature: 'test',
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

const _retiredCursorDefinition = AgentDefinition(
  id: cursorAgentProviderId,
  displayName: 'Retired Cursor Agent',
  vendor: 'Retired',
  commandName: '',
  protocol: 'unsupported',
  transport: 'none',
  configFormat: 'none',
  defaultConfigRelativePath: '',
  npmPackage: '',
);

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

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_effect.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_configuration_editor.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta_ui/zeta_ui.dart';

void main() {
  testWidgets(
    'cold slice initialization does not invalidate an ancestor during build',
    (tester) async {
      // Arrange
      final runner = _ColdInitializationRunner();
      final providerConfig = defaultClaudeCodeAgentProviderConfig.copyWith(
        extra: const <String, Object?>{},
      );
      final store = AgentManagementSliceStore(
        initialState: AgentManagementSliceState.initial(
          agentsById: <String, ManagedAgent>{
            defaultClaudeCodeProviderId: ManagedAgent.claudeCode(enabled: true)
                .copyWith(
                  installationState: AgentInstallationState.installed,
                  currentVersion: '2.1.224',
                ),
          },
          orderedAgentIds: const <String>[defaultClaudeCodeProviderId],
          capabilitiesByAgentId:
              const <String, AgentCliManagementCapabilities>{},
          providerSettings: AgentProviderSettings(
            providers: <AgentProviderConfig>[providerConfig],
            activeProviderId: defaultClaudeCodeProviderId,
          ),
        ),
        effectRunner: runner,
        configurationNotLoadedMessage: '配置文件尚未加载',
      );
      runner.store = store;
      addTearDown(store.close);

      // Act
      await _pumpSlicePage(
        tester,
        store,
        child: _ManagementListenerHost(store: store),
      );
      await tester.pumpAndSettle();

      // Assert
      expect(tester.takeException(), isNull);
      expect(runner.initializationCalls, 1);
      expect(runner.detectionCalls, 1);
      expect(store.initialized, isTrue);
      expect(
        find.byKey(const ValueKey('agent-row-claude_code')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'slice path preserves detection, connection, logs and typed account option',
    (tester) async {
      // Arrange
      final harness = _SlicePageHarness.create();
      addTearDown(harness.store.close);
      await _pumpSlicePage(tester, harness.store);

      // Act
      await tester.tap(find.byKey(const ValueKey('agent-detect-button')));
      await tester.pumpAndSettle();

      // Assert
      expect(harness.runner.detectionCalls, 1);
      expect(
        find.byKey(const ValueKey('agent-row-claude_code')),
        findsOneWidget,
      );

      // Act
      await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
      await tester.pump();
      final enrichmentSwitch = find.byKey(
        const ValueKey('claude-account-data-enrichment-switch'),
      );
      await tester.ensureVisible(enrichmentSwitch);
      await tester.tap(enrichmentSwitch);
      await tester.pump();

      // Assert
      expect(harness.runner.accountUpdateCalls, 1);
      expect(harness.store.accountDataEnrichmentEnabled, isFalse);

      // Act
      await tester.tap(
        find.byKey(const ValueKey('agent-test-connection-button')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('继续测试'));
      await tester.pumpAndSettle();

      // Assert
      expect(harness.runner.connectionTestCalls, 1);
      expect(find.textContaining('连接测试成功'), findsOneWidget);

      // Act
      await tester.tap(find.byKey(const ValueKey('agent-open-logs-button')));
      await tester.pump();

      // Assert
      expect(harness.runner.logsLoadCalls, 1);
      expect(find.text('sanitized log line'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 600));
    },
  );

  testWidgets(
    'slice path keeps configuration conflict confirmation in Widget',
    (tester) async {
      // Arrange
      final harness = _SlicePageHarness.create(conflictOnFirstSave: true);
      addTearDown(harness.store.close);
      await _pumpSlicePage(tester, harness.store);
      await tester.tap(find.byKey(const ValueKey('agent-row-claude_code')));
      await tester.pump();
      await tester.tap(find.text('配置'));
      await tester.pump();
      await tester.pump();
      await tester.tap(
        find.byKey(const ValueKey('agent-config-reveal-button')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const ValueKey('agent-config-editor')),
        '{"theme":"dark"}',
      );
      await tester.pump();
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();

      // Act
      final editor = tester.state<AgentConfigurationEditorState>(
        find.byType(AgentConfigurationEditor),
      );
      unawaited(editor.save());
      await tester.pumpAndSettle();

      // Assert
      expect(find.text('配置文件已在外部发生修改'), findsOneWidget);
      expect(harness.runner.saveOverwriteValues, <bool>[false]);

      // Act
      await tester.tap(find.text('仍然保存'));
      await tester.pumpAndSettle();

      // Assert
      expect(harness.runner.saveOverwriteValues, <bool>[false, true]);
      expect(harness.store.configuration?.content, '{"theme":"dark"}');
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 3));
      await tester.pump(const Duration(milliseconds: 600));
    },
  );
}

final class _SlicePageHarness {
  _SlicePageHarness({required this.store, required this.runner});

  final AgentManagementSliceStore store;
  final _InteractiveRunner runner;

  factory _SlicePageHarness.create({bool conflictOnFirstSave = false}) {
    final runner = _InteractiveRunner(conflictOnFirstSave: conflictOnFirstSave);
    final providerConfig = defaultClaudeCodeAgentProviderConfig.copyWith(
      extra: const <String, Object?>{},
    );
    final store = AgentManagementSliceStore(
      initialState: AgentManagementSliceState(
        agentsById: <String, ManagedAgent>{
          defaultClaudeCodeProviderId: ManagedAgent.claudeCode(enabled: true)
              .copyWith(
                installationState: AgentInstallationState.installed,
                currentVersion: '2.1.224',
                accountState: AgentAccountState.loggedIn,
                logPaths: const <String>['/tmp/claude.log'],
              ),
        },
        orderedAgentIds: const <String>[defaultClaudeCodeProviderId],
        selectedAgentId: defaultClaudeCodeProviderId,
        capabilitiesByAgentId: const <String, AgentCliManagementCapabilities>{
          defaultClaudeCodeProviderId: AgentCliManagementCapabilities(
            supportsAccountDataEnrichment: true,
          ),
        },
        providerSettings: AgentProviderSettings(
          providers: <AgentProviderConfig>[providerConfig],
          activeProviderId: defaultClaudeCodeProviderId,
        ),
        initialized: true,
      ),
      effectRunner: runner,
      configurationNotLoadedMessage: '配置文件尚未加载',
    );
    runner.store = store;
    return _SlicePageHarness(store: store, runner: runner);
  }
}

final class _InteractiveRunner implements AgentManagementSliceEffectRunner {
  _InteractiveRunner({required this.conflictOnFirstSave});

  final bool conflictOnFirstSave;
  late AgentManagementSliceStore store;
  int detectionCalls = 0;
  int accountUpdateCalls = 0;
  int connectionTestCalls = 0;
  int logsLoadCalls = 0;
  final List<bool> saveOverwriteValues = <bool>[];

  @override
  void run(AgentManagementSliceEffect effect) {
    switch (effect) {
      case ManagementInitializeEffect():
        throw StateError('The test store starts initialized');
      case DetectAgentsEffect():
        detectionCalls += 1;
        final detected = store.agent.copyWith(
          installationState: AgentInstallationState.installed,
          currentVersion: '2.1.224',
          accountState: AgentAccountState.loggedIn,
          logPaths: const <String>['/tmp/claude.log'],
        );
        store.detectionStarted(effect.operationId, defaultClaudeCodeProviderId);
        store.detectionProgressReported(
          effect.operationId,
          defaultClaudeCodeProviderId,
          const AgentDetectionProgress(completed: 1, total: 1, message: 'done'),
          detected,
        );
        store.agentDetected(
          effect.operationId,
          defaultClaudeCodeProviderId,
          detected,
        );
        store.detectionCompleted(effect.operationId);
      case UpdateProviderEnabledEffect():
        store.providerEnabledUpdated(
          effect.operationId,
          effect.agentId,
          effect.enabled,
          store.state.providerSettings,
        );
      case UpdateAccountDataEnrichmentEffect():
        accountUpdateCalls += 1;
        final current = store.state.providerSettings.providers.single;
        final updated = current.copyWith(
          extra: <String, Object?>{
            ...current.extra,
            claudeCodeAccountDataEnrichmentKey: effect.enabled ? null : false,
          }..removeWhere((key, value) => value == null),
        );
        store.accountDataEnrichmentUpdated(
          effect.operationId,
          effect.agentId,
          AgentProviderSettings(
            providers: <AgentProviderConfig>[updated],
            activeProviderId: defaultClaudeCodeProviderId,
          ),
        );
      case TestAgentConnectionEffect():
        connectionTestCalls += 1;
        store.connectionTestSucceeded(
          operationId: effect.operationId,
          agentId: effect.agentId,
          result: AgentConnectionTestResult(
            success: true,
            testedAt: DateTime.utc(2026, 8, 23),
            elapsed: const Duration(milliseconds: 5),
            cliCallable: true,
            accountValid: true,
            protocolReady: true,
          ),
          models: const <AgentModelInfo>[],
          modelSource: 'Claude Code',
          modelsUpdatedAt: DateTime.utc(2026, 8, 23),
        );
      case LoadAgentConfigurationEffect():
        store.configurationLoaded(
          effect.operationId,
          effect.agentId,
          AgentConfigurationDocument(
            path: '/tmp/settings.json',
            format: 'JSON',
            content: '{"theme":"light"}',
            maskedContent: '{"theme":"light"}',
            exists: true,
            loadedAt: DateTime.utc(2026, 8, 23),
            signature: 'original',
          ),
        );
      case SaveAgentConfigurationEffect():
        saveOverwriteValues.add(effect.overwriteExternalChanges);
        if (conflictOnFirstSave && !effect.overwriteExternalChanges) {
          store.configurationSaveFailed(
            effect.operationId,
            effect.agentId,
            const AgentConfigurationConflictException('conflict'),
            StackTrace.current,
          );
          return;
        }
        store.configurationSaved(
          effect.operationId,
          effect.agentId,
          effect.original.signature,
          AgentConfigurationSaveResult(
            document: AgentConfigurationDocument(
              path: effect.original.path,
              format: effect.original.format,
              content: effect.content,
              maskedContent: effect.content,
              exists: true,
              loadedAt: DateTime.utc(2026, 8, 23),
              signature: 'saved',
            ),
          ),
        );
      case LoadAgentLogsEffect():
        logsLoadCalls += 1;
        store.logsLoaded(
          effect.operationId,
          effect.agentId,
          const <String>['/tmp/claude.log'],
          <AgentLogEntry>[
            AgentLogEntry(
              id: 'log-1',
              sourcePath: '/tmp/claude.log',
              message: 'sanitized log line',
              level: AgentLogLevel.info,
              timestamp: DateTime.utc(2026, 8, 23),
            ),
          ],
        );
    }
  }

  @override
  String? validateConfiguration(String agentId, String content) => null;
}

final class _ColdInitializationRunner
    implements AgentManagementSliceEffectRunner {
  late AgentManagementSliceStore store;
  int initializationCalls = 0;
  int detectionCalls = 0;

  @override
  void run(AgentManagementSliceEffect effect) {
    switch (effect) {
      case ManagementInitializeEffect():
        initializationCalls += 1;
        store.initializationSucceeded(
          effect.operationId,
          store.state.providerSettings,
          store.state.agentsById,
        );
      case DetectAgentsEffect():
        detectionCalls += 1;
        final agent = store.state.agentsById[defaultClaudeCodeProviderId]!;
        store.detectionStarted(effect.operationId, defaultClaudeCodeProviderId);
        store.agentDetected(
          effect.operationId,
          defaultClaudeCodeProviderId,
          agent,
        );
        store.detectionCompleted(effect.operationId);
      case UpdateProviderEnabledEffect() ||
          UpdateAccountDataEnrichmentEffect() ||
          TestAgentConnectionEffect() ||
          LoadAgentConfigurationEffect() ||
          SaveAgentConfigurationEffect() ||
          LoadAgentLogsEffect():
        throw StateError('Unexpected effect: $effect');
    }
  }

  @override
  String? validateConfiguration(String agentId, String content) => null;
}

final class _ManagementListenerHost extends StatefulWidget {
  const _ManagementListenerHost({required this.store});

  final AgentManagementSliceStore store;

  @override
  State<_ManagementListenerHost> createState() =>
      _ManagementListenerHostState();
}

final class _ManagementListenerHostState
    extends State<_ManagementListenerHost> {
  int _notificationCount = 0;

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_handleManagementChanged);
  }

  @override
  void dispose() {
    widget.store.removeListener(_handleManagementChanged);
    super.dispose();
  }

  void _handleManagementChanged() {
    setState(() {
      _notificationCount += 1;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      value: '$_notificationCount',
      child: AgentManagementPage(sliceStore: widget.store),
    );
  }
}

Future<void> _pumpSlicePage(
  WidgetTester tester,
  AgentManagementSliceStore store, {
  Widget? child,
}) async {
  tester.view
    ..physicalSize = const Size(1200, 820)
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
    ProviderScope(
      child: IdeThemeScope(
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
            child:
                child ??
                AgentManagementPage(sliceStore: store, autoDetect: false),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

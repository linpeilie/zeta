import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  final tempDirectories = <Directory>[];

  tearDown(() {
    for (final directory in tempDirectories) {
      if (directory.existsSync()) {
        directory.deleteSync(recursive: true);
      }
    }
    tempDirectories.clear();
  });

  testWidgets('restores the previous project and selected file on restart', (
    tester,
  ) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final file = File('${directory.path}${Platform.pathSeparator}sample.txt');
    file.writeAsStringSync('hello from zeta');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    await tester.tap(find.byKey(fileNodeKey('sample.txt')));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await pumpSessionSave(tester);

    expect(session.value, isNotNull);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets('restores expanded file tree folders on restart', (tester) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_test_');
    tempDirectories.add(directory);

    final folder = Directory('${directory.path}${Platform.pathSeparator}lib')
      ..createSync();
    File(
      '${folder.path}${Platform.pathSeparator}main.dart',
    ).writeAsStringSync('void main() {}');

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        directoryPicker: () async => directory.path,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byKey(fileNodeKey('lib')));
    await tester.pumpAndSettle();
    await pumpSessionSave(tester);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets(
    'restores project root contents without showing the root folder',
    (tester) async {
      _useWideWindow(tester);
      final directory = Directory.systemTemp.createTempSync('zeta_test_');
      tempDirectories.add(directory);

      File(
        '${directory.path}${Platform.pathSeparator}sample.txt',
      ).writeAsStringSync('hello from zeta');

      final session = MemorySessionStore(
        jsonEncode(<String, Object?>{
          'version': 1,
          'projectPaths': <String>[directory.path],
          'activeProjectPath': directory.path,
          'currentFilePath': null,
          'expandedDirectoryPaths': <String>[],
          'selectedTreeKey': directory.path,
        }),
      );

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();
      await _openFilesPanel(tester);

      expect(find.byKey(fileNodeKey(fileName(directory.path))), findsNothing);
      expect(find.text('sample.txt'), findsOneWidget);
    },
  );

  testWidgets('ignores missing paths when restoring a session', (tester) async {
    _useWideWindow(tester);
    final session = MemorySessionStore(
      jsonEncode(<String, Object?>{
        'version': 1,
        'projectPaths': <String>['/zeta/missing/project'],
        'activeProjectPath': '/zeta/missing/project',
        'currentFilePath': '/zeta/missing/project/main.dart',
        'expandedDirectoryPaths': <String>['/zeta/missing/project'],
        'selectedTreeKey': '/zeta/missing/project/main.dart',
      }),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
      ),
    );
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('No folder opened'), findsOneWidget);
    expect(find.text('No file tree'), findsOneWidget);
    expect(find.text('No file context'), findsNothing);
  });

  testWidgets('keeps restored workbench fields during startup resave', (
    tester,
  ) async {
    const workbench = IdeWorkbenchLayoutState(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: 315,
      agentUsageHeightFraction: 0.48,
      selectedAgentUsageProviderId: 'grok',
    );
    final session = MemorySessionStore(
      const IdeSessionState(workbenchLayout: workbench).encode(),
    );

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        sessionLoader: session.load,
        sessionSaver: session.save,
        agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await pumpSessionSave(tester);

    expect(
      IdeSessionState.tryDecode(session.value)?.workbenchLayout,
      workbench,
    );
  });

  testWidgets('restores five workbench preferences after user interactions', (
    tester,
  ) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();

    Future<void> pumpApp({bool waitForUsage = true}) async {
      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          sessionLoader: session.load,
          sessionSaver: session.save,
          agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
          agentUsagePanelRepository: const _WorkbenchUsageRepository(),
        ),
      );
      await pumpUntilCondition(tester, () {
        final key = waitForUsage
            ? 'agent-usage-expand-button'
            : 'titlebar-left-sidebar-action';
        return find.byKey(ValueKey<String>(key)).evaluate().isNotEmpty;
      }, failureMessage: 'Workbench did not become ready');
    }

    await pumpApp();
    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    await tester.pump();

    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(44, 0),
    );
    await tester.pump();
    await tester.drag(
      find.byKey(const ValueKey('agent-usage-resize-handle')),
      const Offset(0, -32),
    );
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('agent-usage-tab-grok')));
    await tester.pump();

    final expectedUsageHeight = tester
        .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
        .height;
    expect(
      tester
          .widget<IdeTabs<String>>(
            find.byKey(const ValueKey('agent-usage-tabs')),
          )
          .value,
      'grok',
    );

    await tester.tap(
      find.byKey(const ValueKey('titlebar-left-sidebar-action')),
    );
    await pumpSessionSave(tester);

    final persisted = IdeSessionState.tryDecode(session.value)!.workbenchLayout;
    expect(persisted.leftSidebarVisible, isFalse);
    expect(persisted.agentUsageExpanded, isTrue);
    expect(persisted.leftSidebarWidth, 324);
    expect(persisted.agentUsageHeightFraction, isNotNull);
    expect(persisted.selectedAgentUsageProviderId, 'grok');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await pumpApp(waitForUsage: false);

    expect(
      find.byKey(const ValueKey('workbench-navigation-inline')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey('titlebar-left-sidebar-action')),
    );
    await pumpUntilCondition(
      tester,
      () =>
          find.byKey(const ValueKey('agent-usage-tabs')).evaluate().isNotEmpty,
      failureMessage: 'Restored expanded Agent usage did not become ready',
    );

    expect(
      tester
          .getSize(find.byKey(const ValueKey('workbench-navigation-inline')))
          .width,
      324,
    );
    expect(find.byKey(const ValueKey('projects-panel-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('context-panel-card')), findsNothing);
    expect(
      find.byKey(const ValueKey('agent-usage-resize-handle')),
      findsOneWidget,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      moreOrLessEquals(expectedUsageHeight, epsilon: 1),
    );
    expect(
      tester
          .widget<IdeTabs<String>>(
            find.byKey(const ValueKey('agent-usage-tabs')),
          )
          .value,
      'grok',
    );
  });

  testWidgets(
    'does not let a slow session restore replace a user-opened folder',
    (tester) async {
      _useWideWindow(tester);
      final restoreCompleter = Completer<String?>();
      final savedSession = MemorySessionStore();
      final restoredDirectory = Directory.systemTemp.createTempSync(
        'zeta_restore_',
      );
      final chosenDirectory = Directory.systemTemp.createTempSync(
        'zeta_chosen_',
      );
      tempDirectories
        ..add(restoredDirectory)
        ..add(chosenDirectory);

      final restoredFile = File(
        '${restoredDirectory.path}${Platform.pathSeparator}restored.txt',
      )..writeAsStringSync('restored');
      File(
        '${chosenDirectory.path}${Platform.pathSeparator}chosen.txt',
      ).writeAsStringSync('chosen');

      await tester.pumpWidget(
        MainApp(
          enableNativeWindowFrame: true,
          showWindowControls: false,
          directoryPicker: () async => chosenDirectory.path,
          sessionLoader: () => restoreCompleter.future,
          sessionSaver: savedSession.save,
          agentProviderFactory: FakeAgentProviderFactory(FakeAgentProvider()),
          agentProviderConfigStore: MemoryAgentProviderConfigStore(),
        ),
      );

      await tester.tap(find.byIcon(Icons.create_new_folder_outlined));
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();
      await _openFilesPanel(tester);

      expect(find.text('chosen.txt'), findsOneWidget);
      expect(find.text('restored.txt'), findsNothing);

      restoreCompleter.complete(
        sessionJson(
          projectPath: restoredDirectory.path,
          currentFilePath: restoredFile.path,
        ),
      );
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();
      await pumpSessionSave(tester);

      expect(find.text('chosen.txt'), findsOneWidget);
      expect(find.text('restored.txt'), findsNothing);
    },
  );
}

class _WorkbenchUsageRepository implements AgentUsagePanelRepository {
  const _WorkbenchUsageRepository();

  @override
  Future<List<AgentUsagePanelProvider>> discoverProviders() async =>
      const <AgentUsagePanelProvider>[
        AgentUsagePanelProvider(providerId: 'codex', providerName: 'Codex'),
        AgentUsagePanelProvider(providerId: 'grok', providerName: 'Grok'),
      ];

  @override
  Future<AgentUsagePanelProviderResult?> loadProvider(
    String providerId, {
    bool forceRefresh = false,
  }) async {
    return AgentUsagePanelProviderResult(
      entry: AgentUsagePanelEntry(
        providerId: providerId,
        providerName: providerId == 'grok' ? 'Grok' : 'Codex',
      ),
      refreshedAt: DateTime(2026, 8, 12),
    );
  }
}

Future<void> _openFilesPanel(WidgetTester tester) async {
  // 右侧 Files 面板默认关闭，测试需先打开才能断言文件树内容。
  await tester.tap(find.byKey(const ValueKey('titlebar-right-sidebar-action')));
  await tester.pumpAndSettle();
}

void _useWideWindow(WidgetTester tester) {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
}

@Tags(['slow', 'shell'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/ide_session/domain/ide_workbench_layout_state.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta_ui/zeta_ui.dart';

import '../../../testing/ide_test_harness.dart';
import '../../../testing/fake_workspace_directory_picker.dart';
import '../../../testing/zeta_test_app.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';

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
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ...fakeDirectoryPickerOverrides(directory.path),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
      ),
    );

    await openProjectFromMenu(tester);
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
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
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
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ...fakeDirectoryPickerOverrides(directory.path),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
      ),
    );

    await openProjectFromMenu(tester);
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
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
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
          'version': sessionStateVersion,
          'projectPaths': <String>[directory.path],
          'activeProjectPath': directory.path,
          'currentFilePath': null,
          'expandedDirectoryPaths': <String>[],
          'selectedTreeKey': directory.path,
        }),
      );

      await tester.pumpWidget(
        zetaTestApp(
          overrides: <Override>[
            zetaWindowHostProvider.overrideWithValue(
              const NativeDesktopWindowHost(showsWindowControls: false),
            ),
            ideSessionStoreProvider.overrideWithValue(session),
            agentProviderBundleFactoryProvider.overrideWithValue(
              FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
            ),
            agentProviderConfigStoreProvider.overrideWithValue(
              MemoryAgentProviderConfigStore(),
            ),
          ],
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
        'version': sessionStateVersion,
        'projectPaths': <String>['/zeta/missing/project'],
        'activeProjectPath': '/zeta/missing/project',
        'currentFilePath': '/zeta/missing/project/main.dart',
        'expandedDirectoryPaths': <String>['/zeta/missing/project'],
        'selectedTreeKey': '/zeta/missing/project/main.dart',
      }),
    );

    await tester.pumpWidget(
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ideSessionStoreProvider.overrideWithValue(session),
          // 必须注入 fake：不注入时 MainApp 会构造真实工厂并拉起本机 Codex CLI，
          // 模型目录预热的 30 秒 JSON-RPC Timer 会挂到 widget 树销毁之后。
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
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
      leftSidebarWidth: 315,
      selectedAgentUsageProviderId: 'grok',
    );
    final session = MemorySessionStore(
      const IdeSessionState(workbenchLayout: workbench).encode(),
    );

    await tester.pumpWidget(
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
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

  testWidgets(
    'IDE Session slice restores and resaves the same workbench projection',
    (tester) async {
      _useWideWindow(tester);
      const workbench = IdeWorkbenchLayoutState(
        leftSidebarVisible: false,
        leftSidebarWidth: 315,
        selectedAgentUsageProviderId: 'grok',
      );
      final session = MemorySessionStore(
        const IdeSessionState(workbenchLayout: workbench).encode(),
      );

      // 同一个组合根重建 Widget：容器与 store identity 都必须保持稳定。
      final composition = zetaTestComposition(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            const NativeDesktopWindowHost(showsWindowControls: false),
          ),
          ideSessionStoreProvider.overrideWithValue(session),
          agentProviderBundleFactoryProvider.overrideWithValue(
            FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
          ),
          agentProviderConfigStoreProvider.overrideWithValue(
            MemoryAgentProviderConfigStore(),
          ),
        ],
      );
      await tester.pumpWidget(MainApp(composition: composition));
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('workbench-navigation-inline')),
        findsNothing,
      );
      await tester.tap(
        find.byKey(const ValueKey('titlebar-left-sidebar-action')),
      );
      await pumpSessionSave(tester);

      expect(
        IdeSessionState.tryDecode(session.value)?.workbenchLayout,
        workbench.copyWith(leftSidebarVisible: true),
      );

      await tester.pumpWidget(MainApp(composition: composition));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(
        find.byKey(const ValueKey('workbench-navigation-inline')),
        findsOneWidget,
      );
    },
  );

  testWidgets('restores active workbench preferences after user interactions', (
    tester,
  ) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();

    Future<void> pumpApp({bool waitForUsage = true}) async {
      await tester.pumpWidget(
        zetaTestApp(
          overrides: <Override>[
            zetaWindowHostProvider.overrideWithValue(
              const NativeDesktopWindowHost(showsWindowControls: false),
            ),
            ideSessionStoreProvider.overrideWithValue(session),
            agentProviderBundleFactoryProvider.overrideWithValue(
              FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
            ),
            agentProviderConfigStoreProvider.overrideWithValue(
              MemoryAgentProviderConfigStore(),
            ),
            agentUsagePanelRepositoryProvider.overrideWithValue(
              const _WorkbenchUsageRepository(),
            ),
            agentUsageAutoRefreshEnabledProvider.overrideWithValue(true),
          ],
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
    await tester.drag(
      find.byKey(const ValueKey('left-width-resize-handle')),
      const Offset(44, 0),
    );
    await tester.pump();

    // Provider 选择在弹层内完成；收起弹层后偏好仍须留在会话里。
    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    await _settleUsagePopover(tester);
    await tester.tap(find.byKey(const ValueKey('agent-usage-tab-grok')));
    await tester.pump();
    expect(
      tester
          .widget<IdeTabs<String>>(
            find.byKey(const ValueKey('agent-usage-tabs')),
          )
          .value,
      'grok',
    );
    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    await _settleUsagePopover(tester);

    final expectedUsageHeight = tester
        .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
        .height;

    await tester.tap(
      find.byKey(const ValueKey('titlebar-left-sidebar-action')),
    );
    await pumpSessionSave(tester);

    final persisted = IdeSessionState.tryDecode(session.value)!.workbenchLayout;
    expect(persisted.leftSidebarVisible, isFalse);
    expect(persisted.leftSidebarWidth, 324);
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
      () => find
          .byKey(const ValueKey('agent-usage-expand-button'))
          .evaluate()
          .isNotEmpty,
      failureMessage: 'Restored Agent usage summary did not become ready',
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
      findsNothing,
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('project-agent-sidebar-usage')))
          .height,
      moreOrLessEquals(expectedUsageHeight, epsilon: 1),
    );

    await tester.tap(find.byKey(const ValueKey('agent-usage-expand-button')));
    await _settleUsagePopover(tester);
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
        zetaTestApp(
          overrides: <Override>[
            zetaWindowHostProvider.overrideWithValue(
              const NativeDesktopWindowHost(showsWindowControls: false),
            ),
            ...fakeDirectoryPickerOverrides(chosenDirectory.path),
            ideSessionStoreProvider.overrideWithValue(
              _DeferredSessionStore(
                pending: restoreCompleter.future,
                sink: savedSession,
              ),
            ),
            agentProviderBundleFactoryProvider.overrideWithValue(
              FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
            ),
            agentProviderConfigStoreProvider.overrideWithValue(
              MemoryAgentProviderConfigStore(),
            ),
          ],
        ),
      );

      await openProjectFromMenu(tester);
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

  testWidgets(
    'IDE Session slice cancels a slow restore after the user opens a folder',
    (tester) async {
      _useWideWindow(tester);
      final restoreCompleter = Completer<String?>();
      final savedSession = MemorySessionStore();
      final restoredDirectory = Directory.systemTemp.createTempSync(
        'zeta_restore_slice_',
      );
      final chosenDirectory = Directory.systemTemp.createTempSync(
        'zeta_chosen_slice_',
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
        zetaTestApp(
          overrides: <Override>[
            zetaWindowHostProvider.overrideWithValue(
              const NativeDesktopWindowHost(showsWindowControls: false),
            ),
            ...fakeDirectoryPickerOverrides(chosenDirectory.path),
            ideSessionStoreProvider.overrideWithValue(
              _DeferredSessionStore(
                pending: restoreCompleter.future,
                sink: savedSession,
              ),
            ),
            agentProviderBundleFactoryProvider.overrideWithValue(
              FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
            ),
            agentProviderConfigStoreProvider.overrideWithValue(
              MemoryAgentProviderConfigStore(),
            ),
          ],
        ),
      );

      await openProjectFromMenu(tester);
      await tester.runAsync(waitForIo);
      await tester.pumpAndSettle();
      await _openFilesPanel(tester);

      expect(find.text('chosen.txt'), findsOneWidget);
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

/// Agent 统计弹层在帧末挂载，开合都要多走一帧并跑完过渡。
Future<void> _settleUsagePopover(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
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

/// 恢复流程测试专用：load 挂在 completer 上，save 落到内存 store。
///
/// 迁移前这条路径用 `sessionLoader: () => completer.future` 表达；
/// 换成 typed [IdeSessionStore] 后语义不变，只是从裸回调变成显式实现。
class _DeferredSessionStore implements IdeSessionStore {
  _DeferredSessionStore({required this.pending, required this.sink});

  final Future<String?> pending;
  final MemorySessionStore sink;

  @override
  Future<IdeSessionState?> load() async =>
      IdeSessionState.tryDecode(await pending);

  @override
  Future<void> save(IdeSessionState state) => sink.save(state);
}

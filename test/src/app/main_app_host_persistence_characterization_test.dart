import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/core/storage/zeta_data_paths.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/usage_statistics/domain/agent_usage_panel_models.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_picker.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../testing/ide_test_harness.dart';
import '../testing/fake_workspace_directory_picker.dart';
import '../testing/zeta_test_app.dart';
import 'package:zeta/src/app/composition/zeta_environment_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_providers.dart';

/// `zetaTestComposition` 的本机隔离 characterization test。
///
/// widget test 必须经测试组合根装配，不能碰用户机器：
///
/// 1. 所有持久化退成内存实现，一个字节都不写 `dataPaths` 指向的目录；
/// 2. 用无安装结果的 stub 顶掉本机 CLI 探测（否则 `IdeHome` 会去
///    `AgentManagementOperations.initialize()` 真扫本机）；
/// 3. 关掉 Agent 用量自动刷新（否则会读本机 CLI 的历史记录）。
///
/// 第 3 条由 `agentUsageAutoRefreshEnabledProvider` 显式决定，**不再从
/// "有没有传统计仓储"反推**。一个可选参数同时决定数据源和刷新策略，改一处
/// 就会悄悄改另一处；要恢复刷新就自己把开关打开。
void main() {
  testWidgets('会话保存走回调，不写 dataPaths 指向的任何文件', (tester) async {
    final home = Directory.systemTemp.createTempSync('zeta_test_host_');
    addTearDown(() {
      if (home.existsSync()) {
        home.deleteSync(recursive: true);
      }
    });
    final project = Directory.systemTemp.createTempSync('zeta_host_project_');
    addTearDown(() {
      if (project.existsSync()) {
        project.deleteSync(recursive: true);
      }
    });
    final dataPaths = ZetaDataPaths.fromHomeDirectory(
      home.path,
      isWindows: Platform.isWindows,
    );
    final session = MemorySessionStore(null);

    await _pumpzetaTestApp(
      tester,
      session: session,
      directoryPicker: FakeWorkspaceDirectoryPicker(project.path),
    );

    // 真正落到写路径上：不触发一次持久化，下面的目录断言就是空的。
    await openProjectFromMenu(tester);
    await tester.runAsync(waitForIo);
    await pumpSessionSave(tester);

    // 注意：这条目录断言**未经 mutation 验证**——强制走文件持久化的三种 mutation
    // 都没让它变红，因为本场景没有驱动到会真正写 `.zeta` 的路径。它作为纵深防御
    // 保留（成本近乎为零），但本测试的实际保护力来自下面那条回调断言。
    final zetaRoot = Directory(dataPaths.rootPath);
    final written = zetaRoot.existsSync()
        ? zetaRoot
              .listSync(recursive: true)
              .whereType<File>()
              .map((file) => file.path)
              .toList()
        : const <String>[];
    expect(written, isEmpty, reason: '测试组合根不得触碰 dataPaths 指向的真实目录');

    expect(session.value, isNotNull, reason: '会话必须交给注入的回调，而不是写进 dataPaths');
  });

  testWidgets('测试组合根用无安装 stub 顶掉本机 CLI 探测', (tester) async {
    final composition = await _pumpzetaTestApp(tester);
    await tester.pump();

    final loader = composition.container.read(
      homeProviderDetectionLoaderProvider,
    );
    expect(
      loader,
      isNotNull,
      reason: 'loader 为 null 时 IdeHome 会真的去初始化 Agent Management 扫描本机',
    );
    expect(await loader!(), isEmpty);
  });

  testWidgets('测试组合根关闭 Agent 用量自动刷新', (tester) async {
    final composition = await _pumpzetaTestApp(tester);
    await tester.pump();

    expect(
      composition.container.read(agentUsageAutoRefreshEnabledProvider),
      isFalse,
      reason: '自动刷新会读取本机 CLI 历史，测试组合根必须关闭',
    );
  });

  testWidgets('注入统计仓储并显式打开开关后自动刷新恢复', (tester) async {
    final composition = await _pumpzetaTestApp(
      tester,
      agentUsagePanelRepository: const _EmptyAgentUsageRepository(),
    );
    await tester.pump();

    expect(
      composition.container.read(agentUsageAutoRefreshEnabledProvider),
      isTrue,
      reason: '仓储已注入、开关已显式打开时不再读本机历史，自动刷新可以恢复',
    );
  });

  testWidgets('显式注入的探测 loader 优先于无安装 stub', (tester) async {
    final composition = await _pumpzetaTestApp(
      tester,
      homeProviderDetectionLoader: () async => const <ManagedAgent>[],
    );
    await tester.pump();

    expect(
      composition.container.read(homeProviderDetectionLoaderProvider),
      isNotNull,
    );
  });
}

Future<ZetaAppComposition> _pumpzetaTestApp(
  WidgetTester tester, {
  AgentUsagePanelRepository? agentUsagePanelRepository,
  HomeProviderDetectionLoader? homeProviderDetectionLoader,
  MemorySessionStore? session,
  WorkspaceDirectoryPicker? directoryPicker,
}) async {
  final sessionStore = session ?? MemorySessionStore(null);
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final composition = zetaTestComposition(
    overrides: <Override>[
      headlessWindowHost(showsWindowControls: false),
      ...directoryPicker == null
          ? const <Override>[]
          : fakeDirectoryPickerOverridesOf(directoryPicker),
      ideSessionStoreProvider.overrideWithValue(sessionStore),
      agentProviderBundleFactoryProvider.overrideWithValue(
        FakeAgentProviderBundleBuilder.fromFake(FakeAgentProvider()),
      ),
      // 注入统计仓储时数据来源已经不碰本机，这时才把自动刷新打开。
      if (agentUsagePanelRepository case final repository?) ...<Override>[
        agentUsagePanelRepositoryProvider.overrideWithValue(repository),
        agentUsageAutoRefreshEnabledProvider.overrideWithValue(true),
      ],
      if (homeProviderDetectionLoader case final loader?)
        homeProviderDetectionLoaderProvider.overrideWithValue(loader),
    ],
  );
  await tester.pumpWidget(MainApp(composition: composition));
  // 用量刷新协调器用零延迟 Timer 重试，必须排干净否则 widget 树销毁后仍有 pending timer。
  await tester.pump(const Duration(milliseconds: 1));
  await tester.idle();
  await tester.pump();
  return composition;
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

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/app/composition/workbench_session_providers.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/router/app_navigation.dart';
import 'package:zeta/src/app/router/app_route_location.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/settings/presentation/settings_can_leave.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

import '../../testing/ide_test_harness.dart';
import '../../testing/zeta_test_app.dart';

typedef _Fixture = ({
  GoRouter router,
  ProviderContainer container,
  String path,
  String id,
});

Future<_Fixture> _pump(
  WidgetTester tester, {
  FakeAgentProvider Function(String)? providerForPath,
}) async {
  tester.view
    ..physicalSize = const Size(1400, 900)
    ..devicePixelRatio = 1;
  addTearDown(() {
    tester.view
      ..resetPhysicalSize()
      ..resetDevicePixelRatio();
  });
  final dir = Directory.systemTemp.createTempSync('zeta_router_regression_');
  addTearDown(() {
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  });
  final provider =
      providerForPath?.call(dir.path) ??
      FakeAgentProvider(threadPages: [_threads(dir.path)]);
  await tester.pumpWidget(
    zetaTestApp(
      overrides: [
        zetaWindowHostProvider.overrideWithValue(
          NativeDesktopWindowHost(showsWindowControls: false),
        ),
        ideSessionStoreProvider.overrideWithValue(
          MemorySessionStore(
            IdeSessionState(
              projectPaths: [dir.path],
              activeProjectPath: dir.path,
              projectHomeActive: true,
            ).encode(),
          ),
        ),
        agentProviderBundleFactoryProvider.overrideWithValue(
          FakeAgentProviderBundleBuilder.fromFake(provider),
        ),
        agentProviderConfigStoreProvider.overrideWithValue(
          MemoryAgentProviderConfigStore(),
        ),
      ],
    ),
  );
  await tester.runAsync(waitForIo);
  await pumpUntilCondition(
    tester,
    () => find
        .byKey(ValueKey('project-thread-${dir.path}-thread-a'))
        .evaluate()
        .isNotEmpty,
    failureMessage: 'Restored thread list did not appear',
  );
  final element = tester.element(find.byType(IdeHome));
  return (
    router: GoRouter.of(element),
    container: ProviderScope.containerOf(element),
    path: dir.path,
    id: ProjectIdMapping.hashPath(dir.path),
  );
}

AgentThreadPage _threads(String path) => AgentThreadPage(
  threads: [
    agentThread(id: 'thread-a', projectPath: path, title: 'Thread A'),
    agentThread(id: 'thread-b', projectPath: path, title: 'Thread B'),
  ],
  nextCursor: null,
);

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump();
}

void main() {
  test('case-sensitive projects keep distinct route identities', () {
    final mapping = ProjectIdMapping()
      ..syncProjects(['/repo/Foo', '/repo/foo']);
    expect(
      mapping.idForPath('/repo/Foo'),
      isNot(mapping.idForPath('/repo/foo')),
    );
    expect(mapping.pathForId(mapping.idForPath('/repo/Foo')!), '/repo/Foo');
    expect(mapping.pathForId(mapping.idForPath('/repo/foo')!), '/repo/foo');
    expect(
      ProjectIdMapping.hashPath('/'),
      isNot(ProjectIdMapping.hashPath('')),
    );
  });

  testWidgets('A B A during history loading restores the committed selection', (
    tester,
  ) async {
    late _GatedProvider provider;
    final f = await _pump(
      tester,
      providerForPath: (path) =>
          provider = _GatedProvider(path, gateHistory: true),
    );
    f.router.go('/project/${f.id}/thread/thread-a');
    await _frames(tester);
    f.router.go('/project/${f.id}/thread/thread-b');
    await pumpUntilCondition(
      tester,
      () => provider.entered.isCompleted,
      failureMessage: 'B did not start loading',
    );
    f.router.go('/project/${f.id}/thread/thread-a');
    await _frames(tester);
    provider.gate.complete();
    await _frames(tester);
    expect(f.router.state.uri.path, '/project/${f.id}/thread/thread-a');
    final shell = f.container.read(workbenchSessionProvider).shell;
    expect(
      shell.agentConversationWorkspace.selectedEntry?.threadId,
      'thread-a',
    );
    expect(
      shell.projectThreadsController.stateFor(f.path).selectedThreadId,
      'thread-a',
    );
    expect(
      tester
              .widget<AgentPane>(find.byType(AgentPane))
              .controller
              .currentSession
              ?.id ??
          tester
              .widget<AgentPane>(find.byType(AgentPane))
              .controller
              .threadSnapshot
              .sessionId,
      'thread-a',
    );
  });

  testWidgets(
    'draft promotion preserves settings and canonicalizes on return',
    (tester) async {
      late _GatedProvider provider;
      final f = await _pump(
        tester,
        providerForPath: (path) => provider = _GatedProvider(path),
      );
      f.router.go('/project/${f.id}/draft/codex');
      await _frames(tester);
      final shell = f.container.read(workbenchSessionProvider).shell;
      final entry = shell.agentConversationWorkspace.selectedEntry!;
      final sending = shell.lifetimes
          .actionsForOwner(entry.ownerKey)
          .sendMessage('fixture');
      await pumpUntilCondition(
        tester,
        () => provider.entered.isCompleted,
        failureMessage: 'Session did not start',
      );
      unawaited(f.router.push('/settings/general'));
      await _frames(tester);
      provider.gate.complete();
      await sending;
      await _frames(tester);
      expect(f.router.state.uri.path, '/settings/general');
      f.router.pop();
      await _frames(tester);
      expect(f.router.state.uri.path, '/project/${f.id}/thread/thread-1');
      expect(
        shell.agentConversationWorkspace.selectedEntry?.ownerKey,
        entry.ownerKey,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'late promotion after leaving draft does not hijack the new route',
    (tester) async {
      late _GatedProvider provider;
      final f = await _pump(
        tester,
        providerForPath: (path) => provider = _GatedProvider(path),
      );
      f.router.go('/project/${f.id}/draft/codex');
      await _frames(tester);
      final shell = f.container.read(workbenchSessionProvider).shell;
      final entry = shell.agentConversationWorkspace.selectedEntry!;
      final sending = shell.lifetimes
          .actionsForOwner(entry.ownerKey)
          .sendMessage('fixture');
      await pumpUntilCondition(
        tester,
        () => provider.entered.isCompleted,
        failureMessage: 'Session did not start',
      );
      f.router.go('/project/${f.id}/thread/thread-a');
      await _frames(tester);
      provider.gate.complete();
      await sending;
      await _frames(tester);
      expect(f.router.state.uri.path, '/project/${f.id}/thread/thread-a');
      f.router.go('/project/${f.id}/draft/codex');
      await _frames(tester);
      expect(shell.agentConversationWorkspace.selectedEntry?.isDraft, isTrue);
      expect(
        shell.agentConversationWorkspace.selectedEntry?.ownerKey,
        isNot(entry.ownerKey),
      );
    },
  );

  testWidgets('project hint restricts the open-entry fallback', (tester) async {
    final f = await _pump(tester);
    f.router.go('/project/${f.id}/thread/thread-a');
    await _frames(tester);
    final shell = f.container.read(workbenchSessionProvider).shell;
    expect(
      shell.resolveThreadTarget(
        threadId: 'thread-a',
        projectPathHint: '${f.path}-other',
      ),
      isNull,
    );
    expect(
      await shell.openThreadFromRoute('${f.path}-other', 'thread-a'),
      isFalse,
    );
  });

  for (final route in ['draft/codex', 'thread/thread-a']) {
    testWidgets('usage stays visible over $route and preserves content', (
      tester,
    ) async {
      final f = await _pump(tester);
      f.router.go('/project/${f.id}/$route');
      await _frames(tester);
      final pane = tester.element(find.byType(AgentPane));
      await tester.tap(
        find.byKey(const ValueKey('titlebar-usage-statistics-action')),
      );
      await _frames(tester);
      expect(f.router.state.uri.path, '/usage');
      expect(
        find.byKey(const ValueKey('usage-statistics-page')),
        findsOneWidget,
      );
      expect(pane.mounted, isTrue);
      expect(TickerMode.valuesOf(pane).enabled, isTrue);
      await tester.tap(find.byKey(const ValueKey('titlebar-back-action')));
      await _frames(tester);
      expect(f.router.state.uri.path, '/project/${f.id}/$route');
      expect(tester.element(find.byType(AgentPane)), same(pane));
    });
  }

  testWidgets('usage cover supports enlarged text and keyboard back', (
    tester,
  ) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    final semantics = tester.ensureSemantics();
    try {
      final f = await _pump(tester);
      unawaited(f.router.push('/usage'));
      await _frames(tester);
      final back = find.byKey(const ValueKey('titlebar-back-action'));
      expect(
        find.bySemanticsLabel(tester.element(back).l10n.workbenchBackToHome),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      bool backHasFocus() {
        var found = false;
        FocusManager.instance.primaryFocus?.context?.visitAncestorElements((
          element,
        ) {
          found = element == tester.element(back);
          return !found;
        });
        return found;
      }

      for (var step = 0; step < 20 && !backHasFocus(); step++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
      }
      expect(
        backHasFocus(),
        isTrue,
        reason: 'Back action must be keyboard reachable',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await _frames(tester);
      expect(f.router.state.uri.path, '/project/${f.id}');
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  testWidgets('async settings confirmation completes navigation to usage', (
    tester,
  ) async {
    final f = await _pump(tester);
    unawaited(f.router.push('/settings/agents'));
    await _frames(tester);
    final gate = Completer<bool>();
    f.container
        .read(settingsCanLeaveRegistryProvider)
        .register(() => gate.future);
    await tester.tap(
      find.byKey(const ValueKey('titlebar-usage-statistics-action')),
    );
    await _frames(tester);
    expect(f.router.state.uri.path, '/settings/agents');
    gate.complete(true);
    await _frames(tester);
    expect(f.router.state.uri.path, '/usage');
    expect(find.byKey(const ValueKey('usage-statistics-page')), findsOneWidget);
  });

  testWidgets('rejected deep link does not select its hidden target', (
    tester,
  ) async {
    final f = await _pump(tester);
    unawaited(f.router.push('/settings/agents'));
    await _frames(tester);
    f.container
        .read(settingsCanLeaveRegistryProvider)
        .register(() async => false);
    final result = f.container
        .read(routerCoordinatorProvider)
        .activateThreadFromDeepLink('codex', 'thread-a');
    await _frames(tester);
    expect(await result, isFalse);
    expect(f.router.state.uri.path, '/settings/agents');
    expect(
      f.container
          .read(workbenchSessionProvider)
          .shell
          .agentConversationWorkspace
          .selectedEntry
          ?.threadId,
      isNot('thread-a'),
    );
  });

  testWidgets('accepted deep link opens once and reports resource readiness', (
    tester,
  ) async {
    late FakeAgentProvider provider;
    final f = await _pump(
      tester,
      providerForPath: (path) =>
          provider = FakeAgentProvider(threadPages: [_threads(path)]),
    );
    unawaited(f.router.push('/settings/general'));
    await _frames(tester);
    final result = f.container
        .read(routerCoordinatorProvider)
        .activateThreadFromDeepLink('codex', 'thread-a');
    await _frames(tester);
    expect(await result, isTrue);
    expect(f.router.state.uri.path, '/project/${f.id}/thread/thread-a');
    expect(
      provider.readHistories.where((id) => id == 'thread-a'),
      hasLength(1),
    );
  });

  for (final covered in [false, true]) {
    testWidgets(
      'deleting the displayed thread returns home (covered: $covered)',
      (tester) async {
        final f = await _pump(tester);
        f.router.go('/project/${f.id}/thread/thread-a');
        await _frames(tester);
        if (covered) {
          unawaited(f.router.push('/settings/general'));
          await _frames(tester);
        }
        await f.container
            .read(workbenchSessionProvider)
            .shell
            .deleteProjectThread(
              f.path,
              agentThread(
                id: 'thread-a',
                projectPath: f.path,
                title: 'Thread A',
              ),
            );
        await _frames(tester);
        if (covered) {
          expect(f.router.state.uri.path, '/settings/general');
          f.router.pop();
          await _frames(tester);
        }
        expect(f.router.state.uri.path, '/project/${f.id}');
        expect(
          find.byKey(const ValueKey('project-home-header')),
          findsOneWidget,
        );
      },
    );
  }

  for (final timeout in [false, true]) {
    testWidgets(
      'late confirmation cannot commit after ${timeout ? 'timeout' : 'detach'}',
      (tester) async {
        final f = await _pump(tester);
        unawaited(f.router.push('/settings/agents'));
        await _frames(tester);
        final gate = Completer<bool>();
        f.container
            .read(settingsCanLeaveRegistryProvider)
            .register(() => gate.future);
        final navigation =
            f.container.read(appNavigationPortProvider)
                as MountableAppNavigationPort;
        final pending = navigation.navigateTo(ThreadLocation(f.id, 'thread-a'));
        await _frames(tester);
        if (timeout) {
          await tester.pump(const Duration(seconds: 11));
        } else {
          navigation.detach();
        }
        expect(
          await pending,
          timeout ? NavigationOutcome.timedOut : NavigationOutcome.unavailable,
        );
        gate.complete(true);
        await _frames(tester);
        expect(f.router.state.uri.path, '/settings/agents');
      },
    );
  }

  testWidgets(
    'superseded navigation settles and stale confirmation cannot navigate',
    (tester) async {
      final f = await _pump(tester);
      unawaited(f.router.push('/settings/agents'));
      await _frames(tester);
      final gate = Completer<bool>();
      f.container
          .read(settingsCanLeaveRegistryProvider)
          .register(() => gate.future);
      final navigation = f.container.read(appNavigationPortProvider);
      final first = navigation.navigateTo(ThreadLocation(f.id, 'thread-a'));
      await _frames(tester);
      final second = navigation.navigateTo(ThreadLocation(f.id, 'thread-b'));
      await _frames(tester);
      expect(await first, NavigationOutcome.superseded);
      gate.complete(true);
      await _frames(tester);
      expect(await second, NavigationOutcome.reached);
      expect(f.router.state.uri.path, '/project/${f.id}/thread/thread-b');
    },
  );
}

class _GatedProvider extends FakeAgentProvider {
  _GatedProvider(String path, {this.gateHistory = false})
    : super(threadPages: [_threads(path)]);
  final bool gateHistory;
  final gate = Completer<void>();
  final entered = Completer<void>();

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    if (!gateHistory) {
      entered.complete();
      await gate.future;
    }
    return super.startSession(
      context: context,
      permissionSnapshot: permissionSnapshot,
    );
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    if (gateHistory && threadId == 'thread-b') {
      entered.complete();
      await gate.future;
    }
    return super.readThreadHistory(
      threadId: threadId,
      sessionPath: sessionPath,
      projectPath: projectPath,
    );
  }
}

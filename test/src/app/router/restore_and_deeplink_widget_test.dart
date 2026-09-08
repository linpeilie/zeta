import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/router/project_id_mapping.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/ide_session/data/ide_session_store.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/ui/features/ide/views/ide_home.dart';

import '../../testing/ide_test_harness.dart';
import '../../testing/zeta_test_app.dart';

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

  testWidgets('restore incomplete stays on / with the restoring placeholder', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(1400, 900)
      ..devicePixelRatio = 1;
    addTearDown(() {
      tester.view
        ..resetPhysicalSize()
        ..resetDevicePixelRatio();
    });

    final directory = Directory.systemTemp.createTempSync('zeta_w6_restore_');
    tempDirectories.add(directory);
    final gate = Completer<void>();
    final session = _GatedSessionStore(
      MemorySessionStore(
        IdeSessionState(
          projectPaths: <String>[directory.path],
          activeProjectPath: directory.path,
          projectHomeActive: true,
        ).encode(),
      ),
      gate,
    );

    await tester.pumpWidget(
      zetaTestApp(
        overrides: <Override>[
          zetaWindowHostProvider.overrideWithValue(
            NativeDesktopWindowHost(showsWindowControls: false),
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
    await tester.pump();
    await tester.pump();

    final router = GoRouter.of(tester.element(find.byType(IdeHome)));
    expect(router.state.uri.path, '/');
    expect(
      find.byKey(const ValueKey<String>('global-home-restoring')),
      findsOneWidget,
    );

    gate.complete();
    await tester.runAsync(waitForIo);
    await pumpUntilCondition(
      tester,
      () => find
          .byKey(const ValueKey<String>('project-home-header'))
          .evaluate()
          .isNotEmpty,
      failureMessage: 'Project home did not appear after restore',
    );

    final projectId =
        (ProjectIdMapping()..syncProjects(<String>[directory.path])).idForPath(
          directory.path,
        )!;
    expect(router.state.uri.path, '/project/$projectId');
    expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'restore with a last-thread mapping still lands on project home',
    (tester) async {
      tester.view
        ..physicalSize = const Size(1400, 900)
        ..devicePixelRatio = 1;
      addTearDown(() {
        tester.view
          ..resetPhysicalSize()
          ..resetDevicePixelRatio();
      });

      final directory = Directory.systemTemp.createTempSync('zeta_w6_thread_');
      tempDirectories.add(directory);
      final session = MemorySessionStore(
        IdeSessionState(
          projectPaths: <String>[directory.path],
          activeProjectPath: directory.path,
          projectHomeActive: true,
          agentThreadIdsByProject: <String, String>{
            directory.path: 'cached-thread',
          },
          selectedThreadIdsByProject: <String, String>{
            directory.path: 'cached-thread',
          },
        ).encode(),
      );

      await tester.pumpWidget(
        zetaTestApp(
          overrides: <Override>[
            zetaWindowHostProvider.overrideWithValue(
              NativeDesktopWindowHost(showsWindowControls: false),
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
      await pumpUntilCondition(
        tester,
        () => find
            .byKey(const ValueKey<String>('project-home-header'))
            .evaluate()
            .isNotEmpty,
        failureMessage: 'Project home did not appear after restore',
      );

      final router = GoRouter.of(tester.element(find.byType(IdeHome)));
      final projectId =
          (ProjectIdMapping()..syncProjects(<String>[directory.path]))
              .idForPath(directory.path)!;
      expect(router.state.uri.path, '/project/$projectId');
      expect(router.state.uri.path, isNot(contains('/thread/')));
      expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

final class _GatedSessionStore implements IdeSessionStore {
  _GatedSessionStore(this._inner, this._gate);

  final IdeSessionStore _inner;
  final Completer<void> _gate;

  @override
  Future<IdeSessionState?> load() async {
    await _gate.future;
    return _inner.load();
  }

  @override
  Future<void> save(IdeSessionState state) => _inner.save(state);
}

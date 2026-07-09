import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/core/utils/path_utils.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';

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
        enableNativeWindowFrame: false,
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
        enableNativeWindowFrame: false,
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
        enableNativeWindowFrame: false,
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
        enableNativeWindowFrame: false,
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
          enableNativeWindowFrame: false,
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
        enableNativeWindowFrame: false,
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
          enableNativeWindowFrame: false,
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

Future<void> _openFilesPanel(WidgetTester tester) async {
  // 右侧 Files 面板默认关闭，测试需先打开才能断言文件树内容。
  await tester.tap(find.byKey(const ValueKey('right-files-action')));
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

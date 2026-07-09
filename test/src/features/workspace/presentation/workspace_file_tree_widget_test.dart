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

  testWidgets('opens a folder and selects a file from the tree', (
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

    expect(find.byKey(fileNodeKey(fileName(directory.path))), findsNothing);
    expect(find.text('sample.txt'), findsOneWidget);

    await tester.tap(find.byKey(fileNodeKey('sample.txt')));
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();

    expect(find.text('sample.txt'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-context-chip')), findsNothing);
    expect(find.byIcon(Icons.save_outlined), findsNothing);
  });

  testWidgets('opens this repository and shows top-level files', (
    tester,
  ) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();
    final repositoryDirectory = Directory.current;

    await tester.pumpWidget(
      MainApp(
        enableNativeWindowFrame: false,
        directoryPicker: () async => repositoryDirectory.path,
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

    expect(
      find.byKey(fileNodeKey(fileName(repositoryDirectory.path))),
      findsNothing,
    );
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('pubspec.yaml', skipOffstage: false), findsOneWidget);
  });

  testWidgets('loads nested file tree folders after expansion', (tester) async {
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

    expect(find.byKey(fileNodeKey(fileName(directory.path))), findsNothing);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byKey(fileNodeKey('lib')));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
  });
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

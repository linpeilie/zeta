import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/main.dart';
import 'package:zeta/src/features/ide_session/domain/ide_session_state.dart';
import 'package:zeta/src/features/workspace/domain/workspace_directory_picker.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import '../../../testing/ide_test_harness.dart';
import '../../../testing/fake_workspace_directory_picker.dart';
import '../../../testing/zeta_test_app.dart';

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
      zetaTestApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        overrides: fakeDirectoryPickerOverrides(directory.path),
        hostMode: ZetaHostMode.ephemeral,
        ideSessionStore: session,
        agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await openProjectFromMenu(tester);
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.byKey(fileNodePathKey(directory.path)), findsNothing);
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
      zetaTestApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        overrides: fakeDirectoryPickerOverrides(repositoryDirectory.path),
        hostMode: ZetaHostMode.ephemeral,
        ideSessionStore: session,
        agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await openProjectFromMenu(tester);
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.byKey(fileNodePathKey(repositoryDirectory.path)), findsNothing);
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
      zetaTestApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        overrides: fakeDirectoryPickerOverrides(directory.path),
        hostMode: ZetaHostMode.ephemeral,
        ideSessionStore: session,
        agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      ),
    );

    await openProjectFromMenu(tester);
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.byKey(fileNodePathKey(directory.path)), findsNothing);
    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsNothing);

    await tester.tap(find.byKey(fileNodeKey('lib')));
    await tester.pumpAndSettle();

    expect(find.text('main.dart'), findsOneWidget);
  });

  testWidgets('workspace slice opens, selects, persists and restores lazily', (
    tester,
  ) async {
    _useWideWindow(tester);
    final session = MemorySessionStore();
    final directory = Directory.systemTemp.createTempSync('zeta_slice_test_');
    tempDirectories.add(directory);
    final folder = Directory('${directory.path}${Platform.pathSeparator}lib')
      ..createSync();
    final file = File('${folder.path}${Platform.pathSeparator}main.dart')
      ..writeAsStringSync('void main() {}');

    MainApp buildApp({WorkspaceDirectoryPicker? directoryPicker}) {
      return zetaTestApp(
        enableNativeWindowFrame: true,
        showWindowControls: false,
        overrides: directoryPicker == null
            ? const <Override>[]
            : fakeDirectoryPickerOverridesOf(directoryPicker),
        hostMode: ZetaHostMode.ephemeral,
        ideSessionStore: session,
        agentProviderFactory: FakeAgentProviderBundleBuilder.fromFake(
          FakeAgentProvider(),
        ),
        agentProviderConfigStore: MemoryAgentProviderConfigStore(),
      );
    }

    await tester.pumpWidget(
      buildApp(directoryPicker: FakeWorkspaceDirectoryPicker(directory.path)),
    );
    await openProjectFromMenu(tester);
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('main.dart'), findsNothing);
    await tester.tap(find.byKey(fileNodeKey('lib')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(fileNodeKey('main.dart')));
    await tester.pumpAndSettle();
    await pumpSessionSave(tester);

    final persisted = IdeSessionState.tryDecode(session.value)!;
    expect(persisted.activeProjectPath, directory.path);
    expect(persisted.expandedDirectoryPaths, contains(folder.path));
    expect(persisted.selectedTreeKey, file.path);
    expect(persisted.currentFilePath, file.path);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(buildApp());
    await tester.runAsync(waitForIo);
    await tester.pumpAndSettle();
    await _openFilesPanel(tester);

    expect(find.text('lib'), findsOneWidget);
    expect(find.text('main.dart'), findsOneWidget);
  });
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

ValueKey<String> fileNodePathKey(String path) {
  return ValueKey<String>('file-node-path-$path');
}

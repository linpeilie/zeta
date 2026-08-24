import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace reducer/store stay pure and Flutter stays out', () {
    // intent / effect / state / reducer 是纯数据与纯函数：它们不发布状态，
    // 因此连纯 Dart 的 package:riverpod 都不该出现（工程规范 §3.0）。
    const pureFiles = <String>[
      'lib/src/features/workspace/application/workspace_file_corpus_port.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_intent.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_reducer.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_state.dart',
    ];
    // store 是状态 owner：允许 flutter_riverpod。
    const ownerFiles = <String>[
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_store.dart',
    ];
    for (final path in pureFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains('riverpod')), reason: path);
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
    }
    for (final path in ownerFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
    }

    final reducer = File(
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_reducer.dart',
    ).readAsStringSync();
    expect(reducer, isNot(contains('Timer(')));
    expect(reducer, isNot(contains('Future<')));
    expect(reducer, isNot(contains('Directory(')));
  });

  test('workspace index and production mention chain do not use ChangeNotifier', () {
    final index = File(
      'lib/src/features/workspace/application/workspace_file_index_controller.dart',
    ).readAsStringSync();
    expect(index, isNot(contains('package:flutter/')));
    expect(index, isNot(contains('ChangeNotifier')));

    for (final path in const <String>[
      'lib/src/app/shell/ide_shell_controller.dart',
      'lib/src/app/conversation_workspace_slice/agent_conversation_workspace_store.dart',
      'lib/src/features/agent/presentation/agent_conversation_view_model.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('workspaceFilesProvider')), reason: path);
      expect(source, isNot(contains('workspaceFilesListenable')), reason: path);
      expect(source, isNot(contains('workspaceFilesIndexReady')), reason: path);
    }
  });

  test('batch 4a is closed and Shell cannot regain workspace ownership', () {
    for (final path in const <String>[
      'lib/main.dart',
      'lib/src/app/app.dart',
      'lib/src/app/shell/ide_shell_controller.dart',
      'lib/src/ui/features/ide/views/ide_home.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('workspaceSliceEnabled')), reason: path);
    }

    final shell = File(
      'lib/src/app/shell/ide_shell_controller.dart',
    ).readAsStringSync();
    for (final legacyOwner in const <String>[
      '_workspaceTree',
      '_expandedDirectoryPaths',
      '_projects',
      '_projectLastOpenedAtByPath',
      '_projectPath',
      '_currentFilePath',
      '_selectedTreePath',
      '_isLoadingProject',
    ]) {
      expect(shell, isNot(contains(legacyOwner)), reason: legacyOwner);
    }
    expect(shell, isNot(contains("import 'dart:io'")));
    expect(shell, isNot(contains('workspace_tree_builder.dart')));
    expect(shell, isNot(contains('buildWorkspaceDirectoryChildren(')));
    expect(shell, contains('workspaceSliceStore.loadProject(path)'));
  });
}

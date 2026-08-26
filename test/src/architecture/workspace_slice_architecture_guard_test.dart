import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace notifier owns state and Flutter stays out of application', () {
    const ownerFiles = <String>[
      'lib/src/features/workspace/application/workspace_notifier.dart',
      'lib/src/features/workspace/application/workspace_file_tree_notifier.dart',
      'lib/src/features/workspace/application/workspace_file_corpus.dart',
    ];
    const pureFiles = <String>[
      'lib/src/features/workspace/application/workspace_file_corpus_port.dart',
      'lib/src/features/workspace/application/workspace_restore_snapshot.dart',
      'lib/src/features/workspace/domain/workspace_project.dart',
      'lib/src/features/workspace/domain/workspace_directory_catalog.dart',
    ];
    for (final path in [...pureFiles, ...ownerFiles]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
    }
    for (final path in pureFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('riverpod')), reason: path);
    }

    final notifier = File(
      'lib/src/features/workspace/application/workspace_notifier.dart',
    ).readAsStringSync();
    expect(notifier, contains('typedef WorkspaceDirectoryPicker'));
    expect(notifier, isNot(contains('_Deferred')));

    final fileTree = File(
      'lib/src/features/workspace/application/workspace_file_tree_notifier.dart',
    ).readAsStringSync();
    expect(fileTree, contains('NotifierProvider.family'));
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

  test('Shell cannot regain workspace ownership', () {
    for (final path in const <String>[
      'lib/main.dart',
      'lib/src/app/app.dart',
      'lib/src/app/shell/ide_shell_controller.dart',
      'lib/src/ui/features/ide/views/ide_home.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('workspaceSliceEnabled')), reason: path);
      expect(source, isNot(contains('WorkspaceSliceStore')), reason: path);
      expect(
        source,
        isNot(contains('_DeferredWorkspaceSliceRunner')),
        reason: path,
      );
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
    expect(shell, contains('openOrActivate(path)'));
  });

  test('directory catalog IO lives in data, not domain', () {
    final domain = File(
      'lib/src/features/workspace/domain/workspace_directory_catalog.dart',
    ).readAsStringSync();
    expect(domain, isNot(contains("import 'dart:io'")));

    final data = File(
      'lib/src/features/workspace/data/io_workspace_directory_catalog.dart',
    ).readAsStringSync();
    expect(data, contains("import 'dart:io'"));
    expect(data, contains('IoWorkspaceDirectoryCatalog'));
  });
}

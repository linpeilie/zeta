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
      'lib/src/features/workspace/domain/workspace_directory_picker.dart',
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
    expect(notifier, contains('workspaceDirectoryPickerProvider'));
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

  test('目录选择器：端口在 domain，原生实现在 data，真实实现只由生产入口装', () {
    final picker = File(
      'lib/src/features/workspace/data/file_selector_workspace_directory_picker.dart',
    ).readAsStringSync();
    expect(
      picker,
      contains("import 'package:file_selector/file_selector.dart'"),
    );
    expect(picker, contains('FileSelectorWorkspaceDirectoryPicker'));

    // 平台 picker 不许再漏回 app 组合层。
    final overrides = File(
      'lib/src/app/workspace_slice/workspace_overrides.dart',
    ).readAsStringSync();
    expect(overrides, isNot(contains("package:file_selector/")));

    // 真实选择器只在 local 宿主装：ephemeral 也装的话，调用方就再也覆盖不掉这个
    // provider（同容器重复 override 会被 Riverpod 断言拦下），fake 进不来。
    final composition = File(
      'lib/src/app/composition/zeta_app_composition.dart',
    ).readAsStringSync();
    expect(
      composition,
      contains(
        'if (hostMode.usesNativeDialogs) systemDirectoryPickerOverride()',
      ),
    );

    // Widget 上不许再有任何注入参数：容器与依赖都归组合根。
    final app = File('lib/src/app/app.dart').readAsStringSync();
    expect(app, isNot(contains('directoryPicker')));
    expect(app, isNot(contains('ProviderContainer(')));
    expect(app, contains('required this.composition'));
  });
}

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('workspace reducer/store stay pure and Riverpod stays presentation-only', () {
    const applicationFiles = <String>[
      'lib/src/features/workspace/application/workspace_file_corpus_port.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_effect.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_intent.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_reducer.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_state.dart',
      'lib/src/features/workspace/application/workspace_slice/workspace_slice_store.dart',
    ];
    for (final path in applicationFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains('riverpod')), reason: path);
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
      'lib/src/features/agent/application/agent_thread_workspace_controller.dart',
      'lib/src/features/agent/presentation/agent_conversation_view_model.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('workspaceFilesProvider')), reason: path);
      expect(source, isNot(contains('workspaceFilesListenable')), reason: path);
      expect(source, isNot(contains('workspaceFilesIndexReady')), reason: path);
    }
  });

  test('batch 4a production entry remains explicitly enabled', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains('workspaceSliceEnabled: true'));
  });
}

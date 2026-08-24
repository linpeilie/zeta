import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IDE Session reducer/store stay pure and persistence stays in runner', () {
    // intent / effect / state / reducer / 端口是纯数据与纯函数：它们不发布状态，
    // 因此连纯 Dart 的 package:riverpod 都不该出现（工程规范 §3.0）。
    const pureFiles = <String>[
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart',
    ];
    // notifier 是状态 owner：允许 flutter_riverpod。
    const ownerFiles = <String>[
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart',
    ];
    for (final path in <String>[...pureFiles, ...ownerFiles]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
      expect(
        source,
        isNot(contains('/features/ide_session/data/')),
        reason: path,
      );
    }
    for (final path in pureFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('riverpod')), reason: path);
    }

    final reducer = File(
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart',
    ).readAsStringSync();
    expect(reducer, isNot(contains('Timer(')));
    expect(reducer, isNot(contains('Future<')));
    expect(reducer, isNot(contains('IdeSessionStore')));
  });

  test('v4 DTO and store do not depend on the runtime slice', () {
    for (final path in const <String>[
      'lib/src/features/ide_session/domain/ide_session_state.dart',
      'lib/src/features/ide_session/data/ide_session_store.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('ide_session_slice')), reason: path);
    }
  });

  test('batch 4b is closed and Shell only uses the slice operations port', () {
    for (final path in const <String>[
      'lib/main.dart',
      'lib/src/app/app.dart',
      'lib/src/app/shell/ide_shell_controller.dart',
      'lib/src/ui/features/ide/views/ide_home.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('ideSessionSliceEnabled')), reason: path);
    }

    final shell = File(
      'lib/src/app/shell/ide_shell_controller.dart',
    ).readAsStringSync();
    // 切片所有权归容器：不得再出现手工组合对象或反向绑定的注册表。
    expect(shell, isNot(contains('IdeSessionSliceComposition')));
    expect(shell, isNot(contains('IdeSessionStore')));
    expect(shell, isNot(contains('IdeSessionPersistenceCoordinator')));
    expect(shell, isNot(contains('_sessionCoordinator')));
    expect(shell, isNot(contains('_workbenchLayout')));
    expect(shell, isNot(contains('_initialRestoreCompleted')));
    expect(shell, isNot(contains('_initialRestoreCompleter')));
    expect(shell, contains('required this.ideSessionOperations'));
  });
}

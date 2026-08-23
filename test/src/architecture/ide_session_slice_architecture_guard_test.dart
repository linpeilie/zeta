import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('IDE Session reducer/store stay pure and persistence stays in runner', () {
    const applicationFiles = <String>[
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_effect.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_intent.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_operations.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_reducer.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart',
      'lib/src/features/ide_session/application/ide_session_slice/ide_session_slice_store.dart',
    ];
    for (final path in applicationFiles) {
      final source = File(path).readAsStringSync();
      expect(source, isNot(contains('package:flutter/')), reason: path);
      expect(source, isNot(contains('riverpod')), reason: path);
      expect(source, isNot(contains("import 'dart:io'")), reason: path);
      expect(
        source,
        isNot(contains('/features/ide_session/data/')),
        reason: path,
      );
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

  test('batch 4 session and workspace production entries remain disabled', () {
    final mainSource = File('lib/main.dart').readAsStringSync();
    expect(mainSource, contains('workspaceSliceEnabled: false'));
    expect(mainSource, contains('ideSessionSliceEnabled: false'));
  });
}

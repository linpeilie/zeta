import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('root snapshot is an on-demand projection, never a watchable store', () {
    final snapshot = File(
      'lib/src/app/composition/zeta_state_snapshot.dart',
    ).readAsStringSync();
    expect(snapshot, isNot(contains('package:flutter/')));
    expect(snapshot, isNot(contains('riverpod')));
    expect(snapshot, isNot(contains('ChangeNotifier')));
    expect(snapshot, isNot(contains('ValueNotifier')));
    expect(snapshot, isNot(contains('addListener(')));
    expect(snapshot, isNot(contains('subscribe(')));
    expect(snapshot, isNot(contains('toJson(')));
    expect(snapshot, isNot(contains('encode(')));

    for (final path in const <String>[
      'lib/src/app/app.dart',
      'lib/src/ui/features/ide/views/ide_home.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        source,
        isNot(
          matches(
            RegExp(
              r'(ref\.watch|ref\.listen|subscribe)\s*\([^;]*ZetaStateSnapshot',
              multiLine: true,
            ),
          ),
        ),
        reason: path,
      );
    }
  });

  test('root conversation and management projections exclude body fields', () {
    final snapshot = File(
      'lib/src/app/composition/zeta_state_snapshot.dart',
    ).readAsStringSync();
    for (final forbidden in const <String>[
      'AgentConversationSliceState',
      'AgentConfigurationDocument',
      'AgentLogEntry',
      'AgentProviderRawPayload',
      '.title',
      '.preview',
      '.content',
      '.logs',
    ]) {
      expect(snapshot, isNot(contains(forbidden)), reason: forbidden);
    }
  });
}

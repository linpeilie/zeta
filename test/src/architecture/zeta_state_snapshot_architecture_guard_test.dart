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

    // P4-6：覆盖面从两个文件扩到**全部生产 Dart 文件**。
    // 只盯 app.dart / ide_home.dart 的话，任何新文件都能悄悄把 root snapshot
    // 变成可订阅的状态源。
    final subscribePattern = RegExp(
      r'(ref\.watch|ref\.listen|subscribe)\s*\([^;]*ZetaStateSnapshot',
      multiLine: true,
    );
    final production = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList(growable: false);

    expect(production, isNotEmpty, reason: '扫不到生产文件说明守卫本身失效了');

    final offenders = <String>[
      for (final file in production)
        if (subscribePattern.hasMatch(file.readAsStringSync())) file.path,
    ];

    expect(
      offenders,
      isEmpty,
      reason: 'root snapshot 只能按需同步读取，不得被订阅：$offenders',
    );
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

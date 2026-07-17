import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/local_history/grok_updates_history_parser.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_session_update_mapper.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_stream_identity.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

import '../../../../../testing/fixture_reader.dart';
import 'grok_canonical_signature.dart';

void main() {
  test('Grok live/history share the complete canonical signature', () {
    final fixture = readFixtureJsonMap(
      'agent_stream_identity/grok_history.json',
    );
    final fixtureTurns = _maps(fixture['turns']);
    final expected = _maps(
      fixture['expectedCanonicalSignature'],
    ).map(GrokCanonicalEntrySignature.fromJson).toList(growable: false);

    final liveTurns = _mapLiveTurns(fixtureTurns);
    final historyContent = fixtureTurns
        .expand((turn) => _maps(turn['records']))
        .map(jsonEncode)
        .join('\n');
    const parser = GrokUpdatesHistoryParser();
    final history = parser.parse(
      threadId: 'grok-session-redacted',
      content: historyContent,
    );

    final liveSignature = GrokCanonicalComparator.fromLiveTurns(liveTurns);
    final historySignature = GrokCanonicalComparator.fromHistory(history);

    expect(liveSignature, expected);
    expect(historySignature, expected);
    expect(
      GrokCanonicalComparator.compare(liveSignature, historySignature),
      isEmpty,
    );

    // eventId 不进入 history entryId；同 source message 在 tool 前后形成两段。
    final agentMessages = history.turns.first.entries
        .whereType<AgentHistoryMessageEntry>()
        .where((entry) => entry.role == AgentMessageRole.agent)
        .toList();
    expect(agentMessages, hasLength(2));
    expect(
      agentMessages.map((entry) => entry.sourceMessageId),
      everyElement('grok-source-message-redacted'),
    );
    expect(
      agentMessages.map((entry) => entry.id),
      everyElement(isNot(contains('grok-history-agent'))),
    );

    // 每次 parse 都使用 fresh reducer；重复解析相同 eventId 仍得到稳定结果。
    final secondHistory = parser.parse(
      threadId: 'grok-session-redacted',
      content: historyContent,
    );
    expect(
      secondHistory.turns.map((turn) => turn.id),
      history.turns.map((turn) => turn.id),
    );
    expect(
      GrokCanonicalComparator.fromHistory(secondHistory),
      historySignature,
    );
  });
}

List<List<AgentEvent>> _mapLiveTurns(List<Map<String, Object?>> fixtureTurns) {
  final mapper = GrokSessionUpdateMapper();
  const runtimeScope = AgentRuntimeScope(
    runtimeId: 'grok-live-canonical-regression',
    connectionEpoch: 73,
  );
  final result = <List<AgentEvent>>[];
  addTearDown(mapper.dispose);

  for (final fixtureTurn in fixtureTurns) {
    final turnId = fixtureTurn['turnId']! as String;
    final records = _maps(fixtureTurn['records']);
    final firstParams = _map(records.first['params']);
    final sessionId = firstParams['sessionId']! as String;
    mapper.beginTurn(
      runtimeScope: runtimeScope,
      sessionId: sessionId,
      turnId: turnId,
    );

    final events = <AgentEvent>[];
    for (final record in records) {
      final method = record['method']! as String;
      events.addAll(
        mapper
            .mapSessionUpdate(
              params: _map(record['params']),
              runningTurnId: turnId,
              runtimeScope: runtimeScope,
              terminalSource: method.startsWith('_x.ai/')
                  ? GrokTerminalSource.xaiNotification
                  : GrokTerminalSource.standardNotification,
            )
            .events,
      );
    }
    result.add(List<AgentEvent>.unmodifiable(events));
  }
  return List<List<AgentEvent>>.unmodifiable(result);
}

List<Map<String, Object?>> _maps(Object? value) {
  return (value! as List<Object?>).map(_map).toList(growable: false);
}

Map<String, Object?> _map(Object? value) {
  return (value! as Map<Object?, Object?>).map(
    (key, item) => MapEntry(key.toString(), item),
  );
}

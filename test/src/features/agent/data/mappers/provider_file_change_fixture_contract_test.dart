import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import '../../../../testing/fixture_reader.dart';

const _fixtureRoot = 'agent_file_change_evidence';
const _fixtureNames = <String>[
  'grok_edit_1_0_0.json',
  'claude_code_edit_write_2_1_227.json',
  'codex_command_edit_0_144_1.json',
  'codex_patch_apply_end_history_0_144_1.json',
  'codex_structured_file_change_schema_0_144_5.json',
];

void main() {
  late Map<String, Object?> manifest;
  late Map<String, Map<String, Object?>> fixtures;

  setUpAll(() {
    manifest = readFixtureJsonMap('$_fixtureRoot/manifest.json');
    fixtures = <String, Map<String, Object?>>{
      for (final name in _fixtureNames)
        name: readFixtureJsonMap('$_fixtureRoot/$name'),
    };
  });

  group('Provider file-change fixture contract', () {
    test('manifest distinguishes real shapes from schema construction', () {
      expect(manifest['formatVersion'], 1);
      expect(
        manifest['versionPolicy'],
        'Versions identify evidence provenance only. They are not runtime gates.',
      );

      final entries = _list(manifest['fixtures']).map(_map).toList();
      expect(entries, hasLength(5));
      expect(
        entries.map((entry) => _string(entry['path'])).toSet(),
        _fixtureNames.toSet(),
      );

      _expectManifestEntry(
        entries,
        path: 'grok_edit_1_0_0.json',
        provider: 'grok',
        sourceKind: 'sanitizedRealShape',
        sourceVersion: '1.0.0',
      );
      _expectManifestEntry(
        entries,
        path: 'claude_code_edit_write_2_1_227.json',
        provider: 'claude_code',
        sourceKind: 'sanitizedRealShape',
        sourceVersion: '2.1.227',
      );
      _expectManifestEntry(
        entries,
        path: 'codex_command_edit_0_144_1.json',
        provider: 'codex',
        sourceKind: 'sanitizedRealShape',
        sourceVersion: '0.144.1',
      );
      _expectManifestEntry(
        entries,
        path: 'codex_patch_apply_end_history_0_144_1.json',
        provider: 'codex',
        sourceKind: 'sanitizedRealShape',
        sourceVersion: '0.144.1',
      );
      _expectManifestEntry(
        entries,
        path: 'codex_structured_file_change_schema_0_144_5.json',
        provider: 'codex',
        sourceKind: 'schemaConstructed',
        sourceVersion: '0.144.5',
      );
    });

    test('Grok real shape repeats old/new evidence at completion', () {
      final fixture = fixtures['grok_edit_1_0_0.json']!;
      _expectFixtureMetadata(
        fixture,
        provider: 'grok',
        sourceKind: 'sanitizedRealShape',
        versionKey: 'cliVersion',
        version: '1.0.0',
      );

      final events = _list(fixture['events']);
      expect(events, hasLength(4));
      final detailUpdate = _update(_map(events[1]));
      final terminalUpdate = _update(_map(events[2]));

      expect(detailUpdate['sessionUpdate'], 'tool_call_update');
      expect(detailUpdate['kind'], 'edit');
      final detailDiff = _map(_list(detailUpdate['content']).single);
      expect(detailDiff['type'], 'diff');
      expect(detailDiff['path'], '<WORKSPACE_REDACTED>/sample.txt');
      expect(detailDiff['oldText'], '[BEFORE_REDACTED]\n');
      expect(detailDiff['newText'], '[AFTER_REDACTED]\n');

      expect(terminalUpdate['status'], 'completed');
      expect(terminalUpdate['content'], detailUpdate['content']);
      final checks = _map(fixture['_captureChecks']);
      expect(checks['fileContentChanged'], isTrue);
      expect(checks['stopReason'], 'end_turn');
    });

    test('Claude real shapes keep evidence in tool_use, not tool_result', () {
      final fixture = fixtures['claude_code_edit_write_2_1_227.json']!;
      _expectFixtureMetadata(
        fixture,
        provider: 'claude_code',
        sourceKind: 'sanitizedRealShape',
        versionKey: 'cliVersion',
        version: '2.1.227',
      );

      final scenarios = _list(fixture['scenarios']).map(_map).toList();
      final edit = _named(scenarios, 'edit');
      final write = _named(scenarios, 'write');

      final editInput = _toolUseInput(edit, expectedToolName: 'Edit');
      expect(editInput.keys.toSet(), <String>{
        'file_path',
        'old_string',
        'new_string',
        'replace_all',
      });
      expect(editInput['replace_all'], isFalse);
      _expectPlainToolResult(edit);

      final writeInput = _toolUseInput(write, expectedToolName: 'Write');
      expect(writeInput.keys.toSet(), <String>{'file_path', 'content'});
      _expectPlainToolResult(write);
    });

    test('current Codex real shape is command-only despite file mutation', () {
      final fixture = fixtures['codex_command_edit_0_144_1.json']!;
      _expectFixtureMetadata(
        fixture,
        provider: 'codex',
        sourceKind: 'sanitizedRealShape',
        versionKey: 'cliVersion',
        version: '0.144.1',
      );

      final events = _list(fixture['events']).map(_map).toList();
      expect(events.map((event) => _string(event['method'])), <String>[
        'item/commandExecution/requestApproval',
        'item/started',
        'item/completed',
      ]);
      expect(
        events.any(
          (event) =>
              _string(event['method']).contains('fileChange') ||
              _string(event['method']) == 'turn/diff/updated',
        ),
        isFalse,
      );

      final completedItem = _map(_map(events.last['params'])['item']);
      expect(completedItem['type'], 'commandExecution');
      expect(completedItem['status'], 'completed');
      expect(
        _map(_list(completedItem['commandActions']).single)['type'],
        'unknown',
      );

      final checks = _map(fixture['_captureChecks']);
      expect(checks['fileContentChanged'], isTrue);
      expect(checks['fileChangeStartedCount'], 0);
      expect(checks['fileChangePatchUpdatedCount'], 0);
      expect(checks['fileChangeCompletedCount'], 0);
      expect(checks['turnDiffUpdatedCount'], 0);
    });

    test('Codex local JSONL keeps structured patch_apply_end shapes', () {
      final fixture = fixtures['codex_patch_apply_end_history_0_144_1.json']!;
      _expectFixtureMetadata(
        fixture,
        provider: 'codex',
        sourceKind: 'sanitizedRealShape',
        versionKey: 'cliVersion',
        version: '0.144.1',
      );

      final records = _list(fixture['records']).map(_map).toList();
      final responseItems = records
          .where((record) => record['type'] == 'response_item')
          .map((record) => _map(record['payload']))
          .toList(growable: false);
      expect(responseItems, hasLength(1));
      expect(responseItems.single['type'], 'custom_tool_call');
      expect(responseItems.single['name'], 'exec');

      final patchEnds = records
          .where((record) => record['type'] == 'event_msg')
          .map((record) => _map(record['payload']))
          .where((payload) => payload['type'] == 'patch_apply_end')
          .toList(growable: false);
      expect(patchEnds, hasLength(3));
      final changes = patchEnds
          .map((payload) => _map(payload['changes']).values.single)
          .map(_map)
          .toList(growable: false);
      expect(changes.map((change) => change['type']), <String>[
        'update',
        'add',
        'delete',
      ]);
      expect(changes[0]['unified_diff'], isA<String>());
      expect(changes[1]['content'], isA<String>());
      expect(changes[2]['content'], isA<String>());
    });

    test('Codex structured fixture is labelled schema-only', () {
      final fixture =
          fixtures['codex_structured_file_change_schema_0_144_5.json']!;
      _expectFixtureMetadata(
        fixture,
        provider: 'codex',
        sourceKind: 'schemaConstructed',
        versionKey: 'schemaVersion',
        version: '0.144.5',
      );

      final metadata = _map(fixture['_fixture']);
      expect(
        _string(metadata['provenance']),
        contains('repository-pinned stable'),
      );
      expect(_string(metadata['privacy']), contains('not labelled as a real'));

      final events = _list(fixture['events']).map(_map).toList();
      expect(events.map((event) => _string(event['method'])), <String>[
        'item/started',
        'item/fileChange/patchUpdated',
        'item/completed',
        'turn/diff/updated',
      ]);

      final patchUpdate = _map(events[1]['params']);
      final change = _map(_list(patchUpdate['changes']).single);
      expect(change['path'], '<WORKSPACE_REDACTED>/sample.txt');
      expect(_map(change['kind'])['type'], 'update');
      expect(_string(change['diff']), contains('[BEFORE_REDACTED]'));
      expect(_string(change['diff']), contains('[AFTER_REDACTED]'));

      final threadReadItem = _map(fixture['threadReadItem']);
      expect(threadReadItem['type'], 'fileChange');
      expect(_list(threadReadItem['changes']), hasLength(1));
    });

    test('all fixtures satisfy the privacy sentinel contract', () {
      for (final entry in fixtures.entries) {
        final encoded = jsonEncode(entry.value);
        expect(
          encoded,
          isNot(matches(RegExp(r'[A-Za-z]:[\\/](?:Users|Development)'))),
          reason: '${entry.key} contains a real-looking Windows path',
        );
        expect(
          encoded,
          isNot(matches(RegExp(r'/(?:Users|home)/'))),
          reason: '${entry.key} contains a real-looking POSIX home path',
        );
        expect(encoded, isNot(contains('Bearer ')));
        expect(encoded, isNot(contains('BEGIN PRIVATE KEY')));
        _expectSensitiveValuesRedacted(entry.value, fixtureName: entry.key);
      }
    });
  });
}

void _expectManifestEntry(
  List<Map<String, Object?>> entries, {
  required String path,
  required String provider,
  required String sourceKind,
  required String sourceVersion,
}) {
  final entry = entries.singleWhere((item) => item['path'] == path);
  expect(entry['provider'], provider);
  expect(entry['sourceKind'], sourceKind);
  expect(entry['sourceVersion'], sourceVersion);
}

void _expectFixtureMetadata(
  Map<String, Object?> fixture, {
  required String provider,
  required String sourceKind,
  required String versionKey,
  required String version,
}) {
  final metadata = _map(fixture['_fixture']);
  expect(metadata['formatVersion'], 1);
  expect(metadata['provider'], provider);
  expect(metadata['sourceKind'], sourceKind);
  expect(metadata[versionKey], version);
  expect(_string(metadata['privacy']), isNotEmpty);
  expect(_string(metadata['provenance']), isNotEmpty);
}

Map<String, Object?> _update(Map<String, Object?> event) {
  return _map(_map(event['params'])['update']);
}

Map<String, Object?> _named(List<Map<String, Object?>> scenarios, String name) {
  return scenarios.singleWhere((scenario) => scenario['name'] == name);
}

Map<String, Object?> _toolUseInput(
  Map<String, Object?> scenario, {
  required String expectedToolName,
}) {
  final frames = _list(scenario['frames']).map(_map).toList();
  final assistantMessage = _map(frames.first['message']);
  final toolUse = _map(_list(assistantMessage['content']).single);
  expect(toolUse['type'], 'tool_use');
  expect(toolUse['name'], expectedToolName);
  return _map(toolUse['input']);
}

void _expectPlainToolResult(Map<String, Object?> scenario) {
  final frames = _list(scenario['frames']).map(_map).toList();
  final userMessage = _map(frames[1]['message']);
  final toolResult = _map(_list(userMessage['content']).single);
  expect(toolResult['type'], 'tool_result');
  expect(toolResult.containsKey('is_error'), isFalse);
  expect(toolResult['content'], '[TOOL_RESULT_REDACTED]');
  expect(_map(frames.last)['subtype'], 'success');
  expect(frames.last['is_error'], isFalse);
}

const _sensitiveTextKeys = <String>{
  'aggregatedOutput',
  'command',
  'content',
  'cwd',
  'diff',
  'file_path',
  'new_string',
  'newText',
  'old_string',
  'oldText',
  'path',
  'title',
};

const _identityKeys = <String>{
  'eventId',
  'id',
  'itemId',
  'requestId',
  'sessionId',
  'session_id',
  'threadId',
  'toolCallId',
  'tool_use_id',
  'turnId',
  'uuid',
};

void _expectSensitiveValuesRedacted(
  Object? value, {
  required String fixtureName,
  String? key,
}) {
  if (value is Map) {
    for (final entry in value.entries) {
      _expectSensitiveValuesRedacted(
        entry.value,
        fixtureName: fixtureName,
        key: entry.key.toString(),
      );
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _expectSensitiveValuesRedacted(item, fixtureName: fixtureName, key: key);
    }
    return;
  }
  if (value is! String || key == null) {
    return;
  }
  if (_sensitiveTextKeys.contains(key)) {
    expect(
      value.toUpperCase(),
      contains('REDACTED'),
      reason: '$fixtureName has non-redacted $key',
    );
  }
  if (_identityKeys.contains(key)) {
    expect(
      value.toLowerCase(),
      contains('redacted'),
      reason: '$fixtureName has non-redacted $key',
    );
  }
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw StateError('Expected a JSON object, got ${value.runtimeType}');
  }
  return value.map(
    (key, dynamic item) => MapEntry(key.toString(), item as Object?),
  );
}

List<Object?> _list(Object? value) {
  if (value is! List) {
    throw StateError('Expected a JSON list, got ${value.runtimeType}');
  }
  return value.cast<Object?>();
}

String _string(Object? value) {
  if (value is! String) {
    throw StateError('Expected a JSON string, got ${value.runtimeType}');
  }
  return value;
}

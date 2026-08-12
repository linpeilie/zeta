import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _fixtureRoot =
    'test/src/features/agent/data/datasources/claude_code/fixtures';
const _fixtureNames = <String>[
  'initialize_reverse_source_schema.json',
  'initialize_2_1_228_redacted.json',
  'auth_status_2_1_228_redacted.json',
  'oauth_usage_schema_redacted.json',
];

void main() {
  late Map<String, Map<String, Object?>> fixtures;

  setUpAll(() {
    fixtures = <String, Map<String, Object?>>{
      for (final name in _fixtureNames) name: _readFixture(name),
    };
  });

  group('Claude Code metadata fixture contract', () {
    test('distinguishes constructed schema from the local real shape', () {
      final reverseSource = fixtures['initialize_reverse_source_schema.json']!;
      final local = fixtures['initialize_2_1_228_redacted.json']!;

      expect(_metadata(reverseSource)['sourceKind'], 'schemaConstructed');
      expect(_metadata(reverseSource)['sourceVersion'], '2.8.4');
      expect(jsonEncode(reverseSource), isNot(contains('resolvedModel')));

      expect(_metadata(local)['sourceKind'], 'sanitizedRealShape');
      expect(_metadata(local)['cliVersion'], '2.1.228');
      expect(_metadata(local)['os'], 'macOS');
      expect(_metadata(local)['architecture'], 'arm64');
      expect(
        _models(local).every((model) => model['resolvedModel'] is String),
        isTrue,
      );
      expect(_initializePayload(local)['futureMetadata'], isA<Map>());
    });

    test('preserves model order and has exactly one default option', () {
      expect(
        _models(
          fixtures['initialize_reverse_source_schema.json']!,
        ).map((model) => model['value']),
        <String>['default', 'sonnet', 'opus', 'haiku'],
      );
      expect(
        _models(
          fixtures['initialize_2_1_228_redacted.json']!,
        ).map((model) => model['value']),
        <String>['default', 'sonnet', 'claude-fable-5[1m]', 'opus', 'haiku'],
      );

      for (final fixture in fixtures.entries.where(
        (entry) => entry.key.startsWith('initialize_'),
      )) {
        expect(
          _models(fixture.value).where((model) => model['value'] == 'default'),
          hasLength(1),
          reason: '${fixture.key} must expose exactly one default option',
        );
      }
    });

    test('keeps only whitelisted account and authentication fields', () {
      for (final name in <String>[
        'initialize_reverse_source_schema.json',
        'initialize_2_1_228_redacted.json',
      ]) {
        final account = _map(_initializePayload(fixtures[name]!)['account']);
        expect(account.keys.toSet(), <String>{
          'subscriptionType',
          'apiProvider',
        });
      }

      final auth = Map<String, Object?>.of(
        fixtures['auth_status_2_1_228_redacted.json']!,
      )..remove('_fixture');
      expect(auth.keys.toSet(), <String>{
        'loggedIn',
        'authMethod',
        'apiProvider',
        'subscriptionType',
      });
      expect(auth['loggedIn'], isTrue);
    });

    test('keeps the quota fixture to its minimal consumed shape', () {
      final usage = Map<String, Object?>.of(
        fixtures['oauth_usage_schema_redacted.json']!,
      )..remove('_fixture');
      expect(usage.keys.toSet(), <String>{
        'five_hour',
        'seven_day',
        'seven_day_sonnet',
        'extra_usage',
      });
      expect(_map(usage['extra_usage'])['monthly_limit'], isNull);
    });

    test('all fixtures satisfy account identity and privacy sentinels', () {
      for (final fixture in fixtures.entries) {
        final encoded = jsonEncode(fixture.value);
        expect(
          encoded,
          isNot(matches(RegExp(r'[A-Za-z]:[\\/](?:Users|Development)'))),
          reason: '${fixture.key} contains a real-looking Windows path',
        );
        expect(
          encoded,
          isNot(matches(RegExp(r'/(?:Users|home)/'))),
          reason: '${fixture.key} contains a real-looking POSIX home path',
        );
        expect(encoded, isNot(contains('Bearer ')));
        expect(encoded, isNot(contains('BEGIN PRIVATE KEY')));
        expect(encoded, isNot(contains('sk-ant-')));
        _expectNoSensitiveKeys(fixture.value, fixtureName: fixture.key);
      }
    });
  });
}

Map<String, Object?> _readFixture(String name) {
  final decoded = jsonDecode(File('$_fixtureRoot/$name').readAsStringSync());
  return _map(decoded);
}

Map<String, Object?> _metadata(Map<String, Object?> fixture) {
  return _map(fixture['_fixture']);
}

Map<String, Object?> _initializePayload(Map<String, Object?> fixture) {
  final envelope = _map(fixture['response']);
  expect(envelope['subtype'], 'success');
  return _map(envelope['response']);
}

List<Map<String, Object?>> _models(Map<String, Object?> fixture) {
  return _list(
    _initializePayload(fixture)['models'],
  ).map(_map).toList(growable: false);
}

const _sensitiveKeys = <String>{
  'accesstoken',
  'refreshtoken',
  'email',
  'organization',
  'organizationid',
  'accountuuid',
  'userid',
  'pid',
  'cwd',
  'path',
  'stderr',
};

void _expectNoSensitiveKeys(Object? value, {required String fixtureName}) {
  if (value is Map) {
    for (final entry in value.entries) {
      final normalizedKey = entry.key
          .toString()
          .replaceAll(RegExp(r'[^A-Za-z0-9]'), '')
          .toLowerCase();
      expect(
        _sensitiveKeys,
        isNot(contains(normalizedKey)),
        reason: '$fixtureName contains prohibited key ${entry.key}',
      );
      _expectNoSensitiveKeys(entry.value, fixtureName: fixtureName);
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _expectNoSensitiveKeys(item, fixtureName: fixtureName);
    }
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

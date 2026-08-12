import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_initialize_metadata_mapper.dart';

const _fixtureRoot =
    'test/src/features/agent/data/datasources/claude_code/fixtures';

void main() {
  group('mapClaudeCodeInitializeMetadata', () {
    test('maps the local 2.1.228 shape in CLI order', () {
      // Arrange
      final raw = _readFixture('initialize_2_1_228_redacted.json');

      // Act
      final result = mapClaudeCodeInitializeMetadata(raw);

      // Assert
      expect(result.models.models.map((model) => model.id), <String>[
        'default',
        'sonnet',
        'claude-fable-5[1m]',
        'opus',
        'haiku',
      ]);
      expect(result.models.models.map((model) => model.displayName), <String>[
        'Default (recommended)',
        'Sonnet',
        'Fable',
        'Opus',
        'Haiku',
      ]);
      expect(result.subscriptionType, 'Claude Pro');
      expect(
        result.models.models.where((model) => model.isDefault),
        hasLength(1),
      );
      expect(result.models.models.first.id, 'default');
      expect(result.models.models.first.model, 'default');
    });

    test('maps the reverse-source shape without resolvedModel', () {
      // Arrange
      final raw = _readFixture('initialize_reverse_source_schema.json');

      // Act
      final result = mapClaudeCodeInitializeMetadata(raw);

      // Assert
      expect(result.models.models.map((model) => model.id), <String>[
        'default',
        'sonnet',
        'opus',
        'haiku',
      ]);
      expect(result.models.models.last.description, isNull);
      expect(result.subscriptionType, 'Claude Pro');
    });

    test('uses name fallback, skips duplicates, and preserves first order', () {
      // Arrange
      final raw = _successFrame(
        models: <Object?>[
          <String, Object?>{
            'name': ' legacy-name ',
            'displayName': ' Legacy display ',
            'description': ' Legacy description ',
          },
          <String, Object?>{'value': 'legacy-name', 'displayName': 'Duplicate'},
          <String, Object?>{'value': 'default', 'displayName': 'Default'},
          <String, Object?>{'value': ' '},
          <String, Object?>{'name': 7},
          'malformed',
        ],
        account: <String, Object?>{
          'subscriptionType': ' Claude Team ',
          'email': 'must-not-be-projected',
          'organization': <String, Object?>{'name': 'ignored'},
        },
      );

      // Act
      final result = mapClaudeCodeInitializeMetadata(raw);

      // Assert
      expect(result.models.models.map((model) => model.id), <String>[
        'legacy-name',
        'default',
      ]);
      expect(result.models.models.first.model, 'legacy-name');
      expect(result.models.models.first.displayName, 'Legacy display');
      expect(result.models.models.first.description, 'Legacy description');
      expect(result.subscriptionType, 'Claude Team');
    });

    test('does not project raw or unimplemented model capabilities', () {
      final result = mapClaudeCodeInitializeMetadata(
        _readFixture('initialize_2_1_228_redacted.json'),
      );

      for (final model in result.models.models) {
        expect(model.raw, isEmpty);
        expect(model.supportedReasoningEfforts, isEmpty);
        expect(model.defaultReasoningEffort, isNull);
        expect(model.serviceTiers, isEmpty);
        expect(model.defaultServiceTier, isNull);
        expect(model.contextWindowTokens, isNull);
      }
    });

    test('returns empty for failed, empty, and malformed envelopes', () {
      expect(mapClaudeCodeInitializeMetadata(null), _isEmptyMetadata);
      expect(
        mapClaudeCodeInitializeMetadata(<String, Object?>{}),
        _isEmptyMetadata,
      );
      expect(
        mapClaudeCodeInitializeMetadata(<String, Object?>{
          'type': 'control_response',
          'response': <String, Object?>{
            'subtype': 'error',
            'response': <String, Object?>{
              'models': <Object?>[
                <String, Object?>{'value': 'must-not-map'},
              ],
            },
          },
        }),
        _isEmptyMetadata,
      );
      expect(
        mapClaudeCodeInitializeMetadata(<String, Object?>{
          'type': 'assistant',
          'response': <String, Object?>{
            'subtype': 'success',
            'response': <String, Object?>{},
          },
        }),
        _isEmptyMetadata,
      );
    });

    test('keeps plan metadata when the models field is damaged', () {
      final result = mapClaudeCodeInitializeMetadata(
        _successFrame(
          models: 'invalid',
          account: <String, Object?>{'subscriptionType': 'Claude Enterprise'},
        ),
      );

      expect(result.models.models, isEmpty);
      expect(result.subscriptionType, 'Claude Enterprise');
    });
  });
}

final Matcher _isEmptyMetadata = isA<ClaudeCodeCliMetadataSnapshot>()
    .having((value) => value.models.models, 'models', isEmpty)
    .having((value) => value.subscriptionType, 'subscriptionType', isNull);

Map<String, Object?> _readFixture(String name) {
  final decoded = jsonDecode(File('$_fixtureRoot/$name').readAsStringSync());
  return _map(decoded);
}

Map<String, Object?> _successFrame({
  required Object? models,
  required Map<String, Object?> account,
}) {
  return <String, Object?>{
    'type': 'control_response',
    'unknownEnvelopeField': true,
    'response': <String, Object?>{
      'subtype': 'success',
      'request_id': 'request_redacted',
      'response': <String, Object?>{
        'models': models,
        'account': account,
        'futureMetadata': <String, Object?>{'mustBeIgnored': true},
      },
    },
  };
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw StateError('Expected a JSON object, got ${value.runtimeType}');
  }
  return value.map(
    (key, dynamic item) => MapEntry(key.toString(), item as Object?),
  );
}

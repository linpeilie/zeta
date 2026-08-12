import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/claude_code_model_catalog_mapper.dart';

void main() {
  group('mapClaudeCodeModelCatalog', () {
    test('maps valid models in order and keeps declared capabilities', () {
      // Arrange
      final capabilities = <String, Object?>{
        'effort': <String, Object?>{'supported': true},
        'thinking': true,
        'image_input': false,
      };
      final raw = <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': 'claude-opus-4-7',
            'display_name': 'Claude Opus 4.7',
            'max_input_tokens': 200000,
            'capabilities': capabilities,
          },
          <String, Object?>{
            'id': 'claude-sonnet-4-6',
            'display_name': 'Claude Sonnet 4.6',
            'max_input_tokens': 200000.0,
          },
          <String, Object?>{
            'id': 'sonnet-later',
            'display_name': 'Later Sonnet',
          },
          <String, Object?>{'display_name': 'Missing id'},
          'malformed',
        ],
      };

      // Act
      final result = mapClaudeCodeModelCatalog(raw);

      // Assert
      expect(result.models.map((model) => model.id), <String>[
        'claude-opus-4-7',
        'claude-sonnet-4-6',
        'sonnet-later',
      ]);
      expect(result.models.first.model, 'claude-opus-4-7');
      expect(result.models.first.displayName, 'Claude Opus 4.7');
      expect(result.models.first.contextWindowTokens, 200000);
      expect(result.models.first.raw, <String, Object?>{
        'capabilities': capabilities,
      });
      expect(result.models[1].isDefault, isTrue);
      expect(result.models[2].isDefault, isFalse);
      expect(result.models[1].contextWindowTokens, 200000);
      expect(result.nextCursor, isNull);
    });

    test('returns an empty directory for malformed payloads', () {
      expect(mapClaudeCodeModelCatalog(null).models, isEmpty);
      expect(
        mapClaudeCodeModelCatalog(<String, Object?>{'data': 'invalid'}).models,
        isEmpty,
      );
    });
  });
}

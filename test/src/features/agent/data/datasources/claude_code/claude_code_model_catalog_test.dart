import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_model_catalog.dart';

void main() {
  group('ClaudeCodeModelCatalog', () {
    test('contains pinned models and CLI aliases in stable order', () {
      // Arrange
      const catalog = ClaudeCodeModelCatalog();

      // Act
      final result = catalog.listModels();

      // Assert
      expect(result.models.map((model) => model.id), <String>[
        'claude-opus-4-7',
        'claude-sonnet-4-6',
        'claude-haiku-4-5-20251001',
        'opus',
        'sonnet',
        'haiku',
      ]);
      expect(result.models.every((model) => model.id == model.model), isTrue);
      expect(
        result.models.where(
          (model) =>
              const <String>{'opus', 'sonnet', 'haiku'}.contains(model.id),
        ),
        hasLength(3),
      );
    });

    test('marks only the stable Sonnet alias as default', () {
      // Arrange
      const catalog = ClaudeCodeModelCatalog();

      // Act
      final defaults = catalog
          .listModels()
          .models
          .where((model) => model.isDefault)
          .toList(growable: false);

      // Assert
      expect(defaults, hasLength(1));
      expect(defaults.single.id, 'sonnet');
    });
  });
}

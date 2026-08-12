import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_model_catalog.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_oauth_credentials_reader.dart';

void main() {
  group('ClaudeCodeModelCatalog', () {
    test('contains pinned models and CLI aliases in stable order', () async {
      // Arrange
      final catalog = ClaudeCodeModelCatalog(
        accountDataEnrichmentEnabled: false,
      );

      // Act
      final result = await catalog.listModels();

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

    test('marks only the stable Sonnet alias as default', () async {
      // Arrange
      final catalog = ClaudeCodeModelCatalog(
        accountDataEnrichmentEnabled: false,
      );

      // Act
      final defaults = (await catalog.listModels()).models
          .where((model) => model.isDefault)
          .toList(growable: false);

      // Assert
      expect(defaults, hasLength(1));
      expect(defaults.single.id, 'sonnet');
    });

    test('uses dynamic models and caches a successful response', () async {
      // Arrange
      var credentialsReads = 0;
      final remote = _RecordingRemoteModels(
        responses: <Map<String, Object?>?>[_dynamicResponse('claude-sonnet-5')],
      );
      final catalog = ClaudeCodeModelCatalog(
        credentialsLoader: () async {
          credentialsReads += 1;
          return _credentials;
        },
        remoteModelsLoader: remote.load,
      );

      // Act
      final first = await catalog.listModels();
      final cached = await catalog.listModels();

      // Assert
      expect(first.models.single.id, 'claude-sonnet-5');
      expect(cached, same(first));
      expect(credentialsReads, 1);
      expect(remote.callCount, 1);
      expect(remote.subscriptionOAuthValues, <bool>[true]);
    });

    test('refresh bypasses memory cache and replaces the result', () async {
      // Arrange
      final remote = _RecordingRemoteModels(
        responses: <Map<String, Object?>?>[
          _dynamicResponse('claude-sonnet-5'),
          _dynamicResponse('claude-opus-5'),
        ],
      );
      final catalog = ClaudeCodeModelCatalog(
        credentialsLoader: () async => _credentials,
        remoteModelsLoader: remote.load,
      );
      await catalog.listModels();

      // Act
      final refreshed = await catalog.refreshModels();

      // Assert
      expect(refreshed.models.single.id, 'claude-opus-5');
      expect(remote.callCount, 2);
    });

    test('falls back to static models when the dynamic source fails', () async {
      // Arrange
      final catalog = ClaudeCodeModelCatalog(
        credentialsLoader: () async => _credentials,
        remoteModelsLoader:
            ({
              required String accessToken,
              required bool isSubscriptionOAuth,
            }) async {
              throw StateError('redacted dynamic failure');
            },
      );

      // Act
      final result = await catalog.refreshModels();

      // Assert
      expect(result, same(claudeCodeStaticModelCatalog));
      expect(result.models, hasLength(6));
    });

    test('disabled enrichment reads no credentials and calls no API', () async {
      // Arrange
      var credentialsReads = 0;
      final remote = _RecordingRemoteModels(
        responses: <Map<String, Object?>?>[_dynamicResponse('unexpected')],
      );
      final catalog = ClaudeCodeModelCatalog(
        accountDataEnrichmentEnabled: false,
        credentialsLoader: () async {
          credentialsReads += 1;
          return _credentials;
        },
        remoteModelsLoader: remote.load,
      );

      // Act
      final result = await catalog.refreshModels();

      // Assert
      expect(result, same(claudeCodeStaticModelCatalog));
      expect(credentialsReads, 0);
      expect(remote.callCount, 0);
    });
  });
}

final ClaudeCodeOAuthCredentials _credentials = ClaudeCodeOAuthCredentials(
  accessToken: 'sensitive-test-token',
  expiresAt: DateTime.utc(2099),
  subscriptionType: 'pro',
);

Map<String, Object?> _dynamicResponse(String id) => <String, Object?>{
  'data': <Object?>[
    <String, Object?>{
      'id': id,
      'display_name': id,
      'max_input_tokens': 200000,
      'capabilities': <String, Object?>{'thinking': true},
    },
  ],
};

final class _RecordingRemoteModels {
  _RecordingRemoteModels({required List<Map<String, Object?>?> responses})
    : _responses = List<Map<String, Object?>?>.of(responses);

  final List<Map<String, Object?>?> _responses;
  final List<bool> subscriptionOAuthValues = <bool>[];
  int callCount = 0;

  Future<Map<String, Object?>?> load({
    required String accessToken,
    required bool isSubscriptionOAuth,
  }) async {
    callCount += 1;
    subscriptionOAuthValues.add(isSubscriptionOAuth);
    return _responses.removeAt(0);
  }
}

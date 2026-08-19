import 'dart:convert';
import 'dart:io';

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';
import 'package:zeta_storage/zeta_storage.dart';

void main() {
  const codec = ProviderConfigCodec();
  final preference = AgentModelPreference(
    modelId: 'gpt-5',
    reasoningEffort: 'high',
    fastEnabled: true,
    serviceTierId: 'priority',
    updatedAt: DateTime.utc(2026, 8, 19),
  );
  final config = AgentProviderConfig(
    id: 'codex-custom',
    displayName: 'Codex Custom',
    kind: AgentProviderKind.codexAppServer,
    command: 'codex',
    arguments: const <String>['app-server'],
    environment: const <String, String>{'RUST_LOG': 'info'},
    defaultModel: 'gpt-5',
    selectedModel: 'gpt-5',
    selectedReasoningEffort: 'high',
    selectedServiceTier: 'priority',
    modelPreferences: <String, AgentModelPreference>{'gpt-5': preference},
    selectedPermissionOptionId: 'workspace-write',
    extra: const <String, Object?>{
      'nested': <String, Object?>{
        'values': <Object?>[1, true, null],
      },
    },
  );

  group('ProviderConfigCodec', () {
    test('round trips every current-schema field without selection state', () {
      final source = codec.encode(<AgentProviderConfig>[config]);
      final root = jsonDecode(source) as Map<String, Object?>;
      expect(root, isNot(contains('activeProviderId')));

      final decoded = codec.decode(source).single;
      expect(decoded.id, config.id);
      expect(decoded.displayName, config.displayName);
      expect(decoded.kind, config.kind);
      expect(decoded.command, config.command);
      expect(decoded.arguments, config.arguments);
      expect(decoded.environment, config.environment);
      expect(decoded.defaultModel, config.defaultModel);
      expect(decoded.selectedModel, config.selectedModel);
      expect(decoded.selectedReasoningEffort, config.selectedReasoningEffort);
      expect(decoded.selectedServiceTier, config.selectedServiceTier);
      expect(decoded.selectedPermissionOptionId, 'workspace-write');
      expect(decoded.enabled, isTrue);
      expect(decoded.extra['nested'], isA<Map<Object?, Object?>>());
      expect(
        decoded.modelPreferences['gpt-5']!.updatedAt,
        preference.updatedAt,
      );
    });

    test('round trips an empty Provider list', () {
      expect(
        codec.decode(codec.encode(const <AgentProviderConfig>[])),
        isEmpty,
      );
    });

    test('reports stable exception data without source contents', () {
      expect(
        () => codec.decode('{secret'),
        throwsA(
          isA<AgentConfigDecodeException>()
              .having(
                (error) => error.document,
                'document',
                AgentConfigDocumentKind.providerConfig,
              )
              .having(
                (error) => error.reason,
                'reason',
                AgentConfigDecodeReason.invalidJson,
              )
              .having((error) => error.source, 'source', isNull)
              .having((error) => error.offset, 'offset', isNull)
              .having(
                (error) => error.toString(),
                'safe text',
                isNot(contains('secret')),
              ),
        ),
      );
    });

    for (final scenario
        in <({String name, Object? value, AgentConfigDecodeReason reason})>[
          (
            name: 'non-object root',
            value: <Object?>[],
            reason: AgentConfigDecodeReason.invalidShape,
          ),
          (
            name: 'unknown version',
            value: <String, Object?>{'version': 1, 'providers': <Object?>[]},
            reason: AgentConfigDecodeReason.unsupportedVersion,
          ),
          (
            name: 'missing version',
            value: <String, Object?>{'providers': <Object?>[]},
            reason: AgentConfigDecodeReason.unsupportedVersion,
          ),
          (
            name: 'providers not list',
            value: <String, Object?>{'version': 2, 'providers': true},
            reason: AgentConfigDecodeReason.invalidShape,
          ),
        ]) {
      test('rejects ${scenario.name}', () {
        expect(
          () => codec.decode(jsonEncode(scenario.value)),
          throwsA(
            isA<AgentConfigDecodeException>().having(
              (error) => error.reason,
              'reason',
              scenario.reason,
            ),
          ),
        );
      });
    }

    test('rejects duplicate Provider ids', () {
      final provider = config.toJson();
      expect(
        () => codec.decode(
          jsonEncode(<String, Object?>{
            'version': 2,
            'providers': <Object?>[provider, provider],
          }),
        ),
        _decodeFailure(AgentConfigDecodeReason.duplicateIdentifier),
      );
    });

    test('rejects malformed Provider fields without truncation', () {
      final base = config.toJson();
      final corruptions = <Map<String, Object?>>[
        <String, Object?>{...base, 'id': ''},
        <String, Object?>{...base, 'kind': 'unknown'},
        <String, Object?>{
          ...base,
          'arguments': <Object?>[7],
        },
        <String, Object?>{
          ...base,
          'environment': <String, Object?>{'A': 7},
        },
        <String, Object?>{...base, 'enabled': 'yes'},
        <String, Object?>{...base, 'defaultModel': 7},
        <String, Object?>{...base, 'extra': <Object?>[]},
        <String, Object?>{
          ...base,
          'modelPreferences': <String, Object?>{
            'other': preference.toJson(),
          },
        },
        <String, Object?>{
          ...base,
          'modelPreferences': <String, Object?>{
            'gpt-5': <String, Object?>{...preference.toJson(), 'version': 2},
          },
        },
        <String, Object?>{
          ...base,
          'modelPreferences': <String, Object?>{
            'gpt-5': <String, Object?>{
              ...preference.toJson(),
              'updatedAt': 'bad',
            },
          },
        },
      ];
      for (final corrupted in corruptions) {
        expect(
          () => codec.decode(
            jsonEncode(<String, Object?>{
              'version': 2,
              'providers': <Object?>[corrupted],
            }),
          ),
          throwsA(isA<AgentConfigDecodeException>()),
        );
      }
    });
  });

  group('FileProviderConfigStore', () {
    late Directory temporaryDirectory;
    late File file;

    setUp(() async {
      temporaryDirectory = await Directory.systemTemp.createTemp(
        'zeta_config_',
      );
      file = File(
        '${temporaryDirectory.path}${Platform.pathSeparator}providers.json',
      );
    });

    tearDown(() => temporaryDirectory.delete(recursive: true));

    test(
      'returns empty when missing and atomically overwrites existing data',
      () async {
        final store = FileProviderConfigStore(file: file);
        expect(await store.read(), isEmpty);

        await store.write(<AgentProviderConfig>[config]);
        expect((await store.read()).single.id, 'codex-custom');
        await store.write(<AgentProviderConfig>[
          AgentProviderConfig.defaultGrok,
        ]);
        expect((await store.read()).single.id, grokAgentProviderId);
        expect(file.parent.listSync().whereType<File>(), hasLength(1));
      },
    );

    test('preserves existing data when atomic replacement fails', () async {
      final store = FileProviderConfigStore(file: file);
      await store.write(<AgentProviderConfig>[config]);
      final before = await file.readAsString();
      final failingStore = FileProviderConfigStore(
        file: file,
        temporaryPathBuilder: (target) => '${target.path}.failed.tmp',
        replacer: (temporaryFile, target) async {
          throw const FileSystemException('replace failed');
        },
      );

      await expectLater(
        failingStore.write(<AgentProviderConfig>[
          AgentProviderConfig.defaultGrok,
        ]),
        throwsA(isA<StorageWriteException>()),
      );
      expect(await file.readAsString(), before);
      expect(File('${file.path}.failed.tmp').existsSync(), isFalse);
    });

    test('does not treat an existing empty file as missing', () async {
      await file.create(recursive: true);
      await expectLater(
        FileProviderConfigStore(file: file).read(),
        _decodeFailure(AgentConfigDecodeReason.invalidJson),
      );
    });
  });
}

Matcher _decodeFailure(AgentConfigDecodeReason reason) {
  return throwsA(
    isA<AgentConfigDecodeException>().having(
      (error) => error.reason,
      'reason',
      reason,
    ),
  );
}

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_management_repository/agent_management_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeProviderConfigStore configStore;
  late FakeManagementDataSource source;
  late AgentManagementRepository repository;

  setUp(() {
    configStore = FakeProviderConfigStore(<AgentProviderConfig>[
      AgentProviderConfig.defaultCodex,
    ]);
    source = FakeManagementDataSource(providerId: defaultAgentProviderId);
    repository = createRepository(
      configStore: configStore,
      sources: <String, AgentManagementDataSource>{
        defaultAgentProviderId: source,
      },
    );
  });

  group('construction and routing', () {
    test(
      'freezes normalized client keys and exposes built-in definitions',
      () async {
        final clients = <String, AgentManagementDataSource>{' codex ': source};
        repository = createRepository(
          configStore: configStore,
          sources: clients,
        );
        clients.clear();

        final result = await repository.detect(
          ' codex ',
          executablePath: ' /bin/codex ',
        );

        expect(result.providerId, defaultAgentProviderId);
        expect(source.detectedPaths, <String>['/bin/codex']);
        expect(repository.definitions, AgentDefinition.all);
      },
    );

    test('rejects blank and duplicate normalized client ids', () {
      expect(
        () => createRepository(
          configStore: configStore,
          sources: <String, AgentManagementDataSource>{' ': source},
        ),
        throwsArgumentError,
      );
      expect(
        () => createRepository(
          configStore: configStore,
          sources: <String, AgentManagementDataSource>{
            'codex': source,
            ' codex ': source,
          },
        ),
        throwsArgumentError,
      );
    });

    test('rejects blank and unknown routed Provider ids', () async {
      await expectLater(
        repository.detect(' ', executablePath: 'codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.unknownProvider,
          AgentManagementRepositoryOperation.resolveClient,
          'provider_unknown',
        ),
      );
      await expectLater(
        repository.detect('missing', executablePath: 'missing'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.unknownProvider,
          AgentManagementRepositoryOperation.resolveClient,
          'provider_unknown',
        ),
      );
    });
  });

  group('detection', () {
    test(
      'maps every account and diagnostic stage without retaining UI state',
      () async {
        final stages = <(AgentManagementFailureStage, AgentDiagnosticStage)>[
          (
            AgentManagementFailureStage.fileDetection,
            AgentDiagnosticStage.fileDetection,
          ),
          (
            AgentManagementFailureStage.cliStartup,
            AgentDiagnosticStage.cliStartup,
          ),
          (
            AgentManagementFailureStage.versionDetection,
            AgentDiagnosticStage.versionDetection,
          ),
          (
            AgentManagementFailureStage.accountAuthentication,
            AgentDiagnosticStage.accountAuthentication,
          ),
          (
            AgentManagementFailureStage.protocolHandshake,
            AgentDiagnosticStage.protocolHandshake,
          ),
          (
            AgentManagementFailureStage.configurationRead,
            AgentDiagnosticStage.configurationRead,
          ),
          (
            AgentManagementFailureStage.configurationWrite,
            AgentDiagnosticStage.configurationWrite,
          ),
          (
            AgentManagementFailureStage.logRead,
            AgentDiagnosticStage.logRead,
          ),
        ];
        const accountStatuses = AgentAccountStatus.values;
        var invocation = 0;
        source.onDetect = (_) async {
          final stage = stages[invocation];
          final account = accountStatuses[invocation % accountStatuses.length];
          invocation += 1;
          return detectionResponse(
            providerId: defaultAgentProviderId,
            accountStatus: account,
            failureStage: stage.$1,
            failureCode: 'safe-code',
            logPaths: <String>['/z.log', '/a.log', '/z.log'],
          );
        };

        final results = <AgentDetection>[];
        for (var index = 0; index < stages.length; index += 1) {
          results.add(
            await repository.detect('codex', executablePath: 'codex'),
          );
        }

        expect(
          results.map((result) => result.diagnostic!.stage),
          stages.map((stage) => stage.$2),
        );
        expect(
          results.take(4).map((result) => result.accountState),
          AgentAccountState.values,
        );
        expect(results.first.logPaths, <String>['/a.log', '/z.log']);
        expect(
          () => results.first.logPaths.add('/new.log'),
          throwsUnsupportedError,
        );
        expect(results.first.diagnostic!.code, 'safe-code');
        expect(results.first.executablePath, '/bin/agent');
        expect(results.first.version, '1.2.3');
        expect(results.first.accountLabel, 'team');
        expect(results.first.configurationPath, '/config');
        expect(results.first.configurationExists, isTrue);
        expect(results.first.installed, isTrue);
      },
    );

    test('maps an absent client diagnostic to null', () async {
      final result = await repository.detect('codex', executablePath: 'codex');

      expect(result.diagnostic, isNull);
    });

    test('maps a diagnostic code that has no client stage', () async {
      source.onDetect = (_) async => detectionResponse(
        providerId: defaultAgentProviderId,
        failureCode: 'stage-unavailable',
      );

      final result = await repository.detect('codex', executablePath: 'codex');

      expect(result.diagnostic!.stage, isNull);
      expect(result.diagnostic!.code, 'stage-unavailable');
    });

    test('uses persisted cliPath and falls back to command', () async {
      configStore.configurations = <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex.copyWith(
          command: 'fallback',
          extra: <String, Object?>{'cliPath': ' /chosen/codex '},
        ),
      ];
      await repository.detect('codex');
      configStore.configurations = <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex.copyWith(command: ' fallback '),
      ];
      await repository.detect('codex', executablePath: '  ');

      expect(source.detectedPaths, <String>['/chosen/codex', 'fallback']);
      expect(configStore.readCount, 2);
    });

    test('explicit path bypasses Provider configuration reads', () async {
      configStore.readError = StateError('must not read');

      await repository.detect('codex', executablePath: 'codex');

      expect(configStore.readCount, 0);
    });

    test('rejects a cross-Provider response', () async {
      source.onDetect = (_) async => detectionResponse(providerId: 'grok');

      await expectLater(
        repository.detect('codex', executablePath: 'codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.providerResponseMismatch,
          AgentManagementRepositoryOperation.detect,
          'provider_response_mismatch',
        ),
      );
    });

    test(
      'translates client failures and renders without cause contents',
      () async {
        final error = StateError('credential=secret');
        source.onDetect = (_) => throw error;

        late AgentManagementRepositoryException translated;
        try {
          await repository.detect('codex', executablePath: 'codex');
          fail('detect should throw');
        } on AgentManagementRepositoryException catch (caught) {
          translated = caught;
        }

        expect(translated.cause, same(error));
        expect(translated.stackTrace, isNotNull);
        expect(
          translated.failure,
          const AgentManagementRepositoryFailure(
            providerId: defaultAgentProviderId,
            operation: AgentManagementRepositoryOperation.detect,
            code: AgentManagementRepositoryFailureCode.clientFailure,
            diagnosticCode: 'detect_failed',
          ),
        );
        expect(translated.toString(), isNot(contains('secret')));
      },
    );
  });

  group('Provider configuration and connection tests', () {
    test('uses current config and maps a complete connection result', () async {
      final model = AgentModelInfo(
        id: 'model',
        model: 'model',
        displayName: 'Model',
      );
      source.onTestConnection = (_) async => connectionResponse(
        models: <AgentModelInfo>[model],
        capabilityIds: <String>['tools'],
        failureStage: AgentManagementFailureStage.protocolHandshake,
        failureCode: 'handshake-warning',
      );

      final result = await repository.testConnection('codex');

      expect(source.testedConfigurations, <AgentProviderConfig>[
        AgentProviderConfig.defaultCodex,
      ]);
      expect(result.providerId, defaultAgentProviderId);
      expect(result.success, isTrue);
      expect(result.testedAt, DateTime.utc(2026, 8, 20, 2));
      expect(result.elapsed, const Duration(milliseconds: 125));
      expect(result.cliCallable, isTrue);
      expect(result.accountValid, isTrue);
      expect(result.protocolReady, isTrue);
      expect(result.models, <AgentModelInfo>[model]);
      expect(result.capabilityIds, <String>['tools']);
      expect(result.diagnostic!.stage, AgentDiagnosticStage.protocolHandshake);
      expect(result.diagnostic!.code, 'handshake-warning');
      expect(result.protocolVersion, '2');
      expect(result.agentName, 'agent');
      expect(result.agentVersion, '1.2.3');
      expect(result.models.clear, throwsUnsupportedError);
      expect(result.capabilityIds.clear, throwsUnsupportedError);
    });

    test('supplies all built-in defaults on a clean config store', () async {
      configStore.configurations = <AgentProviderConfig>[];
      final sources = <String, FakeManagementDataSource>{
        defaultAgentProviderId: FakeManagementDataSource(
          providerId: defaultAgentProviderId,
        ),
        grokAgentProviderId: FakeManagementDataSource(
          providerId: grokAgentProviderId,
        ),
        defaultClaudeCodeProviderId: FakeManagementDataSource(
          providerId: defaultClaudeCodeProviderId,
        ),
      };
      repository = createRepository(
        configStore: configStore,
        sources: sources,
      );

      for (final providerId in sources.keys) {
        await repository.testConnection(providerId);
      }

      expect(
        sources[defaultAgentProviderId]!.testedConfigurations.single,
        same(AgentProviderConfig.defaultCodex),
      );
      expect(
        sources[grokAgentProviderId]!.testedConfigurations.single,
        same(AgentProviderConfig.defaultGrok),
      );
      expect(
        sources[defaultClaudeCodeProviderId]!.testedConfigurations.single,
        same(AgentProviderConfig.defaultClaudeCode),
      );
      expect(configStore.writes, isEmpty);
    });

    test(
      'accepts a configured custom Provider without a built-in definition',
      () async {
        final custom = AgentProviderConfig.defaultCodex.copyWith(
          id: 'custom',
          command: 'custom-cli',
        );
        final customSource = FakeManagementDataSource(providerId: 'custom');
        configStore.configurations = <AgentProviderConfig>[custom];
        repository = createRepository(
          configStore: configStore,
          sources: <String, AgentManagementDataSource>{'custom': customSource},
        );

        await repository.testConnection('custom');

        expect(customSource.testedConfigurations, <AgentProviderConfig>[
          custom,
        ]);
      },
    );

    test('translates decode and external config-store failures', () async {
      const decodeError = AgentConfigDecodeException(
        document: AgentConfigDocumentKind.providerConfig,
        reason: AgentConfigDecodeReason.invalidShape,
      );
      configStore.readError = decodeError;
      await expectLater(
        repository.testConnection('codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
          AgentManagementRepositoryOperation.readProviderConfiguration,
          'provider_configuration_invalid',
          cause: decodeError,
        ),
      );

      final readError = StateError('store secret');
      configStore.readError = readError;
      await expectLater(
        repository.testConnection('codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.clientFailure,
          AgentManagementRepositoryOperation.readProviderConfiguration,
          'provider_configuration_read_failed',
          cause: readError,
        ),
      );
    });

    test('rejects every invalid Provider configuration shape', () async {
      final cases = <(List<AgentProviderConfig>, String, String)>[
        (
          <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultCodex,
          ],
          defaultAgentProviderId,
          'provider_configuration_duplicate',
        ),
        (
          <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(id: ' codex '),
          ],
          defaultAgentProviderId,
          'provider_id_not_canonical',
        ),
        (
          <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(
              kind: AgentProviderKind.acp,
            ),
          ],
          defaultAgentProviderId,
          'provider_kind_mismatch',
        ),
        (
          <AgentProviderConfig>[
            AgentProviderConfig.defaultCodex.copyWith(command: ' '),
          ],
          defaultAgentProviderId,
          'provider_command_missing',
        ),
        (<AgentProviderConfig>[], 'custom', 'provider_configuration_missing'),
      ];

      for (final invalidCase in cases) {
        final providerId = invalidCase.$2;
        configStore = FakeProviderConfigStore(invalidCase.$1);
        final caseSource = FakeManagementDataSource(providerId: providerId);
        repository = createRepository(
          configStore: configStore,
          sources: <String, AgentManagementDataSource>{
            providerId: caseSource,
          },
        );

        await expectLater(
          repository.testConnection(providerId),
          throwsFailure(
            AgentManagementRepositoryFailureCode.invalidProviderConfiguration,
            AgentManagementRepositoryOperation.readProviderConfiguration,
            invalidCase.$3,
          ),
        );
      }
    });
  });

  group('configuration documents', () {
    test('maps read and save responses without storing editor state', () async {
      source
        ..onReadConfiguration = () async {
          return configurationDocument(contents: 'token = "secret"');
        }
        ..onSaveConfiguration = (contents) async {
          return ConfigurationSaveResponse(
            document: configurationDocument(contents: contents),
            backupPath: '/previous.backup',
          );
        };

      final document = await repository.readConfiguration('codex');
      final saved = await repository.saveConfiguration(
        'codex',
        contents: 'model = "new"',
      );

      expect(document.path, '/config');
      expect(document.format, 'toml');
      expect(document.contents, 'token = "secret"');
      expect(document.maskedContents, 'token = "secret"');
      expect(document.exists, isTrue);
      expect(document.loadedAt, DateTime.utc(2026, 8, 20, 3));
      expect(document.modifiedAt, DateTime.utc(2026, 8, 20));
      expect(document.signature, 'signature');
      expect(source.readConfigurationCount, 1);
      expect(source.savedContents, <String>['model = "new"']);
      expect(saved.document.contents, 'model = "new"');
      expect(saved.backupPath, '/previous.backup');
    });

    test('validates JSON and TOML through a pure typed result', () {
      expect(
        repository.validateConfiguration(
          format: ' JSON ',
          contents: '{"model":"safe"}',
        ),
        AgentConfigurationValidation.valid,
      );
      expect(
        repository
            .validateConfiguration(format: 'json', contents: '[]')
            .failureCode,
        'json-object-required',
      );
      expect(
        repository
            .validateConfiguration(format: 'json', contents: '{')
            .failureCode,
        'invalid-json',
      );
      expect(
        repository
            .validateConfiguration(format: 'toml', contents: 'model = "safe"')
            .isValid,
        isTrue,
      );
      expect(
        repository
            .validateConfiguration(format: 'toml', contents: 'model = [')
            .failureCode,
        'invalid-toml',
      );
      expect(
        repository
            .validateConfiguration(format: 'yaml', contents: 'model: safe')
            .failureCode,
        'unsupported-config-format',
      );
    });

    test('translates typed save validation failures', () async {
      const error = ConfigurationValidationException('invalid-toml');
      source.onSaveConfiguration = (_) => throw error;

      await expectLater(
        repository.saveConfiguration('codex', contents: 'secret = ['),
        throwsFailure(
          AgentManagementRepositoryFailureCode.invalidConfiguration,
          AgentManagementRepositoryOperation.saveConfiguration,
          'invalid-toml',
          cause: error,
        ),
      );
    });

    test('translates generic read failures with safe text', () async {
      final error = StateError('token=secret');
      source.onReadConfiguration = () => throw error;

      await expectLater(
        repository.readConfiguration('codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.clientFailure,
          AgentManagementRepositoryOperation.readConfiguration,
          'readConfiguration_failed',
          cause: error,
        ),
      );
    });
  });

  group('logs', () {
    test('discovers deterministic unique immutable paths', () async {
      source.onDiscoverLogPaths = () async => <String>[
        '/z.log',
        '/a.log',
        '/z.log',
      ];

      final paths = await repository.discoverLogPaths('codex');

      expect(paths, <String>['/a.log', '/z.log']);
      expect(paths.clear, throwsUnsupportedError);
    });

    test(
      'maps, orders, deduplicates reads, and globally bounds logs',
      () async {
        final sameTime = DateTime.utc(2026, 8, 20, 4);
        source.onReadLogs = (path, _) async {
          if (path == '/first.log') {
            return <LogEntryResponse>[
              LogEntryResponse(
                id: 'null-b',
                sourcePath: path,
                message: 'debug',
                level: AgentManagementLogLevel.debug,
                timestamp: null,
              ),
              LogEntryResponse(
                id: 'same-b',
                sourcePath: path,
                message: 'info',
                level: AgentManagementLogLevel.info,
                timestamp: sameTime,
              ),
              LogEntryResponse(
                id: 'later',
                sourcePath: path,
                message: 'warning',
                level: AgentManagementLogLevel.warning,
                timestamp: sameTime.add(const Duration(seconds: 1)),
              ),
            ];
          }
          return <LogEntryResponse>[
            LogEntryResponse(
              id: 'null-a',
              sourcePath: path,
              message: 'error',
              level: AgentManagementLogLevel.error,
              timestamp: null,
            ),
            LogEntryResponse(
              id: 'same-a',
              sourcePath: path,
              message: 'info',
              level: AgentManagementLogLevel.info,
              timestamp: sameTime,
            ),
          ];
        };

        final result = await repository.readLogs(
          'codex',
          <String>['/first.log', '/second.log', '/first.log'],
          maxLines: 4,
        );

        expect(source.logReads, <(String, int)>[
          ('/first.log', 4),
          ('/second.log', 4),
        ]);
        expect(
          result.map((entry) => entry.id),
          <String>['null-b', 'same-a', 'same-b', 'later'],
        );
        expect(
          result.map((entry) => entry.level),
          <AgentLogLevel>[
            AgentLogLevel.debug,
            AgentLogLevel.info,
            AgentLogLevel.info,
            AgentLogLevel.warning,
          ],
        );
        expect(result.last.message, 'warning');
        expect(result.last.sourcePath, '/first.log');
        expect(result.clear, throwsUnsupportedError);
      },
    );

    test('returns empty for non-positive bounds and empty paths', () async {
      expect(
        await repository.readLogs('codex', <String>['/agent.log'], maxLines: 0),
        isEmpty,
      );
      expect(await repository.readLogs('codex', const <String>[]), isEmpty);
      expect(source.logReads, isEmpty);
    });

    test('translates log discovery and read failures', () async {
      final discoverError = StateError('discover failed');
      source.onDiscoverLogPaths = () => throw discoverError;
      await expectLater(
        repository.discoverLogPaths('codex'),
        throwsFailure(
          AgentManagementRepositoryFailureCode.clientFailure,
          AgentManagementRepositoryOperation.discoverLogPaths,
          'discoverLogPaths_failed',
          cause: discoverError,
        ),
      );

      final readError = StateError('read failed');
      source.onReadLogs = (_, _) => throw readError;
      await expectLater(
        repository.readLogs('codex', <String>['/agent.log']),
        throwsFailure(
          AgentManagementRepositoryFailureCode.clientFailure,
          AgentManagementRepositoryOperation.readLogs,
          'readLogs_failed',
          cause: readError,
        ),
      );
    });
  });
}

AgentManagementRepository createRepository({
  required FakeProviderConfigStore configStore,
  required Map<String, AgentManagementDataSource> sources,
}) {
  return AgentManagementRepository(
    managementClients: sources,
    configStore: configStore,
  );
}

Matcher throwsFailure(
  AgentManagementRepositoryFailureCode code,
  AgentManagementRepositoryOperation operation,
  String diagnosticCode, {
  Object? cause,
}) {
  var matcher = isA<AgentManagementRepositoryException>()
      .having((error) => error.failure.code, 'code', code)
      .having((error) => error.failure.operation, 'operation', operation)
      .having(
        (error) => error.failure.diagnosticCode,
        'diagnosticCode',
        diagnosticCode,
      )
      .having(
        (error) => error.toString(),
        'safe string',
        isNot(contains('secret')),
      );
  if (cause != null) {
    matcher = matcher.having((error) => error.cause, 'cause', same(cause));
  }
  return throwsA(matcher);
}

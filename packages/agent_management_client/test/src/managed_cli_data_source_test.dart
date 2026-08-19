import 'dart:async';
import 'dart:io';

import 'package:agent_management_client/agent_management_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  group('managed CLI detection', () {
    test('returns a typed missing response and filtered sorted logs', () async {
      final fileSystem = FakeManagementFileSystem()
        ..metadataByPath['config'] = const AgentManagementFileMetadata.missing()
        ..filesByDirectory['logs'] = <String>[
          'logs/z.txt',
          'logs/b.log',
          'logs/a.log',
          'logs/a.log',
        ];
      final source = _codexSource(
        fileSystem: fileSystem,
        resolvePath: (_) async => null,
      );

      final response = await source.detect(executablePath: 'missing');

      expect(response.providerId, 'codex');
      expect(response.installed, isFalse);
      expect(response.accountStatus, AgentAccountStatus.unknown);
      expect(response.logPaths, <String>['logs/a.log', 'logs/b.log']);
      expect(response.failureStage, AgentManagementFailureStage.fileDetection);
      expect(response.failureCode, 'cli-not-found');
    });

    test(
      'maps process startup failure without exposing the exception',
      () async {
        final source = _codexSource(
          processRunner: CliProcessRunner(
            starter: (_, _, {environment}) async =>
                throw const ProcessException('codex', <String>[]),
          ),
        );

        final response = await source.detect(executablePath: 'codex');

        expect(response.installed, isFalse);
        expect(response.executablePath, 'codex-display');
        expect(response.accountStatus, AgentAccountStatus.unavailable);
        expect(response.failureStage, AgentManagementFailureStage.cliStartup);
        expect(response.failureCode, 'cli-start-failed');
      },
    );

    test(
      'keeps installed CLI with unavailable version and account evidence',
      () async {
        final source = _codexSource(
          processRunner: processRunnerFor(
            FakeProcessHandle.text(code: 1, stdout: 'unknown'),
          ),
          accountProbe: (_, _) async => throw StateError('credential boundary'),
        );

        final response = await source.detect(executablePath: 'codex');

        expect(response.installed, isTrue);
        expect(response.version, isNull);
        expect(response.accountStatus, AgentAccountStatus.unavailable);
        expect(
          response.failureStage,
          AgentManagementFailureStage.versionDetection,
        );
        expect(response.failureCode, 'version-unavailable');
      },
    );

    test(
      'maps a successful semantic version and safe account evidence',
      () async {
        final source = _codexSource(
          processRunner: processRunnerFor(
            FakeProcessHandle.text(stdout: 'codex 1.2.3-beta.1'),
          ),
          accountProbe: (_, environment) async {
            expect(environment, isEmpty);
            return const AccountProbeResponse(
              status: AgentAccountStatus.loggedIn,
              label: 'Authenticated',
            );
          },
        );

        final response = await source.detect(executablePath: 'codex');

        expect(response.installed, isTrue);
        expect(response.version, '1.2.3-beta.1');
        expect(response.accountStatus, AgentAccountStatus.loggedIn);
        expect(response.accountLabel, 'Authenticated');
        expect(response.failureStage, isNull);
        expect(response.failureCode, isNull);
      },
    );

    test(
      'Grok and Claude wrappers retain vendor ids and log policies',
      () async {
        final fileSystem = FakeManagementFileSystem()
          ..filesByDirectory['logs'] = <String>[
            'logs/a.jsonl',
            'logs/b.txt',
            'logs/c.log',
            'logs/d.bin',
          ];
        final grok = GrokAgentManagementDataSource(
          configPath: 'grok.toml',
          resolvePath: (_) async => _command,
          locate: (_) async => _command,
          protocolProbe: (_) async => _successfulProbe,
          logDirectory: 'logs',
          fileSystem: fileSystem,
          processRunner: processRunnerFor(
            FakeProcessHandle.text(stdout: 'grok 1.0.5'),
          ),
          now: _now,
        );
        final claude = ClaudeCodeAgentManagementDataSource(
          configPath: 'claude.json',
          resolvePath: (_) async => _command,
          locate: (_) async => _command,
          protocolProbe: (_) async => _successfulProbe,
          logDirectory: 'logs',
          accountProbe: (_, _) async => const AccountProbeResponse(
            status: AgentAccountStatus.loggedOut,
          ),
          fileSystem: fileSystem,
          processRunner: processRunnerFor(
            FakeProcessHandle.text(stdout: 'claude 2.1.227'),
          ),
          now: _now,
        );

        expect((await grok.detect(executablePath: 'grok')).providerId, 'grok');
        expect(
          await grok.discoverLogPaths(),
          <String>['logs/a.jsonl', 'logs/b.txt', 'logs/c.log'],
        );
        final claudeResult = await claude.detect(executablePath: 'claude');
        expect(claudeResult.providerId, 'claude-code');
        expect(claudeResult.accountStatus, AgentAccountStatus.loggedOut);
        expect(await claude.discoverLogPaths(), <String>['logs/c.log']);
      },
    );
  });

  group('managed CLI connection tests', () {
    test('returns not found before invoking the protocol probe', () async {
      var probed = false;
      final source = _codexSource(
        locate: (_) async => null,
        protocolProbe: (_) async {
          probed = true;
          return _successfulProbe;
        },
      );

      final response = await source.testConnection(
        config: AgentProviderConfig.defaultCodex,
      );

      expect(response.success, isFalse);
      expect(response.cliCallable, isFalse);
      expect(response.failureStage, AgentManagementFailureStage.fileDetection);
      expect(response.failureCode, 'cli-not-found');
      expect(probed, isFalse);
    });

    test('maps every whitelisted successful protocol field', () async {
      final source = _codexSource();
      final response = await source.testConnection(
        config: AgentProviderConfig.defaultCodex,
      );

      expect(response.success, isTrue);
      expect(response.cliCallable, isTrue);
      expect(response.accountValid, isTrue);
      expect(response.protocolReady, isTrue);
      expect(response.models.single.id, 'model');
      expect(response.capabilityIds, <String>['prompt']);
      expect(response.protocolVersion, '1');
      expect(response.agentName, 'Fixture');
      expect(response.agentVersion, '1.2.3');
      expect(response.failureStage, isNull);
    });

    test('maps protocol-declared, timeout, and unexpected failures', () async {
      final declared = _codexSource(
        protocolProbe: (_) async => AgentProtocolProbeResponse(
          success: false,
          accountValid: false,
          failureCode: 'not-authenticated',
        ),
      );
      final timedOut = _codexSource(
        protocolProbe: (_) async => throw TimeoutException('fixture'),
      );
      final failed = _codexSource(
        protocolProbe: (_) async => throw StateError('fixture'),
      );

      final declaredResult = await declared.testConnection(
        config: AgentProviderConfig.defaultCodex,
      );
      final timeoutResult = await timedOut.testConnection(
        config: AgentProviderConfig.defaultCodex,
      );
      final failedResult = await failed.testConnection(
        config: AgentProviderConfig.defaultCodex,
      );

      expect(declaredResult.success, isFalse);
      expect(declaredResult.protocolReady, isFalse);
      expect(declaredResult.failureCode, 'not-authenticated');
      expect(timeoutResult.failureCode, 'probe-timeout');
      expect(failedResult.failureCode, 'probe-failed');
      expect(
        failedResult.failureStage,
        AgentManagementFailureStage.protocolHandshake,
      );
    });
  });

  group('managed configuration IO', () {
    test('reads missing and redacted JSON/TOML documents', () async {
      final fileSystem = FakeManagementFileSystem();
      final missing = await _codexSource(fileSystem: fileSystem)
          .readConfiguration();
      expect(missing.exists, isFalse);
      expect(missing.contents, isEmpty);

      fileSystem
        ..metadataByPath['config'] = AgentManagementFileMetadata(
          exists: true,
          isFile: true,
          isLink: false,
          size: 20,
          modifiedAt: _now(),
        )
        ..textByPath['config'] = 'token = "secret"';
      final toml = await _codexSource(fileSystem: fileSystem)
          .readConfiguration();
      expect(toml.exists, isTrue);
      expect(toml.contents, contains('secret'));
      expect(toml.maskedContents, isNot(contains('secret')));
      expect(toml.signature, isNotEmpty);

      fileSystem
        ..metadataByPath['claude.json'] = AgentManagementFileMetadata(
          exists: true,
          isFile: true,
          isLink: false,
          size: 20,
          modifiedAt: _now(),
        )
        ..textByPath['claude.json'] = '{"api_key":"secret"}';
      final json = await _claudeSource(
        fileSystem: fileSystem,
      ).readConfiguration();
      expect(json.format, 'json');
      expect(json.maskedContents, isNot(contains('secret')));
    });

    test('rejects symbolic links on read and save', () async {
      final fileSystem = FakeManagementFileSystem()
        ..metadataByPath['config'] = const AgentManagementFileMetadata(
          exists: true,
          isFile: false,
          isLink: true,
          size: 0,
        );
      final source = _codexSource(fileSystem: fileSystem);

      await expectLater(
        source.readConfiguration(),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        source.saveConfiguration(contents: 'model = "safe"'),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('rejects invalid current-schema JSON and TOML', () async {
      await expectLater(
        _claudeSource().saveConfiguration(contents: '[]'),
        throwsA(
          isA<ConfigurationValidationException>().having(
            (error) => error.code,
            'code',
            'json-object-required',
          ),
        ),
      );
      await expectLater(
        _claudeSource().saveConfiguration(contents: '{'),
        throwsA(
          isA<ConfigurationValidationException>().having(
            (error) => error.code,
            'code',
            'invalid-json',
          ),
        ),
      );
      await expectLater(
        _codexSource().saveConfiguration(contents: '[broken'),
        throwsA(
          isA<ConfigurationValidationException>().having(
            (error) => error.code,
            'code',
            'invalid-toml',
          ),
        ),
      );
    });

    test(
      'atomically saves valid configuration and returns a fresh snapshot',
      () async {
        final fileSystem = FakeManagementFileSystem()
          ..backupPath = 'config.backup';
        final source = _codexSource(fileSystem: fileSystem);

        final response = await source.saveConfiguration(
          contents: 'model = "safe"',
        );

        expect(fileSystem.lastWritePath, 'config');
        expect(fileSystem.lastWriteContents, 'model = "safe"');
        expect(response.backupPath, 'config.backup');
        expect(response.document.exists, isTrue);
        expect(response.document.contents, 'model = "safe"');
      },
    );
  });

  group('managed log reads', () {
    test('returns empty for non-positive limits and unsafe paths', () async {
      final fileSystem = FakeManagementFileSystem()
        ..metadataByPath['link'] = const AgentManagementFileMetadata(
          exists: true,
          isFile: true,
          isLink: true,
          size: 2,
        );
      final source = _codexSource(fileSystem: fileSystem);

      expect(await source.readLogs('missing'), isEmpty);
      expect(await source.readLogs('link'), isEmpty);
      expect(await source.readLogs('missing', maxLines: 0), isEmpty);
    });

    test(
      'redacts, classifies, timestamps, skips partial line, and caps tail',
      () async {
        final fileSystem = FakeManagementFileSystem()
          ..metadataByPath['log'] = const AgentManagementFileMetadata(
            exists: true,
            isFile: true,
            isLink: false,
            size: 100,
          )
          ..tailsByPath['log'] = const AgentManagementTextTail(
            skippedPrefix: true,
            contents:
                'partial\n2026-08-20T00:00:00Z debug trace\n'
                '2026-08-20T00:00:01Z warn token=secret\n'
                '2026-08-20T00:00:02Z fatal failure\n'
                'plain info\n\n',
          );
        final source = _codexSource(fileSystem: fileSystem);

        final entries = await source.readLogs('log', maxLines: 3);

        expect(entries, hasLength(3));
        expect(entries[0].level, AgentManagementLogLevel.warning);
        expect(entries[0].message, isNot(contains('secret')));
        expect(entries[0].timestamp, isNotNull);
        expect(entries[1].level, AgentManagementLogLevel.error);
        expect(entries[2].level, AgentManagementLogLevel.info);
        expect(entries[2].timestamp, isNull);
        expect(entries[2].id, 'log:3');
        expect(entries[2].sourcePath, 'log');
      },
    );

    test(
      'keeps a complete prefix and recognizes error and trace aliases',
      () async {
        final fileSystem = FakeManagementFileSystem()
          ..metadataByPath['log'] = const AgentManagementFileMetadata(
            exists: true,
            isFile: true,
            isLink: false,
            size: 20,
          )
          ..tailsByPath['log'] = const AgentManagementTextTail(
            skippedPrefix: false,
            contents: 'error first\ntrace second',
          );
        final entries = await _codexSource(
          fileSystem: fileSystem,
        ).readLogs('log');

        expect(entries.first.level, AgentManagementLogLevel.error);
        expect(entries.last.level, AgentManagementLogLevel.debug);
      },
    );
  });

  test('protocol and account probe response collections are immutable', () {
    final response = AgentProtocolProbeResponse(
      success: true,
      accountValid: true,
      models: <AgentModelInfo>[
        AgentModelInfo(id: 'id', model: 'id', displayName: 'ID'),
      ],
      capabilityIds: const <String>['prompt'],
      failureCode: 'none',
      protocolVersion: '1',
      agentName: 'agent',
      agentVersion: '1.0.0',
    );
    const account = AccountProbeResponse(
      status: AgentAccountStatus.loggedIn,
      label: 'safe',
    );

    expect(response.success, isTrue);
    expect(response.accountValid, isTrue);
    expect(response.failureCode, 'none');
    expect(response.protocolVersion, '1');
    expect(response.agentName, 'agent');
    expect(response.agentVersion, '1.0.0');
    expect(response.models.clear, throwsUnsupportedError);
    expect(response.capabilityIds.clear, throwsUnsupportedError);
    expect(account.status, AgentAccountStatus.loggedIn);
    expect(account.label, 'safe');
  });
}

CodexAgentManagementDataSource _codexSource({
  FakeManagementFileSystem? fileSystem,
  AgentManagementCliPathResolver? resolvePath,
  AgentManagementCliLocator? locate,
  AgentManagementProtocolProbe? protocolProbe,
  AgentManagementAccountProbe? accountProbe,
  CliProcessRunner? processRunner,
}) {
  return CodexAgentManagementDataSource(
    configPath: 'config',
    resolvePath: resolvePath ?? (_) async => _command,
    locate: locate ?? (_) async => _command,
    protocolProbe: protocolProbe ?? (_) async => _successfulProbe,
    logDirectory: 'logs',
    accountProbe: accountProbe,
    fileSystem: fileSystem ?? FakeManagementFileSystem(),
    processRunner:
        processRunner ??
        processRunnerFor(FakeProcessHandle.text(stdout: 'codex 1.2.3')),
    now: _now,
  );
}

ClaudeCodeAgentManagementDataSource _claudeSource({
  FakeManagementFileSystem? fileSystem,
}) {
  return ClaudeCodeAgentManagementDataSource(
    configPath: 'claude.json',
    resolvePath: (_) async => _command,
    locate: (_) async => _command,
    protocolProbe: (_) async => _successfulProbe,
    logDirectory: 'logs',
    accountProbe: (_, _) async => const AccountProbeResponse(
      status: AgentAccountStatus.loggedIn,
    ),
    fileSystem: fileSystem ?? FakeManagementFileSystem(),
    processRunner: processRunnerFor(
      FakeProcessHandle.text(stdout: 'claude 2.1.227'),
    ),
    now: _now,
  );
}

DateTime _now() => DateTime.utc(2026, 8, 20);

final _command = ResolvedCliProcessCommand(
  executable: 'fixture',
  arguments: const <String>[],
  displayPath: 'codex-display',
);

final _successfulProbe = AgentProtocolProbeResponse(
  success: true,
  accountValid: true,
  models: <AgentModelInfo>[
    AgentModelInfo(id: 'model', model: 'model', displayName: 'Model'),
  ],
  capabilityIds: const <String>['prompt'],
  protocolVersion: '1',
  agentName: 'Fixture',
  agentVersion: '1.2.3',
);

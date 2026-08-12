import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/stream_json_peer.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

void main() {
  const claudeHome = '/test-user/.claude';
  final detectedAt = DateTime.utc(2026, 8, 11, 8, 30);

  group('ClaudeCodeAgentManagementRepository.detect', () {
    test('reports not installed without starting a connection probe', () async {
      // Arrange
      final processRunner = _FakeProcessRunner.failure(
        ProcessException('claude', const <String>['--version']),
      );
      final fileSystem = _FakeMetadataFileSystem();
      final probe = _FakeConnectionProbe();
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: processRunner.call,
        connectionProbe: probe.call,
        fileSystem: fileSystem,
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      // Act
      final agent = await repository.detect(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
        enabled: true,
      );

      // Assert
      expect(agent.installationState, AgentInstallationState.notInstalled);
      expect(agent.accountState, AgentAccountState.unknown);
      expect(agent.runtimeState, AgentRuntimeState.unavailable);
      expect(agent.lastDetectedAt, detectedAt);
      expect(processRunner.calls, hasLength(1));
      expect(processRunner.calls.single.arguments, const <String>['--version']);
      expect(probe.calls, 0);
      expect(fileSystem.operations, <String>[
        'list:${_join(claudeHome, 'logs')}',
      ]);
    });

    test(
      'reports installed but logged out using metadata access only',
      () async {
        // Arrange
        final processRunner = _FakeProcessRunner.success();
        final fileSystem = _FakeMetadataFileSystem();
        final probe = _FakeConnectionProbe();
        final progress = <AgentDetectionProgress>[];
        final repository = ClaudeCodeAgentManagementRepository(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: processRunner.call,
          connectionProbe: probe.call,
          fileSystem: fileSystem,
          now: () => detectedAt,
          claudeHomeProvider: () => claudeHome,
        );

        // Act
        final agent = await repository.detect(
          providerConfig: AgentProviderConfig.defaultClaudeCode,
          enabled: true,
          onProgress: (update, _) => progress.add(update),
        );

        // Assert
        expect(agent.installationState, AgentInstallationState.installed);
        expect(agent.accountState, AgentAccountState.loggedOut);
        expect(agent.currentVersion, '2.1.224');
        expect(agent.versionState, AgentVersionState.current);
        expect(agent.runtimeState, AgentRuntimeState.notRunning);
        expect(agent.configExists, isFalse);
        expect(probe.calls, 0);
        expect(progress.last.completed, 3);
        expect(progress.last.total, 3);
        expect(fileSystem.operations, <String>[
          'stat:${_join(claudeHome, '.credentials.json')}',
          'stat:${_join(claudeHome, 'oauth.json')}',
          'stat:${_join(claudeHome, 'settings.json')}',
          'list:${_join(claudeHome, 'logs')}',
        ]);
        expect(
          fileSystem.operations.where(
            (operation) => operation.startsWith('read:'),
          ),
          isEmpty,
        );
      },
    );

    test('reports logged in without reading credential contents', () async {
      // Arrange
      final credentialsPath = _join(claudeHome, '.credentials.json');
      final configPath = _join(claudeHome, 'settings.json');
      final logPath = _join(_join(claudeHome, 'logs'), 'latest.log');
      final credentialModifiedAt = DateTime.utc(2026, 8, 10, 16);
      final configModifiedAt = DateTime.utc(2026, 8, 10, 17);
      final fileSystem = _FakeMetadataFileSystem(
        metadata: <String, ClaudeCodeFileMetadata>{
          credentialsPath: ClaudeCodeFileMetadata(
            exists: true,
            isFile: true,
            modifiedAt: credentialModifiedAt,
          ),
          configPath: ClaudeCodeFileMetadata(
            exists: true,
            isFile: true,
            modifiedAt: configModifiedAt,
          ),
        },
        logPaths: <String>[logPath],
      );
      final probe = _FakeConnectionProbe();
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: _FakeProcessRunner.success().call,
        connectionProbe: probe.call,
        fileSystem: fileSystem,
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      // Act
      final agent = await repository.detect(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
        enabled: true,
      );

      // Assert
      expect(agent.accountState, AgentAccountState.loggedIn);
      expect(agent.configExists, isTrue);
      expect(agent.configModifiedAt, configModifiedAt);
      expect(agent.logPaths, <String>[logPath]);
      expect(probe.calls, 0);
      expect(fileSystem.operations, <String>[
        'stat:$credentialsPath',
        'stat:$configPath',
        'list:${_join(claudeHome, 'logs')}',
      ]);
      expect(
        fileSystem.operations.where(
          (operation) => operation.startsWith('read:'),
        ),
        isEmpty,
      );
    });
  });

  test(
    'explicit connection test performs one bounded stream-json probe',
    () async {
      // Arrange
      final credentialsPath = _join(claudeHome, '.credentials.json');
      final fileSystem = _FakeMetadataFileSystem(
        metadata: <String, ClaudeCodeFileMetadata>{
          credentialsPath: const ClaudeCodeFileMetadata(
            exists: true,
            isFile: true,
          ),
        },
      );
      final processRunner = _FakeProcessRunner.success();
      final probe = _FakeConnectionProbe(
        result: const ClaudeCodeConnectionProbeResult(
          success: true,
          message: 'Claude Code 连接正常',
          cliVersion: '2.1.224',
          model: 'claude-sonnet-4-5',
        ),
      );
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: processRunner.call,
        connectionProbe: probe.call,
        fileSystem: fileSystem,
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      // Act
      final (result, models) = await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
      );

      // Assert
      expect(result.success, isTrue);
      expect(result.cliCallable, isTrue);
      expect(result.accountValid, isTrue);
      expect(result.protocolReady, isTrue);
      expect(result.protocolVersion, 'stream-json');
      expect(result.agentVersion, '2.1.224');
      expect(models, isEmpty);
      expect(probe.calls, 1);
      expect(probe.lastTimeout, const Duration(seconds: 20));
      expect(processRunner.calls.single.arguments, const <String>['--version']);
    },
  );

  test('connection handshake waits for matching init and result', () {
    // Arrange
    final handshake = ClaudeCodeConnectionHandshake(
      expectedSessionId: 'session-1',
    );

    // Act
    final afterInit = handshake.accept(
      const StreamJsonEvent(
        type: 'system',
        subtype: 'init',
        raw: <String, Object?>{
          'session_id': 'session-1',
          'claude_code_version': '2.1.224',
          'model': 'claude-sonnet-4-5',
        },
      ),
    );
    final afterResult = handshake.accept(
      const StreamJsonEvent(
        type: 'result',
        subtype: 'success',
        raw: <String, Object?>{},
      ),
    );

    // Assert
    expect(afterInit, isNull);
    expect(afterResult?.success, isTrue);
    expect(afterResult?.cliVersion, '2.1.224');
    expect(afterResult?.model, 'claude-sonnet-4-5');
  });
}

class _FakeClaudeCodeCliLocator extends ClaudeCodeCliLocator {
  const _FakeClaudeCodeCliLocator();

  @override
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
    return const ResolvedCliCommand(
      displayPath: '/fake/claude',
      executable: '/fake/claude',
    );
  }

  @override
  Future<ResolvedCliCommand?> resolvePath(String path) =>
      locate(AgentProviderConfig.defaultClaudeCode);
}

final class _FakeProcessRunner {
  _FakeProcessRunner.failure(this.error) : result = null;

  _FakeProcessRunner.success()
    : result = const CliProcessResult(
        exitCode: 0,
        stdout: '2.1.224 (Claude Code)',
        stderr: '',
        elapsed: Duration(milliseconds: 4),
      ),
      error = null;

  final CliProcessResult? result;
  final Object? error;
  final List<_ProcessCall> calls = <_ProcessCall>[];

  Future<CliProcessResult> call(
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 10),
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        command: command,
        arguments: List<String>.of(arguments),
        timeout: timeout,
      ),
    );
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result!;
  }
}

final class _ProcessCall {
  const _ProcessCall({
    required this.command,
    required this.arguments,
    required this.timeout,
  });

  final ResolvedCliCommand command;
  final List<String> arguments;
  final Duration timeout;
}

final class _FakeMetadataFileSystem implements ClaudeCodeMetadataFileSystem {
  _FakeMetadataFileSystem({
    Map<String, ClaudeCodeFileMetadata>? metadata,
    List<String>? logPaths,
  }) : metadata = metadata ?? <String, ClaudeCodeFileMetadata>{},
       logPaths = logPaths ?? <String>[];

  final Map<String, ClaudeCodeFileMetadata> metadata;
  final List<String> logPaths;
  final List<String> operations = <String>[];

  @override
  Future<List<String>> listLogFiles(String directoryPath) async {
    operations.add('list:$directoryPath');
    return List<String>.unmodifiable(logPaths);
  }

  @override
  Future<ClaudeCodeFileMetadata> stat(String path) async {
    operations.add('stat:$path');
    return metadata[path] ?? const ClaudeCodeFileMetadata.missing();
  }
}

final class _FakeConnectionProbe {
  _FakeConnectionProbe({
    this.result = const ClaudeCodeConnectionProbeResult(success: true),
  });

  final ClaudeCodeConnectionProbeResult result;
  int calls = 0;
  Duration? lastTimeout;

  Future<ClaudeCodeConnectionProbeResult> call(
    AgentProviderConfig providerConfig, {
    required Duration timeout,
  }) async {
    calls += 1;
    lastTimeout = timeout;
    return result;
  }
}

String _join(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}

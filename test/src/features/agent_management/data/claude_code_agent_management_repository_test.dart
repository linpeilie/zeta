import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_auth_status_probe.dart';
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
      final authStatus = _FakeAuthStatusLoader();
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: processRunner.call,
        authStatusLoader: authStatus.call,
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
      expect(authStatus.calls, 0);
      expect(probe.calls, 0);
      expect(fileSystem.operations, <String>[
        'list:${_join(claudeHome, 'logs')}',
      ]);
    });

    test(
      'reports auth evidence unavailable without guessing credential files',
      () async {
        // Arrange
        final processRunner = _FakeProcessRunner.success();
        final fileSystem = _FakeMetadataFileSystem();
        final probe = _FakeConnectionProbe();
        final authStatus = _FakeAuthStatusLoader();
        final progress = <AgentDetectionProgress>[];
        final repository = ClaudeCodeAgentManagementRepository(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: processRunner.call,
          authStatusLoader: authStatus.call,
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
        expect(agent.accountState, AgentAccountState.unavailable);
        expect(agent.accountLabel, 'Claude Code 登录证据不可用');
        expect(agent.currentVersion, '2.1.224');
        expect(agent.versionState, AgentVersionState.current);
        expect(agent.runtimeState, AgentRuntimeState.notRunning);
        expect(agent.configExists, isFalse);
        expect(probe.calls, 0);
        expect(authStatus.calls, 1);
        expect(progress.last.completed, 3);
        expect(progress.last.total, 3);
        expect(fileSystem.operations, <String>[
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

    test('does not infer login from a credential-shaped filename', () async {
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
      final authStatus = _FakeAuthStatusLoader();
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: _FakeProcessRunner.success().call,
        authStatusLoader: authStatus.call,
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
      expect(agent.accountState, AgentAccountState.unavailable);
      expect(agent.accountLabel, 'Claude Code 登录证据不可用');
      expect(agent.configExists, isTrue);
      expect(agent.configModifiedAt, configModifiedAt);
      expect(agent.logPaths, <String>[logPath]);
      expect(probe.calls, 0);
      expect(authStatus.calls, 1);
      expect(fileSystem.operations, <String>[
        'stat:$configPath',
        'list:${_join(claudeHome, 'logs')}',
      ]);
      expect(fileSystem.operations, isNot(contains('stat:$credentialsPath')));
      expect(
        fileSystem.operations.where(
          (operation) => operation.startsWith('read:'),
        ),
        isEmpty,
      );
    });

    for (final authCase
        in <
          ({
            String name,
            ClaudeCodeAuthStatusSnapshot snapshot,
            String expectedLabel,
          })
        >[
          (
            name: 'Claude.ai OAuth',
            snapshot: ClaudeCodeAuthStatusSnapshot(
              loggedIn: true,
              authMethod: 'claude.ai',
              apiProvider: 'firstParty',
              subscriptionType: 'pro',
            ),
            expectedLabel: 'Claude.ai 已登录 · Claude Pro',
          ),
          (
            name: 'API key',
            snapshot: ClaudeCodeAuthStatusSnapshot(
              loggedIn: true,
              authMethod: 'api_key',
              apiProvider: 'firstParty',
            ),
            expectedLabel: '已通过 Anthropic API key 配置认证',
          ),
          (
            name: 'third-party Provider',
            snapshot: ClaudeCodeAuthStatusSnapshot(
              loggedIn: true,
              authMethod: 'third_party',
              apiProvider: 'bedrock',
            ),
            expectedLabel: '已配置 Amazon Bedrock',
          ),
        ]) {
      test(
        'prefers ${authCase.name} evidence without credential stat',
        () async {
          final fileSystem = _FakeMetadataFileSystem();
          final authStatus = _FakeAuthStatusLoader(result: authCase.snapshot);
          final repository = ClaudeCodeAgentManagementRepository(
            locator: const _FakeClaudeCodeCliLocator(),
            processRunner: _FakeProcessRunner.success().call,
            authStatusLoader: authStatus.call,
            connectionProbe: _FakeConnectionProbe().call,
            fileSystem: fileSystem,
            now: () => detectedAt,
            claudeHomeProvider: () => claudeHome,
          );

          final agent = await repository.detect(
            providerConfig: AgentProviderConfig.defaultClaudeCode,
            enabled: true,
          );

          expect(agent.accountState, AgentAccountState.loggedIn);
          expect(agent.accountLabel, authCase.expectedLabel);
          expect(authStatus.calls, 1);
          expect(fileSystem.operations, <String>[
            'stat:${_join(claudeHome, 'settings.json')}',
            'list:${_join(claudeHome, 'logs')}',
          ]);
        },
      );
    }

    test(
      'valid logged-out evidence skips stat and keeps the runtime available',
      () async {
        final fileSystem = _FakeMetadataFileSystem(
          metadata: <String, ClaudeCodeFileMetadata>{
            _join(claudeHome, '.credentials.json'):
                const ClaudeCodeFileMetadata(exists: true, isFile: true),
          },
        );
        final authStatus = _FakeAuthStatusLoader(
          result: const ClaudeCodeAuthStatusSnapshot(
            loggedIn: false,
            authMethod: 'none',
            apiProvider: 'firstParty',
          ),
        );
        final repository = ClaudeCodeAgentManagementRepository(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: _FakeProcessRunner.success().call,
          authStatusLoader: authStatus.call,
          connectionProbe: _FakeConnectionProbe().call,
          fileSystem: fileSystem,
          now: () => detectedAt,
          claudeHomeProvider: () => claudeHome,
        );

        final agent = await repository.detect(
          providerConfig: AgentProviderConfig.defaultClaudeCode,
          enabled: true,
        );

        expect(agent.accountState, AgentAccountState.loggedOut);
        expect(agent.accountLabel, '未检测到 Claude.ai OAuth 或 API key 登录证据');
        expect(agent.runtimeState, AgentRuntimeState.notRunning);
        expect(agent.suggestion, contains('连接测试确认当前 CLI 认证路径'));
        expect(fileSystem.operations, <String>[
          'stat:${_join(claudeHome, 'settings.json')}',
          'list:${_join(claudeHome, 'logs')}',
        ]);
      },
    );

    test(
      'probe failure is unavailable and ignores credential filenames',
      () async {
        final credentialsPath = _join(claudeHome, '.credentials.json');
        final fileSystem = _FakeMetadataFileSystem(
          metadata: <String, ClaudeCodeFileMetadata>{
            credentialsPath: const ClaudeCodeFileMetadata(
              exists: true,
              isFile: true,
            ),
          },
        );
        final repository = ClaudeCodeAgentManagementRepository(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: _FakeProcessRunner.success().call,
          authStatusLoader: _FakeAuthStatusLoader(
            error: StateError('redacted damaged auth status'),
          ).call,
          connectionProbe: _FakeConnectionProbe().call,
          fileSystem: fileSystem,
          now: () => detectedAt,
          claudeHomeProvider: () => claudeHome,
        );

        final agent = await repository.detect(
          providerConfig: AgentProviderConfig.defaultClaudeCode,
          enabled: true,
        );

        expect(agent.accountState, AgentAccountState.unavailable);
        expect(agent.accountLabel, 'Claude Code 登录证据不可用');
        expect(agent.errorMessage, '无法通过 Claude CLI 检查登录状态。');
        expect(agent.suggestion, contains('claude auth status --json'));
        expect(fileSystem.operations, isNot(contains('stat:$credentialsPath')));
      },
    );
  });

  test(
    'logged-out evidence does not block the no-Prompt initialize probe',
    () async {
      // Arrange
      final fileSystem = _FakeMetadataFileSystem();
      final authStatus = _FakeAuthStatusLoader(
        result: const ClaudeCodeAuthStatusSnapshot(
          loggedIn: false,
          authMethod: 'none',
          apiProvider: 'firstParty',
        ),
      );
      final processRunner = _FakeProcessRunner.success();
      final probe = _FakeConnectionProbe();
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: processRunner.call,
        authStatusLoader: authStatus.call,
        connectionProbe: probe.call,
        fileSystem: fileSystem,
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      // Act
      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
        enabled: true,
      );
      final (result, models) = await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
      );

      // Assert
      expect(detected.accountState, AgentAccountState.loggedOut);
      expect(result.success, isTrue);
      expect(result.cliCallable, isTrue);
      expect(result.accountValid, isTrue);
      expect(result.protocolReady, isTrue);
      expect(result.protocolVersion, 'stream-json');
      expect(result.agentVersion, '2.1.224');
      expect(result.message, contains('initialize 成功'));
      expect(result.capabilitySummary, const <String>[
        'stream-json initialize',
      ]);
      expect(models, isEmpty);
      expect(probe.calls, 1);
      expect(probe.lastTimeout, const Duration(seconds: 20));
      expect(authStatus.calls, 1);
      expect(
        processRunner.calls.map((call) => call.arguments),
        everyElement(const <String>['--version']),
      );
      expect(processRunner.calls, hasLength(2));
    },
  );

  test(
    'unavailable auth and initialize evidence never guesses logged-out',
    () async {
      final credentialsPath = _join(claudeHome, '.credentials.json');
      final fileSystem = _FakeMetadataFileSystem(
        metadata: <String, ClaudeCodeFileMetadata>{
          credentialsPath: const ClaudeCodeFileMetadata(
            exists: true,
            isFile: true,
          ),
        },
      );
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: _FakeProcessRunner.success().call,
        authStatusLoader: _FakeAuthStatusLoader().call,
        connectionProbe: _FakeConnectionProbe(
          error: const ClaudeCodeCliMetadataProbeException(
            ClaudeCodeCliMetadataProbeFailure.processUnavailable,
          ),
        ).call,
        fileSystem: fileSystem,
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
        enabled: true,
      );
      final (connection, _) = await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
      );

      expect(detected.accountState, AgentAccountState.unavailable);
      expect(detected.accountState, isNot(AgentAccountState.loggedOut));
      expect(connection.success, isFalse);
      expect(connection.protocolReady, isFalse);
      expect(connection.message, '无法启动 Claude Code initialize 探测。');
      expect(fileSystem.operations, isNot(contains('stat:$credentialsPath')));
    },
  );

  for (final failureCase
      in <({ClaudeCodeCliMetadataProbeFailure failure, String message})>[
        (
          failure: ClaudeCodeCliMetadataProbeFailure.processUnavailable,
          message: '无法启动 Claude Code initialize 探测。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.timeout,
          message: 'Claude Code initialize 在 20 秒内未完成。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.processExited,
          message: 'Claude Code 进程在 initialize 完成前退出。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.errorResponse,
          message: 'Claude Code 拒绝了 initialize 请求。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.invalidResponse,
          message: 'Claude Code 返回的 initialize 响应无效。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.invalidStream,
          message: 'Claude Code 返回了无效的 stream-json 数据。',
        ),
        (
          failure: ClaudeCodeCliMetadataProbeFailure.transportFailure,
          message: 'Claude Code initialize 通信失败。',
        ),
      ]) {
    test('maps ${failureCase.failure.name} to a redacted diagnostic', () async {
      final repository = ClaudeCodeAgentManagementRepository(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: _FakeProcessRunner.success().call,
        authStatusLoader: _FakeAuthStatusLoader().call,
        connectionProbe: _FakeConnectionProbe(
          error: ClaudeCodeCliMetadataProbeException(failureCase.failure),
        ).call,
        fileSystem: _FakeMetadataFileSystem(),
        now: () => detectedAt,
        claudeHomeProvider: () => claudeHome,
      );

      final (result, models) = await repository.testConnection(
        providerConfig: AgentProviderConfig.defaultClaudeCode,
      );

      expect(result.success, isFalse);
      expect(result.cliCallable, isTrue);
      expect(result.accountValid, isFalse);
      expect(result.protocolReady, isFalse);
      expect(result.failureStage, AgentDiagnosticStage.protocolHandshake);
      expect(result.message, failureCase.message);
      expect(models, isEmpty);
    });
  }

  test('maps an injected timeout without exposing exception details', () async {
    final repository = ClaudeCodeAgentManagementRepository(
      locator: const _FakeClaudeCodeCliLocator(),
      processRunner: _FakeProcessRunner.success().call,
      authStatusLoader: _FakeAuthStatusLoader().call,
      connectionProbe: _FakeConnectionProbe(
        error: TimeoutException('sensitive timeout detail'),
      ).call,
      fileSystem: _FakeMetadataFileSystem(),
      now: () => detectedAt,
      claudeHomeProvider: () => claudeHome,
    );

    final (result, _) = await repository.testConnection(
      providerConfig: AgentProviderConfig.defaultClaudeCode,
    );

    expect(result.success, isFalse);
    expect(result.message, 'Claude Code initialize 在 20 秒内未完成。');
    expect(result.message, isNot(contains('sensitive')));
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

final class _FakeAuthStatusLoader {
  _FakeAuthStatusLoader({this.result, this.error});

  final ClaudeCodeAuthStatusSnapshot? result;
  final Object? error;
  int calls = 0;

  Future<ClaudeCodeAuthStatusSnapshot?> call(
    AgentProviderConfig providerConfig,
  ) async {
    calls += 1;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
    return result;
  }
}

final class _FakeConnectionProbe {
  _FakeConnectionProbe({this.error});

  final Object? error;
  int calls = 0;
  Duration? lastTimeout;

  Future<void> call(
    AgentProviderConfig providerConfig, {
    required Duration timeout,
  }) async {
    calls += 1;
    lastTimeout = timeout;
    final failure = error;
    if (failure != null) {
      throw failure;
    }
  }
}

String _join(String parent, String child) {
  return '$parent${Platform.pathSeparator}$child';
}

import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent_management/data/claude_code_auth_status_probe.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';

void main() {
  group('ClaudeCodeAuthStatusProbe', () {
    test(
      'projects the sanitized OAuth fixture and drops identity fields',
      () async {
        const fixturePath =
            'test/src/features/agent/data/datasources/claude_code/fixtures/'
            'auth_status_2_1_228_redacted.json';
        final runner = _FakeProcessRunner(
          result: CliProcessResult(
            exitCode: 0,
            stdout: await File(fixturePath).readAsString(),
            stderr: 'sensitive stderr must stay ignored',
            elapsed: const Duration(milliseconds: 4),
          ),
        );
        final probe = ClaudeCodeAuthStatusProbe(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: runner.call,
        );
        final config = AgentProviderConfig.defaultClaudeCode.copyWith(
          environment: const <String, String>{'CLAUDE_CONFIG_DIR': '/redacted'},
        );

        final snapshot = await probe.probe(config);

        expect(snapshot, isNotNull);
        expect(snapshot!.loggedIn, isTrue);
        expect(snapshot.authMethod, 'claude.ai');
        expect(snapshot.apiProvider, 'firstParty');
        expect(snapshot.subscriptionType, 'pro');
        expect(runner.calls, hasLength(1));
        expect(runner.calls.single.arguments, const <String>[
          'auth',
          'status',
          '--json',
        ]);
        expect(runner.calls.single.timeout, const Duration(seconds: 10));
        expect(runner.calls.single.environment, config.environment);
        expect('$snapshot', isNot(contains('email')));
        expect('$snapshot', isNot(contains('organization')));
        expect('$snapshot', isNot(contains('sensitive')));
      },
    );

    for (final authCase
        in <
          ({String name, String json, String authMethod, String apiProvider})
        >[
          (
            name: 'API key',
            json:
                '{"loggedIn":true,"authMethod":"api_key",'
                '"apiProvider":"firstParty","apiKeySource":"secret-source"}',
            authMethod: 'api_key',
            apiProvider: 'firstParty',
          ),
          (
            name: 'third-party provider',
            json:
                '{"loggedIn":true,"authMethod":"third_party",'
                '"apiProvider":"bedrock","email":"sensitive@example.invalid"}',
            authMethod: 'third_party',
            apiProvider: 'bedrock',
          ),
        ]) {
      test('projects ${authCase.name} without unrelated fields', () async {
        final runner = _FakeProcessRunner(
          result: CliProcessResult(
            exitCode: 0,
            stdout: authCase.json,
            stderr: '',
            elapsed: Duration.zero,
          ),
        );
        final probe = ClaudeCodeAuthStatusProbe(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: runner.call,
        );

        final snapshot = await probe.probe(
          AgentProviderConfig.defaultClaudeCode,
        );

        expect(snapshot?.loggedIn, isTrue);
        expect(snapshot?.authMethod, authCase.authMethod);
        expect(snapshot?.apiProvider, authCase.apiProvider);
        expect(snapshot?.subscriptionType, isNull);
        expect('$snapshot', isNot(contains('sensitive')));
        expect('$snapshot', isNot(contains('secret-source')));
      });
    }

    test('accepts valid logged-out JSON when the CLI exits with 1', () async {
      final runner = _FakeProcessRunner(
        result: const CliProcessResult(
          exitCode: 1,
          stdout:
              '{"loggedIn":false,"authMethod":"none",'
              '"apiProvider":"firstParty"}',
          stderr: '',
          elapsed: Duration.zero,
        ),
      );
      final probe = ClaudeCodeAuthStatusProbe(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: runner.call,
      );

      final snapshot = await probe.probe(AgentProviderConfig.defaultClaudeCode);

      expect(snapshot?.loggedIn, isFalse);
      expect(snapshot?.authMethod, 'none');
      expect(snapshot?.apiProvider, 'firstParty');
    });

    test(
      'returns unavailable for a missing command without running it',
      () async {
        final runner = _FakeProcessRunner(
          result: const CliProcessResult(
            exitCode: 0,
            stdout: '{"loggedIn":true}',
            stderr: '',
            elapsed: Duration.zero,
          ),
        );
        final probe = ClaudeCodeAuthStatusProbe(
          locator: const _MissingClaudeCodeCliLocator(),
          processRunner: runner.call,
        );

        expect(
          await probe.probe(AgentProviderConfig.defaultClaudeCode),
          isNull,
        );
        expect(runner.calls, isEmpty);
      },
    );

    for (final damaged in <String>[
      '',
      '{not-json',
      '[]',
      '{"loggedIn":"true"}',
      '{"authMethod":"claude.ai"}',
    ]) {
      test('rejects damaged output: $damaged', () async {
        final probe = ClaudeCodeAuthStatusProbe(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: _FakeProcessRunner(
            result: CliProcessResult(
              exitCode: 0,
              stdout: damaged,
              stderr: '',
              elapsed: Duration.zero,
            ),
          ).call,
        );

        expect(
          await probe.probe(AgentProviderConfig.defaultClaudeCode),
          isNull,
        );
      });
    }

    test('rejects unsupported exit codes even with valid JSON', () async {
      final probe = ClaudeCodeAuthStatusProbe(
        locator: const _FakeClaudeCodeCliLocator(),
        processRunner: _FakeProcessRunner(
          result: const CliProcessResult(
            exitCode: 2,
            stdout: '{"loggedIn":true}',
            stderr: '',
            elapsed: Duration.zero,
          ),
        ).call,
      );

      expect(await probe.probe(AgentProviderConfig.defaultClaudeCode), isNull);
    });

    for (final error in <Object>[
      ProcessException('claude', const <String>['auth']),
      TimeoutException('redacted timeout'),
      const FileSystemException('redacted file failure'),
    ]) {
      test('contains ${error.runtimeType} as unavailable', () async {
        final probe = ClaudeCodeAuthStatusProbe(
          locator: const _FakeClaudeCodeCliLocator(),
          processRunner: _FakeProcessRunner(error: error).call,
        );

        expect(
          await probe.probe(AgentProviderConfig.defaultClaudeCode),
          isNull,
        );
      });
    }
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
}

class _MissingClaudeCodeCliLocator extends ClaudeCodeCliLocator {
  const _MissingClaudeCodeCliLocator();

  @override
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async => null;
}

final class _FakeProcessRunner {
  _FakeProcessRunner({this.result, this.error});

  final CliProcessResult? result;
  final Object? error;
  final List<_ProcessCall> calls = <_ProcessCall>[];

  Future<CliProcessResult> call(
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    calls.add(
      _ProcessCall(
        arguments: List<String>.of(arguments),
        timeout: timeout,
        environment: environment,
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
    required this.arguments,
    required this.timeout,
    required this.environment,
  });

  final List<String> arguments;
  final Duration timeout;
  final Map<String, String>? environment;
}

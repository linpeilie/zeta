import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_macos_keychain_source.dart';

void main() {
  group('ClaudeCodeMacOsKeychainSource', () {
    test(
      'uses the production service and parameterized account arguments',
      () async {
        const secret = 'oauth-sensitive-token-value';
        final process = _RecordingKeychainProcess(
          result: const ClaudeCodeKeychainProcessResult(
            exitCode: 0,
            stdout: '{"claudeAiOauth":{"accessToken":"$secret"}}',
          ),
        );
        final source = ClaudeCodeMacOsKeychainSource(
          environment: const <String, String>{
            'HOME': '/fixture/home',
            'USER': 'fixture-user',
          },
          processRunner: process.call,
        );

        final result = await source.read();

        expect(result, contains(secret));
        expect(source.serviceName, 'Claude Code-credentials');
        expect(source.accountName, 'fixture-user');
        expect(process.calls, hasLength(1));
        expect(process.calls.single.executable, 'security');
        expect(process.calls.single.arguments, const <String>[
          'find-generic-password',
          '-a',
          'fixture-user',
          '-w',
          '-s',
          'Claude Code-credentials',
        ]);
        expect(process.calls.single.timeout, const Duration(seconds: 10));
      },
    );

    test('adds the Claude Code SHA-256 suffix for a custom config dir', () {
      final source = ClaudeCodeMacOsKeychainSource(
        environment: const <String, String>{
          'CLAUDE_CONFIG_DIR': '/fixture/custom-claude',
          'USER': 'fixture-user',
        },
        processRunner: _RecordingKeychainProcess.missing().call,
      );

      expect(source.serviceName, 'Claude Code-credentials-c7fe66de');
    });

    test('normalizes a custom config dir to NFC before hashing', () {
      final composed = claudeCodeMacOsKeychainServiceName(
        const <String, String>{'CLAUDE_CONFIG_DIR': '/fixture/caf\u00e9'},
      );
      final decomposed = claudeCodeMacOsKeychainServiceName(
        const <String, String>{'CLAUDE_CONFIG_DIR': '/fixture/cafe\u0301'},
      );

      expect(decomposed, composed);
    });

    test('keeps Claude Code OAuth environment suffix ordering', () {
      expect(
        claudeCodeMacOsKeychainServiceName(const <String, String>{
          'CLAUDE_CODE_CUSTOM_OAUTH_URL': 'https://allowed.fixture',
          'CLAUDE_CONFIG_DIR': '/fixture/custom-claude',
        }),
        'Claude Code-custom-oauth-credentials-c7fe66de',
      );
      expect(
        claudeCodeMacOsKeychainServiceName(const <String, String>{
          'USER_TYPE': 'ant',
          'USE_STAGING_OAUTH': 'yes',
        }),
        'Claude Code-staging-oauth-credentials',
      );
    });

    for (final failureCase
        in <({String name, _RecordingKeychainProcess process})>[
          (name: 'missing item', process: _RecordingKeychainProcess.missing()),
          (
            name: 'locked or denied keychain',
            process: _RecordingKeychainProcess(
              result: const ClaudeCodeKeychainProcessResult(
                exitCode: 36,
                stdout: '',
              ),
            ),
          ),
          (
            name: 'timeout',
            process: _RecordingKeychainProcess(
              error: TimeoutException('redacted'),
            ),
          ),
          (
            name: 'process failure',
            process: _RecordingKeychainProcess(error: StateError('redacted')),
          ),
        ]) {
      test(
        '${failureCase.name} returns null without surfacing diagnostics',
        () async {
          final source = ClaudeCodeMacOsKeychainSource(
            environment: const <String, String>{'USER': 'fixture-user'},
            processRunner: failureCase.process.call,
          );

          await expectLater(source.read(), completion(isNull));
          expect(failureCase.process.calls, hasLength(1));
        },
      );
    }

    test('process result toString never includes stdout credentials', () {
      const secret = 'oauth-sensitive-token-value';
      const result = ClaudeCodeKeychainProcessResult(
        exitCode: 0,
        stdout: secret,
      );

      expect(result.toString(), contains('hasOutput: true'));
      expect(result.toString(), isNot(contains(secret)));
      expect(result.toString(), isNot(contains(secret.substring(0, 8))));
    });
  });
}

final class _RecordingKeychainProcess {
  _RecordingKeychainProcess({this.result, this.error});

  factory _RecordingKeychainProcess.missing() {
    return _RecordingKeychainProcess(
      result: const ClaudeCodeKeychainProcessResult(exitCode: 44, stdout: ''),
    );
  }

  final ClaudeCodeKeychainProcessResult? result;
  final Object? error;
  final List<_KeychainCall> calls = <_KeychainCall>[];

  Future<ClaudeCodeKeychainProcessResult> call(
    String executable,
    List<String> arguments, {
    required Duration timeout,
  }) async {
    calls.add(
      _KeychainCall(
        executable: executable,
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

final class _KeychainCall {
  const _KeychainCall({
    required this.executable,
    required this.arguments,
    required this.timeout,
  });

  final String executable;
  final List<String> arguments;
  final Duration timeout;
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';
import 'package:zeta_agent_provider_claude_code/zeta_agent_provider_claude_code_testing.dart';

void main() {
  group('ClaudeCodeMacOsKeychainSource', () {
    test(
      'writes a quoted interactive command over stdin and verifies storage',
      () async {
        const contents = '{"claudeAiOauth":{"accessToken":"synthetic-secret"}}';
        final sink = _Input();
        final process = _Process(sink);
        final source = ClaudeCodeMacOsKeychainSource(
          environment: const {'USER': 'fixture "quoted" user'},
          processStarter: (executable, arguments) async {
            expect(executable, '/usr/bin/security');
            expect(arguments, ['-i']);
            return process;
          },
          processRunner: (executable, arguments, {required timeout}) async =>
              const ClaudeCodeKeychainProcessResult(
                exitCode: 0,
                stdout: contents,
              ),
        );
        await source.write(contents);
        final command = utf8.decode(sink.bytes);
        expect(command, startsWith('add-generic-password -U '));
        expect(command, contains(r'-a "fixture \"quoted\" user"'));
        final hex = RegExp(r'-X "([0-9a-f]+)"').firstMatch(command)!.group(1)!;
        expect(
          utf8.decode([
            for (var i = 0; i < hex.length; i += 2)
              int.parse(hex.substring(i, i + 2), radix: 16),
          ]),
          contents,
        );
        expect(command.split('\n'), hasLength(2));
      },
    );

    test(
      'interactive exit zero with unchanged storage is still a failure',
      () async {
        final source = ClaudeCodeMacOsKeychainSource(
          environment: const {'USER': 'fixture'},
          processStarter: (_, arguments) async => _Process(_Input()),
          processRunner: (_, arguments, {required timeout}) async =>
              const ClaudeCodeKeychainProcessResult(
                exitCode: 0,
                stdout: 'unchanged',
              ),
        );
        await expectLater(
          source.write('synthetic-new'),
          throwsA(isA<ClaudeCodeSecureCredentialsUnavailable>()),
        );
      },
    );

    test(
      'oversized command and newline account are rejected before process start',
      () async {
        var starts = 0;
        for (final account in ['fixture', 'bad\naccount']) {
          final source = ClaudeCodeMacOsKeychainSource(
            environment: {'USER': account},
            processStarter: (_, arguments) async {
              starts++;
              throw StateError('must not start');
            },
          );
          await expectLater(
            source.write(account == 'fixture' ? 'x' * 2200 : 'short'),
            throwsA(isA<ClaudeCodeSecureCredentialsUnavailable>()),
          );
        }
        expect(starts, 0);
      },
    );

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
        '${failureCase.name} preserves absence or a sanitized failure',
        () async {
          final source = ClaudeCodeMacOsKeychainSource(
            environment: const <String, String>{'USER': 'fixture-user'},
            processRunner: failureCase.process.call,
          );

          if (failureCase.name == 'missing item') {
            await expectLater(source.read(), completion(isNull));
          } else {
            await expectLater(
              source.read(),
              throwsA(isA<ClaudeCodeSecureCredentialsUnavailable>()),
            );
          }
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

final class _Input implements StreamConsumer<List<int>> {
  final bytes = <int>[];
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      bytes.addAll(chunk);
    }
  }

  @override
  Future<void> close() async {}
}

final class _Process implements Process {
  _Process(_Input input) : stdin = IOSink(input);
  @override
  final IOSink stdin;
  @override
  Stream<List<int>> get stdout => const Stream.empty();
  @override
  Stream<List<int>> get stderr => const Stream.empty();
  @override
  Future<int> get exitCode async => 0;
  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) => true;
  @override
  int get pid => 0;
}

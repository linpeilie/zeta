import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/grok_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

import '../../../testing/ide_test_harness.dart';

void main() {
  group('parseGrokUpdateCheckJson', () {
    test('parses stable update-check payload', () {
      const raw =
          '{"currentVersion":"0.2.99","latestVersion":"0.3.0","updateAvailable":true,"installer":"internal","channel":"stable","autoUpdate":true,"error":null}';
      final payload = parseGrokUpdateCheckJson(raw);
      expect(payload, isNotNull);
      expect(payload!.currentVersion, '0.2.99');
      expect(payload.latestVersion, '0.3.0');
      expect(payload.updateAvailable, isTrue);
      expect(payload.error, isNull);
    });

    test('tolerates surrounding log noise and null error', () {
      const raw = '''
checking...
{"currentVersion":"0.2.99","latestVersion":"0.2.99","updateAvailable":false,"error":null}
done
''';
      final payload = parseGrokUpdateCheckJson(raw);
      expect(payload?.latestVersion, '0.2.99');
      expect(payload?.updateAvailable, isFalse);
      expect(payload?.error, isNull);
    });
  });

  group('GrokAgentManagementRepository', () {
    late Directory root;

    setUp(() {
      root = Directory.systemTemp.createTempSync('zeta-grok-mgmt-');
    });

    tearDown(() async {
      if (await root.exists()) {
        await root.delete(recursive: true);
      }
    });

    test('detects installed CLI and marks update available', () async {
      final bin = Directory('${root.path}${Platform.pathSeparator}bin')
        ..createSync();
      final grokExe = File(
        '${bin.path}${Platform.pathSeparator}${Platform.isWindows ? 'grok.exe' : 'grok'}',
      )..writeAsStringSync('stub');

      File(
        '${root.path}${Platform.pathSeparator}auth.json',
      ).writeAsStringSync('{"https://auth.x.ai::demo":{"key":"token"}}');
      File(
        '${root.path}${Platform.pathSeparator}config.toml',
      ).writeAsStringSync('ui.compact_mode = false\n');
      Directory('${root.path}${Platform.pathSeparator}logs').createSync();
      File(
        '${root.path}${Platform.pathSeparator}logs${Platform.pathSeparator}unified.jsonl',
      ).writeAsStringSync('{"msg":"hello"}\n');

      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        processRunner: _scriptedRunner(<List<String>, CliProcessResult>{
          const <String>['--version']: const CliProcessResult(
            exitCode: 0,
            stdout: 'grok 0.2.99 (b1b49ccb71)\n',
            stderr: '',
            elapsed: Duration(milliseconds: 12),
          ),
          const <String>['update', '--check', '--json']: const CliProcessResult(
            exitCode: 0,
            stdout:
                '{"currentVersion":"0.2.99","latestVersion":"0.3.1","updateAvailable":true,"error":null}\n',
            stderr: '',
            elapsed: Duration(milliseconds: 20),
          ),
        }),
        grokHomeProvider: () => root.path,
      );

      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultGrok.copyWith(
          extra: <String, Object?>{'cliPath': grokExe.path},
        ),
        enabled: true,
      );

      expect(detected.definition.id, grokAgentProviderId);
      expect(detected.installed, isTrue);
      expect(detected.currentVersion, '0.2.99');
      expect(detected.latestVersion, '0.3.1');
      expect(detected.versionState, AgentVersionState.updateAvailable);
      expect(detected.updateAvailable, isTrue);
      expect(detected.accountState, AgentAccountState.loggedIn);
      expect(detected.configExists, isTrue);
      expect(detected.runtimeState, AgentRuntimeState.idle);
      expect(detected.logPaths, isNotEmpty);
    });

    test('marks version current when already up to date', () async {
      final bin = Directory('${root.path}${Platform.pathSeparator}bin')
        ..createSync();
      final grokExe = File(
        '${bin.path}${Platform.pathSeparator}${Platform.isWindows ? 'grok.exe' : 'grok'}',
      )..writeAsStringSync('stub');
      File(
        '${root.path}${Platform.pathSeparator}auth.json',
      ).writeAsStringSync('{"token":"x"}');

      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        processRunner: _scriptedRunner(<List<String>, CliProcessResult>{
          const <String>['--version']: const CliProcessResult(
            exitCode: 0,
            stdout: 'grok 0.2.99\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
          const <String>['update', '--check', '--json']: const CliProcessResult(
            exitCode: 0,
            stdout:
                '{"currentVersion":"0.2.99","latestVersion":"0.2.99","updateAvailable":false,"error":null}\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        }),
        grokHomeProvider: () => root.path,
      );

      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultGrok.copyWith(
          extra: <String, Object?>{'cliPath': grokExe.path},
        ),
        enabled: true,
      );

      expect(detected.latestVersion, '0.2.99');
      expect(detected.versionState, AgentVersionState.current);
      expect(detected.updateAvailable, isFalse);
    });

    test('marks checkFailed when update check fails', () async {
      final bin = Directory('${root.path}${Platform.pathSeparator}bin')
        ..createSync();
      final grokExe = File(
        '${bin.path}${Platform.pathSeparator}${Platform.isWindows ? 'grok.exe' : 'grok'}',
      )..writeAsStringSync('stub');
      File(
        '${root.path}${Platform.pathSeparator}auth.json',
      ).writeAsStringSync('{"token":"x"}');

      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        processRunner: _scriptedRunner(<List<String>, CliProcessResult>{
          const <String>['--version']: const CliProcessResult(
            exitCode: 0,
            stdout: 'grok 0.2.99\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
          const <String>['update', '--check', '--json']: const CliProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'network unavailable',
            elapsed: Duration.zero,
          ),
        }),
        grokHomeProvider: () => root.path,
      );

      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultGrok.copyWith(
          extra: <String, Object?>{'cliPath': grokExe.path},
        ),
        enabled: true,
      );

      expect(detected.currentVersion, '0.2.99');
      expect(detected.latestVersion, isNull);
      expect(detected.versionState, AgentVersionState.checkFailed);
    });

    test('marks logged out when auth.json missing', () async {
      final bin = Directory('${root.path}${Platform.pathSeparator}bin')
        ..createSync();
      final grokExe = File(
        '${bin.path}${Platform.pathSeparator}${Platform.isWindows ? 'grok.exe' : 'grok'}',
      )..writeAsStringSync('stub');

      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        processRunner: _scriptedRunner(<List<String>, CliProcessResult>{
          const <String>['--version']: const CliProcessResult(
            exitCode: 0,
            stdout: 'grok 0.1.0\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
          const <String>['update', '--check', '--json']: const CliProcessResult(
            exitCode: 0,
            stdout:
                '{"currentVersion":"0.1.0","latestVersion":"0.1.0","updateAvailable":false,"error":null}\n',
            stderr: '',
            elapsed: Duration.zero,
          ),
        }),
        grokHomeProvider: () => root.path,
      );

      final detected = await repository.detect(
        providerConfig: AgentProviderConfig.defaultGrok.copyWith(
          extra: <String, Object?>{'cliPath': grokExe.path},
        ),
        enabled: true,
      );

      expect(detected.accountState, AgentAccountState.loggedOut);
    });

    test('reads and validates TOML configuration', () async {
      File(
        '${root.path}${Platform.pathSeparator}config.toml',
      ).writeAsStringSync('permission_mode = "default"\n');
      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        grokHomeProvider: () => root.path,
      );

      final document = await repository.readConfiguration();
      expect(document.exists, isTrue);
      expect(document.content, contains('permission_mode'));
      expect(repository.validateConfiguration('not = toml ['), isNotNull);
      expect(repository.validateConfiguration('a = 1\n'), isNull);
    });

    test('stores protocol arguments without launcher prefixes', () async {
      // Arrange
      final grokScript = File('${root.path}${Platform.pathSeparator}grok.cmd')
        ..writeAsStringSync('stub');
      final repository = GrokAgentManagementRepository(
        providerFactory: FakeAgentProviderFactory(
          FakeAgentProvider(config: AgentProviderConfig.defaultGrok),
        ),
        grokHomeProvider: () => root.path,
      );

      // Act
      final config = await repository.providerConfigForPath(
        current: AgentProviderConfig.defaultGrok,
        path: grokScript.path,
        timeoutSeconds: 60,
      );

      // Assert
      expect(config.command, grokScript.path);
      expect(config.arguments, const <String>['agent', 'stdio']);
      expect(config.extra['cliPath'], grokScript.path);
    });
  });
}

GrokCliProcessRun _scriptedRunner(
  Map<List<String>, CliProcessResult> responses,
) {
  return (
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    for (final entry in responses.entries) {
      if (_listEquals(entry.key, arguments)) {
        return entry.value;
      }
    }
    return CliProcessResult(
      exitCode: 1,
      stdout: '',
      stderr: 'unexpected args: $arguments',
      elapsed: Duration.zero,
    );
  };
}

bool _listEquals(List<String> a, List<String> b) {
  if (a.length != b.length) {
    return false;
  }
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) {
      return false;
    }
  }
  return true;
}

import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:codex_app_server_client/src/codex_cli_locator.dart';
import 'package:codex_app_server_client/src/datasources/app_server/codex_process_starter.dart';
import 'package:test/test.dart';

void main() {
  group('Codex process startup recovery', () {
    test('fails closed when no Codex executable can be resolved', () async {
      final locator = CodexCliLocator(
        environment: const <String, String>{'PATH': ''},
        isWindows: false,
        fileExists: (_) async => false,
      );

      await expectLater(
        resolveCodexProcessCommand(
          AgentProviderConfig.defaultCodex,
          locator: locator,
        ),
        throwsA(isA<ProcessException>()),
      );
    });

    test('normalizes empty and custom protocol arguments', () async {
      final locator = CodexCliLocator(
        environment: const <String, String>{'PATH': ''},
        isWindows: false,
        fileExists: (_) async => true,
      );

      final empty = await resolveCodexProcessCommand(
        AgentProviderConfig.defaultCodex.copyWith(
          command: '/tools/codex',
          arguments: const <String>[],
        ),
        locator: locator,
      );
      expect(empty.arguments, <String>['app-server']);

      final custom = await resolveCodexProcessCommand(
        AgentProviderConfig.defaultCodex.copyWith(
          command: '/tools/codex',
          arguments: const <String>['server', '--stdio'],
        ),
        locator: locator,
      );
      expect(custom.arguments, <String>['server', '--stdio']);
    });

    test(
      'wrapped starter forwards the resolved command to its delegate',
      () async {
        final locator = CodexCliLocator(
          environment: const <String, String>{'PATH': ''},
          isWindows: false,
          fileExists: (_) async => true,
        );
        late String executable;
        late List<String> arguments;
        late String? capturedWorkingDirectory;
        late Map<String, String>? capturedEnvironment;
        final starter = codexProcessStarter(
          AgentProviderConfig.defaultCodex.copyWith(command: '/tools/codex'),
          locator: locator,
          delegate:
              (
                resolvedExecutable,
                resolvedArguments, {
                workingDirectory,
                environment,
              }) {
                executable = resolvedExecutable;
                arguments = resolvedArguments;
                capturedWorkingDirectory = workingDirectory;
                capturedEnvironment = environment;
                return Process.start(Platform.resolvedExecutable, <String>[
                  '--version',
                ]);
              },
        );

        final process = await starter(
          'ignored',
          const <String>['ignored'],
          workingDirectory: Directory.current.path,
          environment: const <String, String>{'ZETA_TEST': '1'},
        );
        await process.exitCode;

        expect(executable, '/tools/codex');
        expect(arguments, <String>['app-server']);
        expect(capturedWorkingDirectory, Directory.current.path);
        expect(capturedEnvironment, const <String, String>{'ZETA_TEST': '1'});
      },
    );

    test('locates Codex from the Unix home fallback', () async {
      final locator = CodexCliLocator(
        environment: const <String, String>{
          'PATH': '',
          'HOME': '/home/tester',
        },
        isWindows: false,
        fileExists: (path) async => path == '/home/tester/.local/bin/codex',
      );

      final resolved = await locator.locate(AgentProviderConfig.defaultCodex);

      expect(resolved?.displayPath, '/home/tester/.local/bin/codex');
    });

    test('falls back to PATH when the persisted CLI path is stale', () async {
      final directory = await Directory.systemTemp.createTemp(
        'zeta-codex-locator-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final executable = await _createCodexExecutable(directory);
      final stalePath = _join(directory.path, 'removed-codex.ps1');
      final config = AgentProviderConfig.defaultCodex.copyWith(
        command: stalePath,
        extra: <String, Object?>{'cliPath': stalePath},
      );

      final resolved = await CodexCliLocator(
        environment: <String, String>{
          'PATH': directory.path,
          'APPDATA': directory.path,
          'LOCALAPPDATA': directory.path,
          if (Platform.environment['SystemRoot'] case final String value)
            'SystemRoot': value,
        },
      ).locate(config);

      expect(resolved?.displayPath, executable.path);
    });

    test(
      'replaces a stale PowerShell wrapper and removes its arguments',
      () async {
        if (!Platform.isWindows) {
          return;
        }
        final directory = await Directory.systemTemp.createTemp(
          'zeta-codex-wrapper-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final executable = await _createCodexExecutable(directory);
        final stalePath = _join(directory.path, 'removed-codex.ps1');
        final systemRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
        final powerShell = _join(
          _join(
            _join(_join(systemRoot, 'System32'), 'WindowsPowerShell'),
            'v1.0',
          ),
          'powershell.exe',
        );
        final config = AgentProviderConfig.defaultCodex.copyWith(
          command: powerShell,
          arguments: <String>[
            '-NoLogo',
            '-NoProfile',
            '-NonInteractive',
            '-File',
            stalePath,
            'app-server',
          ],
          extra: <String, Object?>{'cliPath': stalePath},
        );
        final locator = CodexCliLocator(
          environment: <String, String>{
            'PATH': directory.path,
            'APPDATA': directory.path,
            'LOCALAPPDATA': directory.path,
            'SystemRoot': systemRoot,
          },
        );

        final resolved = await resolveCodexProcessCommand(
          config,
          locator: locator,
        );

        expect(resolved.executable, executable.path);
        expect(resolved.arguments, <String>['app-server']);
        expect(resolved.arguments, isNot(contains(stalePath)));
      },
    );

    test('finds the Codex Desktop native executable', () async {
      if (!Platform.isWindows) {
        return;
      }
      final localAppData = await Directory.systemTemp.createTemp(
        'zeta-codex-desktop-',
      );
      addTearDown(() => localAppData.delete(recursive: true));
      final binDirectory = Directory(
        _join(
          _join(
            _join(
              _join(_join(localAppData.path, 'Programs'), 'OpenAI'),
              'Codex',
            ),
            'bin',
          ),
          '',
        ),
      );
      await binDirectory.create(recursive: true);
      final executable = File(_join(binDirectory.path, 'codex.exe'));
      await executable.writeAsBytes(const <int>[]);
      final stalePath = _join(localAppData.path, 'removed-codex.ps1');

      final resolved =
          await CodexCliLocator(
            environment: <String, String>{
              'PATH': '',
              'LOCALAPPDATA': localAppData.path,
              'APPDATA': localAppData.path,
            },
          ).locate(
            AgentProviderConfig.defaultCodex.copyWith(
              command: stalePath,
              extra: <String, Object?>{'cliPath': stalePath},
            ),
          );

      expect(resolved?.displayPath, executable.path);
    });

    test(
      'builds the default locator from config and platform environment',
      () async {
        final directory = await Directory.systemTemp.createTemp(
          'zeta-codex-default-locator-',
        );
        addTearDown(() => directory.delete(recursive: true));
        final executable = await _createCodexExecutable(directory);

        final resolved = await resolveCodexProcessCommand(
          AgentProviderConfig.defaultCodex.copyWith(
            command: executable.path,
            environment: const <String, String>{'ZETA_TEST': 'true'},
          ),
        );

        expect(resolved.executable, executable.path);
        expect(resolved.arguments, <String>['app-server']);
      },
    );
  });
}

Future<File> _createCodexExecutable(Directory directory) async {
  final name = Platform.isWindows ? 'codex.exe' : 'codex';
  final file = File(_join(directory.path, name));
  await file.writeAsBytes(const <int>[]);
  return file;
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

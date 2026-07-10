import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_process_starter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('Codex process startup recovery', () {
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

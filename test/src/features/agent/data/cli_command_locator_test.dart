import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('CliCommandLocator Windows launchers', () {
    test('skips extensionless shim and falls back to cmd sibling', () async {
      // Arrange
      const shim = r'D:\nodejs\claude';
      const cmd = r'D:\nodejs\claude.cmd';
      final inspectedPaths = <String>[];
      final locator = CliCommandLocator(
        executableName: 'claude',
        environment: const <String, String>{
          'PATH': r'D:\nodejs',
          'SystemRoot': r'C:\Windows',
        },
        isWindows: true,
        fileExists: (path) async {
          inspectedPaths.add(path);
          return path == shim || path == cmd;
        },
      );
      final config = AgentProviderConfig.defaultClaudeCode.copyWith(
        command: shim,
        extra: const <String, Object?>{'cliPath': shim},
      );

      // Act
      final resolved = await locator.locate(config);

      // Assert
      expect(resolved?.displayPath, cmd);
      expect(resolved?.executable, r'C:\Windows\System32\cmd.exe');
      expect(resolved?.prefixArguments, <String>[
        '/d',
        '/s',
        '/c',
        'call',
        cmd,
      ]);
      expect(inspectedPaths, isNot(contains(shim)));
    });

    test('runs exe directly without a shell prefix', () async {
      // Arrange
      const executable = r'C:\Tools\claude.exe';
      final locator = CliCommandLocator(
        executableName: 'claude',
        environment: const <String, String>{'SystemRoot': r'C:\Windows'},
        isWindows: true,
        fileExists: (path) async => path == executable,
      );

      // Act
      final resolved = await locator.resolvePath(executable);

      // Assert
      expect(resolved?.executable, executable);
      expect(resolved?.prefixArguments, isEmpty);
    });

    test('wraps PowerShell scripts non-interactively', () async {
      // Arrange
      const script = r'C:\Tools\claude.ps1';
      final locator = CliCommandLocator(
        executableName: 'claude',
        environment: const <String, String>{'SystemRoot': r'C:\Windows'},
        isWindows: true,
        fileExists: (path) async => path == script,
      );

      // Act
      final resolved = await locator.resolvePath(script);

      // Assert
      expect(
        resolved?.executable,
        r'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe',
      );
      expect(resolved?.prefixArguments, <String>[
        '-NoLogo',
        '-NoProfile',
        '-NonInteractive',
        '-File',
        script,
      ]);
    });

    test('resolved cmd command can start a batch file with spaces', () async {
      if (!Platform.isWindows) {
        return;
      }

      // Arrange
      final directory = await Directory.systemTemp.createTemp(
        'zeta cli locator-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final script = File(
        '${directory.path}${Platform.pathSeparator}claude.cmd',
      );
      await script.writeAsString('@ECHO off\r\nECHO received:%*\r\n');
      final locator = CliCommandLocator(
        executableName: 'claude',
        environment: <String, String>{
          if (Platform.environment['SystemRoot'] case final String value)
            'SystemRoot': value,
        },
        isWindows: true,
      );

      // Act
      final resolved = await locator.resolvePath(script.path);
      final result = await Process.run(
        resolved!.executable,
        resolved.argumentsFor(const <String>['--version']),
      );

      // Assert
      expect(result.exitCode, 0);
      expect(result.stdout, contains('received:--version'));
    });
  });

  test('Unix accepts the extensionless executable', () async {
    // Arrange
    const executable = '/usr/local/bin/claude';
    final locator = CliCommandLocator(
      executableName: 'claude',
      environment: const <String, String>{'PATH': '/usr/local/bin'},
      isWindows: false,
      fileExists: (path) async => path == executable,
    );

    // Act
    final resolved = await locator.locate(
      AgentProviderConfig.defaultClaudeCode,
    );

    // Assert
    expect(resolved?.executable, executable);
    expect(resolved?.prefixArguments, isEmpty);
  });
}

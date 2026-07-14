import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/data/cli_process_runner.dart';
import 'package:zeta/src/features/agent_management/data/cursor_agent_management_repository.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';

void main() {
  group('CursorAgentManagementRepository', () {
    late Directory tempDirectory;
    late File executable;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp(
        'zeta-cursor-management-',
      );
      executable = File(
        '${tempDirectory.path}${Platform.pathSeparator}'
        '${Platform.isWindows ? 'cursor-agent.exe' : 'cursor-agent'}',
      );
      await executable.writeAsString('cursor');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('detects identity, account and no-cost ACP handshake', () async {
      // Arrange
      var handshakeCount = 0;
      final repository = CursorAgentManagementRepository(
        locator: CursorCliLocator(
          identityProbe: (_) async => const CursorCliIdentity(
            productName: 'Cursor Agent',
            version: '1.4.0',
          ),
        ),
        processRunner: _runnerWithOutput('Authenticated as user@example.com'),
        handshakeProbe: (_, _) async {
          handshakeCount += 1;
        },
        cursorHomeProvider: () => tempDirectory.path,
      );
      final config = AgentProviderConfig.defaultCursor.copyWith(
        command: executable.path,
        extra: <String, Object?>{'cliPath': executable.path},
      );

      // Act
      final detected = await repository.detect(
        providerConfig: config,
        enabled: false,
      );

      // Assert
      expect(detected.definition.id, cursorAgentProviderId);
      expect(detected.installationState, AgentInstallationState.installed);
      expect(detected.currentVersion, '1.4.0');
      expect(detected.accountState, AgentAccountState.loggedIn);
      expect(detected.connectionTest?.success, isTrue);
      expect(detected.runtimeState, AgentRuntimeState.disabled);
      expect(handshakeCount, 1);
    });

    test(
      'reports logged-out account without exposing raw token text',
      () async {
        // Arrange
        final repository = CursorAgentManagementRepository(
          locator: CursorCliLocator(
            identityProbe: (_) async => const CursorCliIdentity(
              productName: 'Cursor Agent',
              version: '1.4.0',
            ),
          ),
          processRunner: _runnerWithOutput(
            'Not authenticated token=super-secret-token',
            exitCode: 1,
          ),
          handshakeProbe: (_, _) async {
            throw StateError('authentication required');
          },
          cursorHomeProvider: () => tempDirectory.path,
        );
        final config = AgentProviderConfig.defaultCursor.copyWith(
          command: executable.path,
          extra: <String, Object?>{'cliPath': executable.path},
        );

        // Act
        final detected = await repository.detect(
          providerConfig: config,
          enabled: false,
        );

        // Assert
        expect(detected.accountState, AgentAccountState.loggedOut);
        expect(detected.connectionTest?.success, isFalse);
        expect(detected.errorDetails, isNot(contains('super-secret-token')));
      },
    );

    test('persists only a verified Cursor executable path', () async {
      // Arrange
      final repository = CursorAgentManagementRepository(
        locator: CursorCliLocator(
          identityProbe: (_) async => const CursorCliIdentity(
            productName: 'Cursor Agent',
            version: '1.4.0',
          ),
        ),
        cursorHomeProvider: () => tempDirectory.path,
      );

      // Act
      final updated = await repository.providerConfigForPath(
        current: AgentProviderConfig.defaultCursor,
        path: executable.path,
        timeoutSeconds: 45,
      );

      // Assert
      expect(updated.kind, AgentProviderKind.cursorAcp);
      expect(updated.arguments, const <String>['acp']);
      expect(updated.extra['cliPath'], executable.path);
      expect(updated.extra['timeoutSeconds'], 45);
    });

    test('masks secrets in Cursor JSON configuration', () async {
      // Arrange
      final repository = CursorAgentManagementRepository(
        cursorHomeProvider: () => tempDirectory.path,
      );
      await File(
        repository.configPath,
      ).writeAsString('{"apiKey":"super-secret-value","mode":"ask"}');

      // Act
      final document = await repository.readConfiguration();

      // Assert
      expect(document.content, contains('super-secret-value'));
      expect(document.maskedContent, isNot(contains('super-secret-value')));
      expect(document.maskedContent, contains('••••••'));
    });
  });
}

CursorCliProcessRun _runnerWithOutput(String output, {int exitCode = 0}) {
  return (
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    Map<String, String>? environment,
  }) async {
    return CliProcessResult(
      exitCode: exitCode,
      stdout: output,
      stderr: '',
      elapsed: const Duration(milliseconds: 5),
    );
  };
}

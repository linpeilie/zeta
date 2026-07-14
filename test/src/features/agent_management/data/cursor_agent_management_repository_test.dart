import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_diagnostics_store.dart';
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

    test(
      'recursively masks nested JSON credentials and keeps normal values',
      () async {
        // Arrange
        final repository = CursorAgentManagementRepository(
          cursorHomeProvider: () => tempDirectory.path,
        );
        await File(repository.configPath).writeAsString('''
{
  "auth": {"access_token": "nested-secret", "CURSOR_API_KEY": "api-secret", "user": "alice"},
  "servers": [{"privateKey": "private-secret", "enabled": true}]
}
''');

        // Act
        final document = await repository.readConfiguration();

        // Assert
        expect(document.maskedContent, isNot(contains('nested-secret')));
        expect(document.maskedContent, isNot(contains('private-secret')));
        expect(document.maskedContent, isNot(contains('api-secret')));
        expect(document.maskedContent, contains('alice'));
        expect(document.maskedContent, contains('"enabled": true'));
      },
    );

    test(
      'detects external changes and preserves a backup on overwrite',
      () async {
        // Arrange
        final repository = CursorAgentManagementRepository(
          cursorHomeProvider: () => tempDirectory.path,
        );
        final file = File(repository.configPath);
        await file.writeAsString('{"mode":"ask"}');
        final original = await repository.readConfiguration();
        await file.writeAsString('{"mode":"agent"}');

        // Act / Assert
        await expectLater(
          repository.saveConfiguration(
            original: original,
            content: '{"mode":"plan"}',
          ),
          throwsA(isA<AgentConfigurationConflictException>()),
        );
        final saved = await repository.saveConfiguration(
          original: original,
          content: '{"mode":"plan"}',
          overwriteExternalChanges: true,
        );
        expect(await file.readAsString(), '{"mode":"plan"}');
        expect(saved.backupPath, isNotNull);
        expect(
          await File(saved.backupPath!).readAsString(),
          '{"mode":"agent"}',
        );
      },
    );

    test('exposes only bounded in-memory Cursor diagnostics as logs', () async {
      // Arrange
      final diagnostics = CursorDiagnosticsStore(maxRecords: 2);
      diagnostics.recordStderr('info ready');
      diagnostics.recordStderr('token=hidden-token warning');
      final repository = CursorAgentManagementRepository(
        cursorHomeProvider: () => tempDirectory.path,
        diagnosticsStore: diagnostics,
      );

      // Act
      final paths = await repository.discoverLogPaths();
      final logs = await repository.readLogs(paths, maxLines: 1);

      // Assert
      expect(paths, const <String>[CursorDiagnosticsStore.runtimeSource]);
      expect(logs, hasLength(1));
      expect(logs.single.message, isNot(contains('hidden-token')));
      expect(logs.single.sourcePath, contains('内存'));
    });

    test('warns when detected CLI version changed', () async {
      // Arrange
      final repository = CursorAgentManagementRepository(
        locator: CursorCliLocator(
          identityProbe: (_) async => const CursorCliIdentity(
            productName: 'Cursor Agent',
            version: '1.5.0',
          ),
        ),
        processRunner: _runnerWithOutput('Authenticated'),
        handshakeProbe: (_, _) async {},
        cursorHomeProvider: () => tempDirectory.path,
        diagnosticsStore: CursorDiagnosticsStore(),
      );
      final config = AgentProviderConfig.defaultCursor.copyWith(
        command: executable.path,
        extra: <String, Object?>{
          'cliPath': executable.path,
          'detectedCurrentVersion': '1.4.0',
        },
      );

      // Act
      final detected = await repository.detect(
        providerConfig: config,
        enabled: false,
      );

      // Assert
      expect(detected.suggestion, contains('版本变化'));
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

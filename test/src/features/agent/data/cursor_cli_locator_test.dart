import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_process_starter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CursorCliLocator', () {
    late Directory tempDirectory;

    setUp(() async {
      tempDirectory = await Directory.systemTemp.createTemp('zeta-cursor-cli-');
    });

    tearDown(() async {
      if (await tempDirectory.exists()) {
        await tempDirectory.delete(recursive: true);
      }
    });

    test('skips a conflicting agent command and continues probing', () async {
      // Arrange
      final conflictingAgent = File(
        '${tempDirectory.path}${Platform.pathSeparator}${_name('agent')}',
      );
      final cursorAgent = File(
        '${tempDirectory.path}${Platform.pathSeparator}${_name('cursor-agent')}',
      );
      await conflictingAgent.writeAsString('grok');
      await cursorAgent.writeAsString('cursor');
      final probed = <String>[];
      final locator = CursorCliLocator(
        environment: <String, String>{
          'PATH': tempDirectory.path,
          'HOME': tempDirectory.path,
          'USERPROFILE': tempDirectory.path,
        },
        identityProbe: (command) async {
          probed.add(command.displayPath);
          if (command.displayPath == cursorAgent.path) {
            return const CursorCliIdentity(
              productName: 'Cursor Agent',
              version: '1.2.3',
            );
          }
          return null;
        },
      );
      final config = AgentProviderConfig.defaultCursor.copyWith(
        extra: <String, Object?>{'cliPath': conflictingAgent.path},
      );

      // Act
      final resolved = await locator.locate(config);

      // Assert
      expect(resolved?.displayPath, cursorAgent.path);
      expect(resolved?.identity.version, '1.2.3');
      expect(probed.first, conflictingAgent.path);
      expect(probed, contains(cursorAgent.path));
    });

    test('rejects selected agent path when identity probe fails', () async {
      // Arrange
      final candidate = File(
        '${tempDirectory.path}${Platform.pathSeparator}${_name('agent')}',
      );
      await candidate.writeAsString('not cursor');
      final locator = CursorCliLocator(identityProbe: (_) async => null);

      // Act
      final resolved = await locator.resolvePath(candidate.path);

      // Assert
      expect(resolved, isNull);
    });

    test('normalizes protocol arguments to agent acp', () async {
      // Arrange
      final candidate = File(
        '${tempDirectory.path}${Platform.pathSeparator}${_name('cursor-agent')}',
      );
      await candidate.writeAsString('cursor');
      final locator = CursorCliLocator(
        identityProbe: (_) async => const CursorCliIdentity(
          productName: 'Cursor Agent',
          version: '2.0.0',
        ),
      );
      final config = AgentProviderConfig.defaultCursor.copyWith(
        command: candidate.path,
        extra: <String, Object?>{'cliPath': candidate.path},
      );

      // Act
      final command = await resolveCursorProcessCommand(
        config,
        locator: locator,
      );

      // Assert
      expect(command.arguments.last, 'acp');
      expect(command.arguments.where((value) => value == 'acp'), hasLength(1));
    });

    test(
      'wraps Windows cmd launchers without shell string interpolation',
      () async {
        // Arrange
        final candidate = File(
          '${tempDirectory.path}${Platform.pathSeparator}agent.cmd',
        );
        await candidate.writeAsString('@echo off');
        final locator = CursorCliLocator(
          identityProbe: (_) async =>
              const CursorCliIdentity(productName: 'Cursor Agent'),
        );

        // Act
        final resolved = await locator.resolvePath(candidate.path);

        // Assert
        expect(resolved?.executable, 'cmd.exe');
        expect(resolved?.argumentsFor(const <String>['acp']), <String>[
          '/d',
          '/s',
          '/c',
          candidate.path,
          'acp',
        ]);
      },
      skip: !Platform.isWindows,
    );
  });
}

String _name(String basename) =>
    Platform.isWindows ? '$basename.exe' : basename;

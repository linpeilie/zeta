import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/cursor_cli_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/acp/cursor_process_starter.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  test(
    'kills the full process tree for a Windows Cursor wrapper',
    () async {
      // Arrange
      final tempDirectory = await Directory.systemTemp.createTemp(
        'zeta-cursor-process-',
      );
      addTearDown(() => tempDirectory.delete(recursive: true));
      final wrapper = File(
        '${tempDirectory.path}${Platform.pathSeparator}cursor-agent.cmd',
      );
      await wrapper.writeAsString('@echo off');
      final locator = CursorCliLocator(
        identityProbe: (_) async =>
            const CursorCliIdentity(productName: 'Cursor Agent'),
      );
      final fakeProcess = _FakeProcess(pid: 42);
      int? killedProcessId;
      final starter = cursorProcessStarter(
        AgentProviderConfig.defaultCursor.copyWith(
          extra: <String, Object?>{'cliPath': wrapper.path},
        ),
        locator: locator,
        delegate:
            (
              _,
              _, {
              String? workingDirectory,
              Map<String, String>? environment,
            }) async => fakeProcess,
        windowsTreeKiller: (processId) async {
          killedProcessId = processId;
          fakeProcess.completeExit();
          return true;
        },
      );

      // Act
      final process = await starter('', const <String>[]);
      final accepted = process.kill();
      await process.exitCode;

      // Assert
      expect(accepted, isTrue);
      expect(killedProcessId, 42);
      expect(fakeProcess.directKillCount, 0);
    },
    skip: !Platform.isWindows,
  );
}

class _FakeProcess implements Process {
  _FakeProcess({required this.pid})
    : stdin = IOSink(_DiscardingStreamConsumer());

  final Completer<int> _exitCode = Completer<int>();
  int directKillCount = 0;

  @override
  final int pid;

  @override
  final IOSink stdin;

  @override
  Stream<List<int>> get stdout => const Stream<List<int>>.empty();

  @override
  Stream<List<int>> get stderr => const Stream<List<int>>.empty();

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    directKillCount += 1;
    completeExit();
    return true;
  }

  void completeExit() {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(0);
    }
  }
}

class _DiscardingStreamConsumer implements StreamConsumer<List<int>> {
  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    await stream.drain<void>();
  }

  @override
  Future<void> close() async {}
}

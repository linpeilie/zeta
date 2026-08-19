import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:claude_code_client/src/datasources/claude_code/stream_json_peer.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart' show ProcessStarter;
import 'package:test/test.dart';

void main() {
  group('StreamJsonPeer', () {
    test('joins half-lines across stdout chunks', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      addTearDown(peer.close);

      final events = <StreamJsonEvent>[];
      peer.events.listen(events.add);
      await peer.start();

      process
        ..writeRawStdoutBytes(utf8.encode('{"type":"sys'))
        ..writeRawStdoutBytes(utf8.encode('tem","subtype":"init"}\n'));
      await pumpEventQueue();

      expect(events, hasLength(1));
      expect(events.single.type, 'system');
      expect(events.single.subtype, 'init');
    });

    test('invalid JSON line does not break subsequent frames', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      addTearDown(peer.close);

      final events = <StreamJsonEvent>[];
      final errors = <StreamJsonProtocolException>[];
      peer.events.listen(events.add);
      peer.protocolErrors.listen(errors.add);
      await peer.start();

      process
        ..writeRawStdout('not-json')
        ..writeRawStdout(
          jsonEncode(<String, Object?>{
            'type': 'result',
            'subtype': 'success',
          }),
        );
      await pumpEventQueue();

      expect(errors, isNotEmpty);
      expect(errors.first.message, contains('Invalid JSON'));
      expect(events, hasLength(1));
      expect(events.single.type, 'result');
    });

    test('oversized line emits protocolErrors and continues', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
        maxLineBytes: 32,
      );
      addTearDown(peer.close);

      final events = <StreamJsonEvent>[];
      final errors = <StreamJsonProtocolException>[];
      peer.events.listen(events.add);
      peer.protocolErrors.listen(errors.add);
      await peer.start();

      process
        ..writeRawStdout('{"type":"x","pad":"${'a' * 80}"}')
        ..writeRawStdout(
          jsonEncode(<String, Object?>{'type': 'assistant'}),
        );
      await pumpEventQueue();

      expect(errors.any((e) => e.message.contains('exceeds max size')), isTrue);
      expect(events, hasLength(1));
      expect(events.single.type, 'assistant');
    });

    test('concurrent send is strictly FIFO', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      addTearDown(peer.close);
      await peer.start();

      final first = peer.send(<String, Object?>{'type': 'user', 'n': 1});
      final second = peer.send(<String, Object?>{'type': 'user', 'n': 2});
      final third = peer.send(<String, Object?>{'type': 'user', 'n': 3});
      await Future.wait(<Future<void>>[first, second, third]);
      await pumpEventQueue();

      expect(process.receivedMessages.map((m) => m['n']), <Object?>[1, 2, 3]);
    });

    test('send after close throws', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      await peer.start();
      await peer.close();

      expect(
        () => peer.send(<String, Object?>{'type': 'user'}),
        throwsA(isA<StreamJsonTransportClosedException>()),
      );
    });

    test('exceptions expose only sanitized diagnostics', () {
      const protocol = StreamJsonProtocolException(
        'invalid',
        payloadLength: 12,
        causeType: 'FormatException',
      );
      expect(
        protocol.toString(),
        'invalid payloadLength=12 causeType=FormatException',
      );
      expect(
        const StreamJsonProtocolException('invalid').toString(),
        'invalid',
      );
      expect(
        const StreamJsonTransportClosedException('closed').toString(),
        'closed',
      );
    });

    test('start is idempotent and shares an in-flight operation', () async {
      final process = _FakeStreamProcess();
      final release = Completer<void>();
      var starts = 0;
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter:
            (
              executable,
              arguments, {
              workingDirectory,
              environment,
            }) async {
              starts += 1;
              await release.future;
              process.start();
              return process;
            },
      );
      addTearDown(peer.close);

      final first = peer.start();
      final second = peer.start();
      release.complete();
      await Future.wait<void>(<Future<void>>[first, second]);
      await peer.start();

      expect(starts, 1);
    });

    test('passes working directory and a copied environment', () async {
      final process = _FakeStreamProcess();
      Map<String, String>? capturedEnvironment;
      final peer = StreamJsonPeer(
        command: 'claude',
        arguments: const <String>['--print'],
        workingDirectory: '/workspace',
        environment: const <String, String>{'SAFE': 'true'},
        processStarter:
            (
              executable,
              arguments, {
              workingDirectory,
              environment,
            }) async {
              expect(workingDirectory, '/workspace');
              capturedEnvironment = environment;
              process.start();
              return process;
            },
      );
      addTearDown(peer.close);

      await peer.start();

      expect(capturedEnvironment, <String, String>{'SAFE': 'true'});
      expect(capturedEnvironment, isNot(same(peer.environment)));
    });

    test('close while start is pending rejects the late process', () async {
      final process = _FakeStreamProcess();
      final processReady = Completer<Process>();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: (
          executable,
          arguments, {
          workingDirectory,
          environment,
        }) => processReady.future,
      );

      final start = peer.start();
      await peer.close();
      processReady.complete(process);

      await expectLater(
        start,
        throwsA(isA<StreamJsonTransportClosedException>()),
      );
      await peer.close();
      await expectLater(
        peer.start(),
        throwsA(isA<StreamJsonTransportClosedException>()),
      );
    });

    test(
      'maps stderr, malformed frames, trailing lines, and IO errors',
      () async {
        final process = _FakeStreamProcess();
        final peer = StreamJsonPeer(
          command: 'claude',
          processStarter: _starter(process),
          maxLineBytes: 32,
        );
        addTearDown(peer.close);
        final events = <StreamJsonEvent>[];
        final stderr = <String>[];
        final errors = <StreamJsonProtocolException>[];
        peer.events.listen(events.add);
        peer.stderrLines.listen(stderr.add);
        peer.protocolErrors.listen(errors.add);
        await peer.start();

        process
          ..writeRawStdout('[]')
          ..writeRawStdout('{}')
          ..writeRawStdout('{"type":"ok","subtype":3}')
          ..writeRawStdoutBytes(utf8.encode('{"type":"crlf"}\r\n'))
          ..writeRawStderr('   ')
          ..writeRawStderr('diagnostic')
          ..writeRawStderr('x' * 50)
          ..writeTrailingStdout('{"type":"tail"}\n${'z' * 50}')
          ..writeTrailingStderr('tail diagnostic\r')
          ..addStdoutError(StateError('stdout'))
          ..addStderrError(StateError('stderr'));
        await process.closeOutput();
        await pumpEventQueue();

        expect(events.map((event) => event.type), <String>[
          'ok',
          'crlf',
          'tail',
        ]);
        expect(events.first.subtype, isNull);
        expect(stderr, containsAll(<String>['diagnostic', 'tail diagnostic']));
        expect(
          errors.where((error) => error.message.contains('IO error')),
          hasLength(2),
        );
        expect(
          errors.any((error) => error.message.contains('not an object')),
          isTrue,
        );
        expect(
          errors.any((error) => error.message.contains('missing type')),
          isTrue,
        );
        expect(
          errors.any((error) => error.message.contains('stderr line')),
          isTrue,
        );
      },
    );

    test('spontaneous exit closes streams and prevents later sends', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      await peer.start();

      process.exit(7);
      await expectLater(peer.events, emitsDone);

      expect(
        () => peer.sendUserMessage(<String, Object?>{'type': 'user'}),
        throwsA(isA<StreamJsonTransportClosedException>()),
      );
      await peer.close();
    });

    test('write and close failures remain contained', () async {
      final process = _FakeStreamProcess(failWrites: true, failClose: true);
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      await peer.start();

      await expectLater(
        peer.sendControl(<String, Object?>{'type': 'control'}),
        throwsA(anything),
      );
      await peer.close();
    });

    test('close force-kills a process that does not exit', () async {
      final process = _FakeStreamProcess(completeOnKill: false);
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
        exitTimeout: const Duration(milliseconds: 1),
      );
      await peer.start();

      await peer.close();

      expect(process.killSignals, <ProcessSignal>[
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
    });

    test('parses a final stdout object without a newline', () async {
      final process = _FakeStreamProcess();
      final peer = StreamJsonPeer(
        command: 'claude',
        processStarter: _starter(process),
      );
      final events = <StreamJsonEvent>[];
      peer.events.listen(events.add);
      await peer.start();

      process.writeTrailingStdout('{"type":"tail-only"}');
      await process.closeOutput();
      await pumpEventQueue();

      expect(events.single.type, 'tail-only');
      await peer.close();
    });
  });
}

ProcessStarter _starter(_FakeStreamProcess process) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    process.start();
    return process;
  };
}

class _FakeStreamProcess implements Process {
  _FakeStreamProcess({
    this.failWrites = false,
    this.failClose = false,
    this.completeOnKill = true,
  });

  final bool failWrites;
  final bool failClose;
  final bool completeOnKill;
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final List<Map<String, Object?>> receivedMessages = <Map<String, Object?>>[];

  late final IOSink _stdin = IOSink(
    _FakeStdinConsumer(
      _stdinBytes,
      failWrites: failWrites,
      failClose: failClose,
    ),
  );

  void start() {
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleInputLine, onDone: () => _completeExit(0));
  }

  @override
  int get pid => 42;

  @override
  IOSink get stdin => _stdin;

  @override
  Stream<List<int>> get stdout => _stdoutBytes.stream;

  @override
  Stream<List<int>> get stderr => _stderrBytes.stream;

  @override
  Future<int> get exitCode => _exitCode.future;

  @override
  bool kill([ProcessSignal signal = ProcessSignal.sigterm]) {
    killSignals.add(signal);
    if (completeOnKill) {
      _completeExit(0);
    }
    return true;
  }

  void writeRawStdout(String line) {
    writeRawStdoutBytes(utf8.encode('$line\n'));
  }

  void writeRawStdoutBytes(List<int> bytes) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(bytes);
    }
  }

  void writeRawStderr(String line) {
    _stderrBytes.add(utf8.encode('$line\n'));
  }

  void writeTrailingStdout(String line) {
    _stdoutBytes.add(utf8.encode(line));
  }

  void writeTrailingStderr(String line) {
    _stderrBytes.add(utf8.encode(line));
  }

  void addStdoutError(Object error) => _stdoutBytes.addError(error);

  void addStderrError(Object error) => _stderrBytes.addError(error);

  Future<void> closeOutput() async {
    await _stdoutBytes.close();
    await _stderrBytes.close();
  }

  void exit(int code) => _completeExit(code);

  void _handleInputLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      receivedMessages.add(<String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
    }
  }

  void _completeExit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_closeController(_stdoutBytes));
    unawaited(_closeController(_stderrBytes));
    unawaited(_closeController(_stdinBytes));
  }
}

class _FakeStdinConsumer implements StreamConsumer<List<int>> {
  const _FakeStdinConsumer(
    this._controller, {
    required this.failWrites,
    required this.failClose,
  });

  final StreamController<List<int>> _controller;
  final bool failWrites;
  final bool failClose;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    if (failWrites) {
      return Future<void>.error(StateError('write failed'));
    }
    return stream.listen(_controller.add).asFuture<void>();
  }

  @override
  Future<void> close() async {
    if (failClose) {
      throw StateError('close failed');
    }
  }
}

Future<void> _closeController(StreamController<List<int>> controller) async {
  if (!controller.isClosed) {
    await controller.close();
  }
}

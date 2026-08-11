import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/stream_json_peer.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart'
    show ProcessStarter;

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

      process.writeRawStdoutBytes(utf8.encode('{"type":"sys'));
      process.writeRawStdoutBytes(utf8.encode('tem","subtype":"init"}\n'));
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

      process.writeRawStdout('not-json');
      process.writeRawStdout(
        jsonEncode(<String, Object?>{'type': 'result', 'subtype': 'success'}),
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

      process.writeRawStdout('{"type":"x","pad":"${'a' * 80}"}');
      process.writeRawStdout(
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
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final List<Map<String, Object?>> receivedMessages = <Map<String, Object?>>[];

  late final IOSink _stdin = IOSink(_FakeStdinConsumer(_stdinBytes));

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
    _completeExit(0);
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
  const _FakeStdinConsumer(this._controller);

  final StreamController<List<int>> _controller;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return stream.listen(_controller.add).asFuture<void>();
  }

  @override
  Future<void> close() async {}
}

Future<void> _closeController(StreamController<List<int>> controller) async {
  if (!controller.isClosed) {
    await controller.close();
  }
}

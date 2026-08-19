import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:json_rpc_transport/json_rpc_transport.dart';
import 'package:test/test.dart';
import 'package:zeta_logging/zeta_logging.dart';

void main() {
  group('transport values', () {
    test('encode errors and expose payload-free typed diagnostics', () {
      const error = JsonRpcError(code: 42, message: 'failed', data: 'details');
      expect(error.toJson(), <String, Object?>{
        'code': 42,
        'message': 'failed',
        'data': 'details',
      });
      expect(
        const JsonRpcError(code: 1, message: 'failed').toJson(),
        <String, Object?>{'code': 1, 'message': 'failed'},
      );
      expect(const JsonRpcException(error).logDiagnostic, <String, Object?>{
        'jsonRpcError': error.toJson(),
      });
      expect(const JsonRpcException(error).toString(), contains('42'));

      const malformed = TransportMalformedFrame(
        message: 'bad frame',
        payloadLength: 12,
        causeType: 'FormatException',
      );
      expect(malformed.toString(), 'bad frame');
      expect(malformed.payloadLength, 12);
      expect(malformed.causeType, 'FormatException');

      const tooLong = TransportLineTooLong(
        maximumLength: 10,
        observedLength: 11,
      );
      expect(tooLong.maximumLength, 10);
      expect(tooLong.observedLength, 11);
      expect(tooLong.message, contains('line limit'));

      final startedAt = DateTime.utc(2026);
      final timeout = TransportTimeout(
        method: 'ping',
        timeout: const Duration(seconds: 1),
        startedAt: startedAt,
      );
      expect(timeout.method, 'ping');
      expect(timeout.timeout, const Duration(seconds: 1));
      expect(timeout.startedAt, startedAt);

      const exited = TransportProcessExited(
        message: 'exited',
        exitCode: 7,
        causeType: 'StateError',
      );
      expect(exited.exitCode, 7);
      expect(exited.causeType, 'StateError');
      expect(
        const TransportClosed().toString(),
        'JSON-RPC transport is closed',
      );
    });

    test('messages freeze top-level maps and attach runtime scope', () {
      final params = <String, Object?>{'value': 1};
      final raw = <String, Object?>{'method': 'notice'};
      final notification = JsonRpcNotification(
        method: 'notice',
        params: params,
        raw: raw,
      );
      final request = JsonRpcRequest(
        id: 1,
        method: 'request',
        params: params,
        raw: raw,
      );
      params['value'] = 2;
      raw['method'] = 'changed';
      expect(notification.params['value'], 1);
      expect(request.raw['method'], 'notice');
      expect(() => notification.params['new'] = 1, throwsUnsupportedError);

      const scope = AgentRuntimeScope(runtimeId: 'runtime', connectionEpoch: 2);
      expect(notification.withRuntimeScope(scope).runtimeScope, scope);
      expect(request.withRuntimeScope(scope).runtimeScope, scope);
    });
  });

  group('JsonRpcStdioTransport', () {
    test('validates constructor bounds', () {
      expect(
        () => _transport(_FakeJsonRpcProcess(), maximumLineLength: 0),
        throwsArgumentError,
      );
      expect(
        () => _transport(
          _FakeJsonRpcProcess(),
          processExitTimeout: const Duration(microseconds: -1),
        ),
        throwsArgumentError,
      );
    });

    test('injects immutable process configuration and starts once', () async {
      final process = _FakeJsonRpcProcess();
      final arguments = <String>['serve'];
      final environment = <String, String>{'MODE': 'test'};
      var calls = 0;
      String? executable;
      List<String>? receivedArguments;
      Map<String, String>? receivedEnvironment;
      String? receivedDirectory;
      final transport = JsonRpcStdioTransport(
        command: 'fake-cli',
        arguments: arguments,
        environment: environment,
        workingDirectory: 'D:/repo',
        logger: loggerFor('transport.test'),
        processStarter:
            (
              command,
              args, {
              workingDirectory,
              environment,
            }) async {
              calls += 1;
              executable = command;
              receivedArguments = args;
              receivedDirectory = workingDirectory;
              receivedEnvironment = environment;
              return process..start();
            },
      );
      arguments.add('changed');
      environment['MODE'] = 'changed';

      await Future.wait<void>(<Future<void>>[
        transport.start(),
        transport.start(),
      ]);
      await transport.start();
      expect(calls, 1);
      expect(executable, 'fake-cli');
      expect(receivedArguments, <String>['serve']);
      expect(receivedDirectory, 'D:/repo');
      expect(receivedEnvironment, <String, String>{'MODE': 'test'});
      receivedEnvironment!['MODE'] = 'mutated';
      expect(transport.environment['MODE'], 'test');
      await transport.close();
    });

    test('wraps process start failure and rejects use after close', () async {
      final transport = JsonRpcStdioTransport(
        command: 'missing',
        processStarter: (
          _,
          _, {
          workingDirectory,
          environment,
        }) => Future<Process>.error(StateError('secret path')),
        logger: loggerFor('transport.test'),
      );
      await expectLater(
        transport.start(),
        throwsA(
          isA<TransportProcessExited>()
              .having((error) => error.exitCode, 'exitCode', isNull)
              .having((error) => error.causeType, 'causeType', 'StateError'),
        ),
      );
      await transport.close();
      await expectLater(transport.start(), throwsA(isA<TransportClosed>()));
      expect(
        () => transport.sendNotification('notice'),
        throwsA(isA<TransportClosed>()),
      );
    });

    test(
      'close waits for an in-progress start and cleans the process',
      () async {
        final process = _FakeJsonRpcProcess();
        final gate = Completer<void>();
        final transport = JsonRpcStdioTransport(
          command: 'fake',
          logger: loggerFor('transport.test'),
          processStarter:
              (
                _,
                _, {
                workingDirectory,
                environment,
              }) async {
                await gate.future;
                return process..start();
              },
        );
        final start = transport.start();
        final close = transport.close();
        gate.complete();
        await expectLater(start, throwsA(isA<TransportClosed>()));
        await close;
        expect(process.killSignals, isNotEmpty);
      },
    );

    test('handles partial frames, notifications, and responses', () async {
      final process = _FakeJsonRpcProcess(
        handler: (process, message) {
          if (message['method'] == 'ping') {
            process
              ..writeStdoutChunk('{"method":"notice",')
              ..writeStdoutChunk('"params":{"value":7}}\r\n')
              ..writeStdout(<String, Object?>{
                'id': message['id'],
                'result': <String, Object?>{'ok': true},
              });
          }
        },
      );
      final transport = _transport(process);
      await transport.start();
      final notification = transport.notifications.first;
      final result = await transport.sendRequest('ping');
      expect(result, <String, Object?>{'ok': true});
      expect((await notification).params['value'], 7);
      await transport.close();
    });

    test('flushes a final frame without a newline', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      await transport.start();
      final notification = transport.notifications.first;
      process
        ..writeStdoutChunk('{"method":"final","params":{}}')
        ..closeStdout();
      expect((await notification).method, 'final');
      await transport.close();
    });

    test('surfaces JSON-RPC errors with tolerant decoding', () async {
      var call = 0;
      final process = _FakeJsonRpcProcess(
        handler: (process, message) {
          call += 1;
          final error = switch (call) {
            1 => <String, Object?>{'code': -1, 'message': 'boom', 'data': 7},
            2 => <String, Object?>{'code': 'bad', 'message': 42},
            _ => 'bad',
          };
          process.writeStdout(<String, Object?>{
            'id': message['id'],
            'error': error,
          });
        },
      );
      final transport = _transport(process);
      await transport.start();

      await expectLater(
        transport.sendRequest('one'),
        throwsA(
          isA<JsonRpcException>().having(
            (exception) => exception.error.data,
            'data',
            7,
          ),
        ),
      );
      await expectLater(
        transport.sendRequest('two'),
        throwsA(
          isA<JsonRpcException>().having(
            (exception) => exception.error.code,
            'code',
            -32000,
          ),
        ),
      );
      await expectLater(
        transport.sendRequest('three'),
        throwsA(isA<JsonRpcException>()),
      );
      await transport.close();
    });

    test('handles server requests and both response shapes', () async {
      final input = <Map<String, Object?>>[];
      final process = _FakeJsonRpcProcess(
        handler: (process, message) => input.add(message),
      );
      final transport = _transport(process);
      await transport.start();
      final requestFuture = transport.serverRequests.first;
      process.writeStdout(<String, Object?>{
        'id': 'server-1',
        'method': 'approval',
        'params': 'invalid',
      });
      final request = await requestFuture;
      expect(request.params, isEmpty);
      await transport.sendResponse(
        request.id,
        result: <String, Object?>{'ok': true},
      );
      await transport.sendResponse(
        'server-2',
        error: const JsonRpcError(code: -1, message: 'denied'),
      );
      expect(input[0]['result'], <String, Object?>{'ok': true});
      expect(input[1]['error'], <String, Object?>{
        'code': -1,
        'message': 'denied',
      });
      await transport.close();
    });

    test('matches a stringified numeric id and reports unknown ids', () async {
      final errors = <TransportException>[];
      final process = _FakeJsonRpcProcess(
        handler: (process, message) {
          process
            ..writeStdout(<String, Object?>{'id': 'secret-id', 'result': null})
            ..writeStdout(<String, Object?>{
              'id': '${message['id']}',
              'result': 'pong',
            });
        },
      );
      final transport = _transport(process);
      final subscription = transport.protocolErrors.listen(errors.add);
      await transport.start();
      expect(await transport.sendRequest('ping'), 'pong');
      await _flushMicrotasks();
      expect(errors.single, isA<TransportMalformedFrame>());
      expect(errors.single.toString(), isNot(contains('secret-id')));
      await transport.close();
      await subscription.cancel();
    });

    test('reports malformed, non-object, and unknown message frames', () async {
      final errors = <TransportException>[];
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      final subscription = transport.protocolErrors.listen(errors.add);
      await transport.start();
      process
        ..writeStdoutRaw('private-broken-payload')
        ..writeStdoutRaw('[]')
        ..writeStdout(<String, Object?>{'unexpected': true})
        ..writeStdoutRaw('   ');
      await _flushMicrotasks();
      expect(errors, hasLength(3));
      expect(
        errors.first,
        isA<TransportMalformedFrame>()
            .having((error) => error.payloadLength, 'payloadLength', 22)
            .having((error) => error.causeType, 'causeType', 'FormatException'),
      );
      expect(errors.join('\n'), isNot(contains('private-broken-payload')));
      await transport.close();
      await subscription.cancel();
    });

    test('discards oversized stdout and stderr lines then recovers', () async {
      final errors = <TransportException>[];
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process, maximumLineLength: 16);
      final subscription = transport.protocolErrors.listen(errors.add);
      await transport.start();
      process
        ..writeStdoutRaw('12345678901234567890')
        ..writeStderr('abcdefghijklmnopqrst')
        ..writeStdout(<String, Object?>{'method': 'ok'});
      expect((await transport.notifications.first).method, 'ok');
      await _flushMicrotasks();
      expect(errors.whereType<TransportLineTooLong>(), hasLength(2));
      expect(
        errors.whereType<TransportLineTooLong>().first.observedLength,
        20,
      );
      await transport.close();
      await subscription.cancel();
    });

    test('keeps streams open after malformed UTF-8', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      await transport.start();
      final notification = transport.notifications.first;
      final stderr = transport.stderrLines.first;
      process
        ..writeStdoutBytes(<int>[
          ...utf8.encode('{"method":"notice","params":{"text":"'),
          0xd6,
          0xd0,
          ...utf8.encode('"}}\n'),
        ])
        ..writeStderrBytes(<int>[...utf8.encode('diagnostic: '), 0xd6, 0x0a]);
      expect((await notification).params['text'], contains('\ufffd'));
      expect(await stderr, contains('\ufffd'));
      await transport.close();
    });

    test('sanitizes stderr and ignores blank lines', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      final lines = <String>[];
      final subscription = transport.stderrLines.listen(lines.add);
      await transport.start();
      process
        ..writeStderr('   ')
        ..writeStderr('Authorization: Bearer top-secret');
      await _flushMicrotasks();
      expect(lines, hasLength(1));
      expect(lines.single, isNot(contains('top-secret')));
      await transport.close();
      await subscription.cancel();
    });

    test('uses the injected clock in typed timeout metadata', () async {
      final now = DateTime.utc(2026, 8, 19);
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process, clock: Clock.fixed(now));
      await transport.start();
      await expectLater(
        transport.sendRequest('slow', timeout: Duration.zero),
        throwsA(
          isA<TransportTimeout>()
              .having((error) => error.method, 'method', 'slow')
              .having((error) => error.startedAt, 'startedAt', now),
        ),
      );
      await expectLater(
        transport.sendRequest('invalid', timeout: const Duration(seconds: -1)),
        throwsArgumentError,
      );
      await transport.close();
    });

    test('close cancels pending requests and is idempotent', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      await transport.start();
      final pendingExpectation = expectLater(
        transport.sendRequest('pending'),
        throwsA(isA<TransportClosed>()),
      );
      await _flushMicrotasks();
      final firstClose = transport.close();
      final secondClose = transport.close();
      expect(identical(firstClose, secondClose), isTrue);
      await pendingExpectation;
      await firstClose;
      expect(process.killSignals, isNotEmpty);
    });

    test('process exit cancels pending work with its exit code', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      await transport.start();
      final pending = transport.sendRequest('pending');
      process.exit(17);
      await expectLater(
        pending,
        throwsA(
          isA<TransportProcessExited>().having(
            (error) => error.exitCode,
            'exitCode',
            17,
          ),
        ),
      );
      await expectLater(transport.notifications, emitsDone);
      await transport.close();
    });

    test('escalates child termination after the grace period', () async {
      final process = _FakeJsonRpcProcess(
        exitOnStdinClose: false,
        exitOnNormalKill: false,
      );
      final transport = _transport(process, processExitTimeout: Duration.zero);
      await transport.start();
      await transport.close();
      expect(process.killSignals, <ProcessSignal>[
        ProcessSignal.sigterm,
        ProcessSignal.sigkill,
      ]);
    });

    test('reports stream errors without exposing their messages', () async {
      final process = _FakeJsonRpcProcess();
      final transport = _transport(process);
      await transport.start();
      final error = transport.protocolErrors.first;
      process.addStdoutError(StateError('private stream detail'));
      expect(
        await error,
        isA<TransportMalformedFrame>().having(
          (failure) => failure.causeType,
          'causeType',
          'StateError',
        ),
      );
      await transport.close();
    });

    test('serializes notification writes before following requests', () async {
      var initialized = false;
      final process = _FakeJsonRpcProcess(
        handler: (process, message) {
          if (message['method'] == 'initialized') {
            initialized = true;
          } else if (message['method'] == 'request') {
            process.writeStdout(<String, Object?>{
              'id': message['id'],
              'result': initialized,
            });
          }
        },
      );
      final transport = _transport(process);
      await transport.start();
      transport.sendNotification('initialized');
      expect(await transport.sendRequest('request'), isTrue);
      await transport.close();
    });

    test(
      'wraps stdin failures and reports async notification failure',
      () async {
        final process = _FakeJsonRpcProcess(failWrites: true);
        final transport = _transport(process);
        await transport.start();
        await expectLater(
          transport.sendRequest('request'),
          throwsA(isA<TransportClosed>()),
        );
        final protocolError = transport.protocolErrors.first;
        transport.sendNotification('notice');
        expect(await protocolError, isA<TransportMalformedFrame>());
        await transport.close();
      },
    );
  });
}

JsonRpcStdioTransport _transport(
  _FakeJsonRpcProcess process, {
  int maximumLineLength = 1024 * 1024,
  Duration processExitTimeout = const Duration(seconds: 1),
  Clock clock = const Clock(),
}) {
  return JsonRpcStdioTransport(
    command: 'fake-json-rpc-server',
    maximumLineLength: maximumLineLength,
    processExitTimeout: processExitTimeout,
    clock: clock,
    logger: loggerFor('transport.test'),
    processStarter: (
      _,
      _, {
      workingDirectory,
      environment,
    }) async => process..start(),
  );
}

final class _FakeJsonRpcProcess implements Process {
  _FakeJsonRpcProcess({
    this.handler,
    this.failWrites = false,
    this.exitOnStdinClose = true,
    this.exitOnNormalKill = true,
  });

  final void Function(
    _FakeJsonRpcProcess process,
    Map<String, Object?> message,
  )?
  handler;
  final bool failWrites;
  final bool exitOnStdinClose;
  final bool exitOnNormalKill;
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();
  final List<ProcessSignal> killSignals = <ProcessSignal>[];
  bool _started = false;

  late final IOSink _stdin = IOSink(
    _FakeStdinConsumer(_stdinBytes, failWrites: failWrites),
  );

  void start() {
    if (_started) {
      return;
    }
    _started = true;
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(
          _handleInputLine,
          onDone: () {
            if (exitOnStdinClose) {
              exit(0);
            }
          },
        );
  }

  @override
  int get pid => 1;

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
    if (signal == ProcessSignal.sigkill || exitOnNormalKill) {
      exit(0);
    }
    return true;
  }

  void writeStdout(Map<String, Object?> message) {
    writeStdoutRaw(jsonEncode(message));
  }

  void writeStdoutRaw(String line) => writeStdoutChunk('$line\n');

  void writeStdoutChunk(String chunk) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(utf8.encode(chunk));
    }
  }

  void writeStdoutBytes(List<int> bytes) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(bytes);
    }
  }

  void writeStderr(String line) {
    writeStderrBytes(utf8.encode('$line\n'));
  }

  void writeStderrBytes(List<int> bytes) {
    if (!_stderrBytes.isClosed) {
      _stderrBytes.add(bytes);
    }
  }

  void addStdoutError(Object error) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.addError(error, StackTrace.current);
    }
  }

  void closeStdout() {
    unawaited(_closeController(_stdoutBytes));
  }

  void exit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
    }
    unawaited(_closeController(_stdoutBytes));
    unawaited(_closeController(_stderrBytes));
    unawaited(_closeController(_stdinBytes));
  }

  void _handleInputLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      handler?.call(this, <String, Object?>{
        for (final entry in decoded.entries)
          if (entry.key is String) entry.key as String: entry.value,
      });
    }
  }
}

final class _FakeStdinConsumer implements StreamConsumer<List<int>> {
  const _FakeStdinConsumer(this.controller, {required this.failWrites});

  final StreamController<List<int>> controller;
  final bool failWrites;

  @override
  Future<void> addStream(Stream<List<int>> stream) async {
    if (failWrites) {
      throw StateError('private write failure');
    }
    await for (final chunk in stream) {
      if (!controller.isClosed) {
        controller.add(chunk);
      }
    }
  }

  @override
  Future<void> close() => _closeController(controller);
}

Future<void> _closeController(StreamController<List<int>> controller) {
  if (controller.isClosed) {
    return Future<void>.value();
  }
  return controller.close();
}

Future<void> _flushMicrotasks() => Future<void>.delayed(Duration.zero);

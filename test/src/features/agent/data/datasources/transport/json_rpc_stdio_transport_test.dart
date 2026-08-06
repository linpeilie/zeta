import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:logger/logger.dart';
import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';

void main() {
  group('JsonRpcStdioTransport', () {
    final records = <LogEvent>[];
    late OutputCallback outputListener;

    setUp(() async {
      records.clear();
      await resetAppLoggingForTesting();
      outputListener = (event) => records.add(event.origin);
      Logger.addOutputListener(outputListener);
      Logger.level = Level.all;
      configureAppLogging();
    });

    tearDown(() async {
      Logger.removeOutputListener(outputListener);
      await resetAppLoggingForTesting();
    });

    test(
      'sends requests, matches responses, and receives notifications',
      () async {
        final transport = JsonRpcStdioTransport(
          command: 'fake-json-rpc-server',
          processStarter: _fakeProcessStarter((process, message) {
            if (message['method'] == 'ping') {
              process
                ..writeStdout(<String, Object?>{
                  'method': 'server/notice',
                  'params': <String, Object?>{'value': 7},
                })
                ..writeStdout(<String, Object?>{
                  'id': message['id'],
                  'result': <String, Object?>{'ok': true},
                });
            }
          }),
        );

        await transport.start();
        final notificationFuture = transport.notifications.first;
        final result = await transport.sendRequest('ping');

        expect(result, <String, Object?>{'ok': true});
        final notification = await notificationFuture;
        expect(notification.method, 'server/notice');
        expect(notification.params['value'], 7);
        await transport.close();
      },
    );

    test('surfaces JSON-RPC error responses', () async {
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          process.writeStdout(<String, Object?>{
            'id': message['id'],
            'error': <String, Object?>{'code': -32000, 'message': 'boom'},
          });
        }),
      );

      await transport.start();

      await expectLater(
        transport.sendRequest('fail'),
        throwsA(isA<JsonRpcException>()),
      );
      await transport.close();
    });

    test(
      'logs only metadata while keeping stderr available to providers',
      () async {
        const secretExecutable = r'C:\private\credentialed-cli.exe';
        final transport = JsonRpcStdioTransport(
          command: secretExecutable,
          processStarter: _fakeProcessStarter((process, message) {
            process
              ..writeStderr('stderr: ${message['method']}')
              ..writeStdout(<String, Object?>{
                'method': 'server/notice',
                'params': <String, Object?>{'echo': message['method']},
              })
              ..writeStdout(<String, Object?>{
                'id': message['id'],
                'result': <String, Object?>{'ok': true},
              });
          }),
        );

        await transport.start();
        final stderrFuture = transport.stderrLines.first;
        await transport.sendRequest('ping');
        expect(await stderrFuture, 'stderr: ping');
        await transport.close();

        final messages = records.map((record) => record.message).toList();
        expect(
          messages,
          anyElement(
            allOf(
              contains('Sending JSON-RPC request ping with id 1'),
              contains('characters'),
            ),
          ),
        );
        expect(messages, isNot(anyElement(contains('"method":"ping"'))));
        expect(
          messages,
          isNot(anyElement(contains('Received JSON-RPC notification'))),
        );
        expect(
          messages,
          anyElement(
            allOf(
              contains('Received JSON-RPC response idType=int'),
              contains('characters'),
            ),
          ),
        );
        expect(
          messages,
          contains('Received JSON-RPC stderr line (12 characters)'),
        );
        expect(messages, isNot(anyElement(contains('stderr: ping'))));
        expect(messages, isNot(anyElement(contains(secretExecutable))));
      },
    );

    test('does not log an unknown provider request id value', () async {
      const secretId = 'provider-secret-request-id';
      final errors = <JsonRpcProtocolException>[];
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          process
            ..writeStdout(<String, Object?>{'id': secretId, 'result': null})
            ..writeStdout(<String, Object?>{
              'id': message['id'],
              'result': null,
            });
        }),
      );
      final subscription = transport.protocolErrors.listen(errors.add);

      await transport.start();
      await transport.sendRequest('ping');
      await Future<void>.delayed(Duration.zero);
      expect(errors, hasLength(1));
      expect(errors.single.kind, JsonRpcProtocolErrorKind.unexpectedResponse);
      await transport.close();
      await subscription.cancel();

      final messages = records.map((record) => record.message).join('\n');
      expect(messages, contains('unknown request id (String)'));
      expect(messages, isNot(contains(secretId)));
    });

    test('matches a stringified numeric response id', () async {
      final errors = <JsonRpcProtocolException>[];
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          process.writeStdout(<String, Object?>{
            'id': '${message['id']}',
            'result': 'pong',
          });
        }),
      );
      final subscription = transport.protocolErrors.listen(errors.add);

      await transport.start();
      final result = await transport.sendRequest(
        'ping',
        timeout: const Duration(milliseconds: 100),
      );

      expect(result, 'pong');
      expect(errors, isEmpty);
      await transport.close();
      await subscription.cancel();
    });

    test('reports invalid stdout without closing the transport', () async {
      const malformedPayload = 'private-broken-payload';
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          process
            ..writeRawStdout(malformedPayload)
            ..writeStdout(<String, Object?>{
              'id': message['id'],
              'result': null,
            });
        }),
      );

      await transport.start();
      final errorFuture = transport.protocolErrors.first;
      await transport.sendRequest('ping');
      final error = await errorFuture;

      expect(error.message, contains('Invalid JSON'));
      expect(error.payloadLength, malformedPayload.length);
      expect(error.causeType, 'FormatException');
      expect(error.toString(), isNot(contains(malformedPayload)));
      final renderedLogs = records
          .map(
            (record) => <Object?>[
              record.message,
              record.error,
              record.stackTrace,
            ].whereType<Object>().join(' '),
          )
          .join('\n');
      expect(renderedLogs, isNot(contains(malformedPayload)));
      await transport.close();
    });

    test('keeps streams open after malformed UTF-8 output', () async {
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          process
            ..writeRawStdoutBytes(<int>[
              ...utf8.encode('{"method":"server/notice","params":{"text":"'),
              0xd6,
              0xd0,
              ...utf8.encode('"}}\n'),
            ])
            ..writeRawStderrBytes(<int>[
              ...utf8.encode('diagnostic: '),
              0xd6,
              0xd0,
              0x0a,
            ])
            ..writeStdout(<String, Object?>{
              'id': message['id'],
              'result': <String, Object?>{'ok': true},
            });
        }),
      );

      await transport.start();
      final notificationFuture = transport.notifications.first;
      final stderrFuture = transport.stderrLines.first;

      final result = await transport.sendRequest('ping');

      expect(result, <String, Object?>{'ok': true});
      expect((await notificationFuture).params['text'], contains('\ufffd'));
      expect(await stderrFuture, contains('\ufffd'));
      await transport.close();
    });

    test('handles server requests and client responses', () async {
      Object? pendingClientRequestId;
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          if (message['method'] == 'ask') {
            pendingClientRequestId = message['id'];
            process.writeStdout(<String, Object?>{
              'id': 'server-request-1',
              'method': 'client/approval',
              'params': <String, Object?>{'title': 'Approve?'},
            });
            return;
          }
          if (message['id'] == 'server-request-1') {
            process.writeStdout(<String, Object?>{
              'id': pendingClientRequestId,
              'result': <String, Object?>{'answered': true},
            });
          }
        }),
      );

      await transport.start();
      final serverRequestFuture = transport.serverRequests.first;
      final clientResponseFuture = transport.sendRequest('ask');
      final serverRequest = await serverRequestFuture;
      await transport.sendResponse(
        serverRequest.id,
        result: <String, Object?>{'approved': true},
      );

      expect(await clientResponseFuture, <String, Object?>{'answered': true});
      await transport.close();
      final messages = records.map((record) => record.message).join('\n');
      expect(
        messages,
        contains('server request client/approval idType=String'),
      );
      expect(messages, isNot(contains('server-request-1')));
    });

    test('serializes notifications before following requests', () async {
      var initialized = false;
      final transport = JsonRpcStdioTransport(
        command: 'fake-json-rpc-server',
        processStarter: _fakeProcessStarter((process, message) {
          if (message['method'] == 'initialized') {
            initialized = true;
            return;
          }
          if (message['method'] == 'thread/start') {
            process.writeStdout(<String, Object?>{
              'id': message['id'],
              'result': <String, Object?>{'sawInitialized': initialized},
            });
          }
        }),
      );

      await transport.start();
      transport.sendNotification('initialized');
      final result = await transport.sendRequest('thread/start');

      expect(result, <String, Object?>{'sawInitialized': true});
      await transport.close();
    });

    test(
      'waits for an in-progress start before reporting the transport open',
      () async {
        final transport = JsonRpcStdioTransport(
          command: 'fake-json-rpc-server',
          processStarter:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
                Map<String, String>? environment,
              }) async {
                await Future<void>.delayed(const Duration(milliseconds: 40));
                return _FakeJsonRpcProcess(_ignoreMessages)..start();
              },
        );

        final firstStart = transport.start();
        final secondStart = transport.start();

        await secondStart;
        expect(
          () => transport.sendNotification('initialized'),
          returnsNormally,
        );

        await firstStart;
        await transport.close();
      },
    );
  });
}

typedef _FakeMessageHandler =
    void Function(_FakeJsonRpcProcess process, Map<String, Object?> message);

ProcessStarter _fakeProcessStarter(_FakeMessageHandler handler) {
  return (
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    return _FakeJsonRpcProcess(handler)..start();
  };
}

void _ignoreMessages(
  _FakeJsonRpcProcess process,
  Map<String, Object?> message,
) {}

class _FakeJsonRpcProcess implements Process {
  _FakeJsonRpcProcess(this._handler);

  final _FakeMessageHandler _handler;
  final StreamController<List<int>> _stdinBytes = StreamController<List<int>>();
  final StreamController<List<int>> _stdoutBytes =
      StreamController<List<int>>();
  final StreamController<List<int>> _stderrBytes =
      StreamController<List<int>>();
  final Completer<int> _exitCode = Completer<int>();

  late final IOSink _stdin = IOSink(_FakeStdinConsumer(_stdinBytes));

  void start() {
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_handleInputLine, onDone: () => _completeExit(0));
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
    _completeExit(0);
    return true;
  }

  void writeStdout(Map<String, Object?> message) {
    writeRawStdout(jsonEncode(message));
  }

  void writeRawStdout(String line) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(utf8.encode('$line\n'));
    }
  }

  void writeRawStdoutBytes(List<int> bytes) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(bytes);
    }
  }

  void writeStderr(String line) {
    if (!_stderrBytes.isClosed) {
      _stderrBytes.add(utf8.encode('$line\n'));
    }
  }

  void writeRawStderrBytes(List<int> bytes) {
    if (!_stderrBytes.isClosed) {
      _stderrBytes.add(bytes);
    }
  }

  void _handleInputLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is Map) {
      _handler(this, <String, Object?>{
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
  Future<void> addStream(Stream<List<int>> stream) async {
    await for (final chunk in stream) {
      if (!_controller.isClosed) {
        _controller.add(chunk);
      }
    }
  }

  @override
  Future<void> close() {
    return _closeController(_controller);
  }
}

Future<void> _closeController(StreamController<List<int>> controller) {
  if (controller.isClosed) {
    return Future<void>.value();
  }
  return controller.close();
}

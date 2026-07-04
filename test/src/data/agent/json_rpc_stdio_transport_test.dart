import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/data/agent/json_rpc_stdio_transport.dart';

void main() {
  group('JsonRpcStdioTransport', () {
    late Directory tempDirectory;

    setUp(() {
      tempDirectory = Directory.systemTemp.createTempSync('zeta_rpc_test_');
    });

    tearDown(() {
      if (tempDirectory.existsSync()) {
        tempDirectory.deleteSync(recursive: true);
      }
    });

    test(
      'sends requests, matches responses, and receives notifications',
      () async {
        final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['method'] == 'ping') {
      stdout.writeln(jsonEncode({'method': 'server/notice', 'params': {'value': 7}}));
      stdout.writeln(jsonEncode({'id': message['id'], 'result': {'ok': true}}));
      stdout.flush();
    }
  });
}
''');
        final transport = JsonRpcStdioTransport(
          command: 'dart',
          arguments: <String>['run', script.path],
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
      final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    stdout.writeln(jsonEncode({
      'id': message['id'],
      'error': {'code': -32000, 'message': 'boom'}
    }));
    stdout.flush();
  });
}
''');
      final transport = JsonRpcStdioTransport(
        command: 'dart',
        arguments: <String>['run', script.path],
      );

      await transport.start();

      await expectLater(
        transport.sendRequest('fail'),
        throwsA(isA<JsonRpcException>()),
      );
      await transport.close();
    });

    test('reports invalid stdout without closing the transport', () async {
      final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    stdout.writeln('not-json');
    stdout.writeln(jsonEncode({'id': message['id'], 'result': null}));
    stdout.flush();
  });
}
''');
      final transport = JsonRpcStdioTransport(
        command: 'dart',
        arguments: <String>['run', script.path],
      );

      await transport.start();
      final errorFuture = transport.protocolErrors.first;
      await transport.sendRequest('ping');
      final error = await errorFuture;

      expect(error.message, contains('Invalid JSON'));
      await transport.close();
    });

    test('handles server requests and client responses', () async {
      final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

int? pendingClientRequestId;

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['method'] == 'ask') {
      pendingClientRequestId = message['id'] as int;
      stdout.writeln(jsonEncode({
        'id': 'server-request-1',
        'method': 'client/approval',
        'params': {'title': 'Approve?'}
      }));
      stdout.flush();
      return;
    }
    if (message['id'] == 'server-request-1') {
      stdout.writeln(jsonEncode({
        'id': pendingClientRequestId,
        'result': {'answered': true}
      }));
      stdout.flush();
    }
  });
}
''');
      final transport = JsonRpcStdioTransport(
        command: 'dart',
        arguments: <String>['run', script.path],
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
    });

    test('serializes notifications before following requests', () async {
      final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

bool initialized = false;

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    final message = jsonDecode(line) as Map<String, dynamic>;
    if (message['method'] == 'initialized') {
      initialized = true;
      return;
    }
    if (message['method'] == 'thread/start') {
      stdout.writeln(jsonEncode({
        'id': message['id'],
        'result': {'sawInitialized': initialized}
      }));
      stdout.flush();
    }
  });
}
''');
      final transport = JsonRpcStdioTransport(
        command: 'dart',
        arguments: <String>['run', script.path],
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
        final script = _writeServerScript(tempDirectory, '''
import 'dart:convert';
import 'dart:io';

void main() {
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((_) {});
}
''');
        final transport = JsonRpcStdioTransport(
          command: 'dart',
          arguments: <String>['run', script.path],
          processStarter:
              (
                String executable,
                List<String> arguments, {
                String? workingDirectory,
                Map<String, String>? environment,
              }) async {
                await Future<void>.delayed(const Duration(milliseconds: 40));
                return Process.start(
                  executable,
                  arguments,
                  workingDirectory: workingDirectory,
                  environment: environment,
                );
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

File _writeServerScript(Directory directory, String source) {
  return File('${directory.path}${Platform.pathSeparator}server.dart')
    ..writeAsStringSync(source);
}

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/claude_code_cli_locator.dart';
import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_cli_metadata_probe.dart';
import 'package:zeta/src/features/agent/data/datasources/claude_code/claude_code_process_starter.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

const _requestId = 'request-test';
const _fixtureRoot =
    'test/src/features/agent/data/datasources/claude_code/fixtures';

void main() {
  group('ClaudeCodeCliMetadataProbe', () {
    test(
      'sends only initialize and accepts only the matching success',
      () async {
        // Arrange
        final process = _FakeStreamProcess();
        process.onMessage = (message) {
          process.writeJson(_successResponse('request-other', model: 'wrong'));
          final response = _readFixture('initialize_2_1_228_redacted.json');
          final envelope = response['response'];
          if (envelope is Map) {
            envelope['request_id'] = _requestId;
          }
          process.writeJson(response);
        };
        final starter = _RecordingProcessStarter(process);
        final config = AgentProviderConfig.defaultClaudeCode.copyWith(
          arguments: const <String>['--model', 'must-not-leak'],
          environment: const <String, String>{
            'CLAUDE_CONFIG_DIR': '/fixture/config',
          },
          defaultModel: 'must-not-leak',
        );
        final probe = _probe(
          config: config,
          process: process,
          starter: starter,
        );

        // Act
        final result = await probe.probe();

        // Assert
        expect(result.models.models.map((model) => model.id), <String>[
          'sonnet',
          'claude-fable-5[1m]',
          'opus',
          'haiku',
        ]);
        expect(result.subscriptionType, 'Claude Pro');
        expect(starter.executable, '/fixture/claude');
        expect(starter.arguments, buildClaudeCodeMetadataProbeArguments());
        expect(starter.workingDirectory, '/fixture/workspace');
        expect(starter.environment, config.environment);
        expect(process.receivedMessages, hasLength(1));
        final sent = process.receivedMessages.single;
        expect(sent['type'], 'control_request');
        expect(sent['request_id'], _requestId);
        expect(_map(sent['request'])['subtype'], 'initialize');
        expect(jsonEncode(sent), isNot(contains('type":"user')));
        expect(jsonEncode(sent), isNot(contains('must-not-leak')));
        expect(process.stdinClosed, isTrue);
        expect(process.killCount, 1);
      },
    );

    test(
      'rejects a matching error response without reading its body',
      () async {
        final process = _FakeStreamProcess();
        process.onMessage = (_) {
          process.writeJson(<String, Object?>{
            'type': 'control_response',
            'response': <String, Object?>{
              'subtype': 'error',
              'request_id': _requestId,
              'error': 'sensitive body must not surface',
            },
          });
        };

        await expectLater(
          _probe(process: process).probe(),
          throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.errorResponse)),
        );
        expect(process.stdinClosed, isTrue);
      },
    );

    test('reports timeout and closes a silent process', () async {
      final process = _FakeStreamProcess();

      await expectLater(
        _probe(
          process: process,
          timeout: const Duration(milliseconds: 30),
        ).probe(),
        throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.timeout)),
      );
      expect(process.stdinClosed, isTrue);
      expect(process.killCount, 1);
    });

    test('reports an early process exit and completes cleanup', () async {
      final process = _FakeStreamProcess();
      process.onMessage = (_) => process.exit(1);

      await expectLater(
        _probe(process: process).probe(),
        throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.processExited)),
      );
      expect(process.exited, isTrue);
      expect(process.stdoutClosed, isTrue);
      expect(process.stderrClosed, isTrue);
      expect(process.killCount, 0);
    });

    test('rejects malformed stdout even if a valid response follows', () async {
      final process = _FakeStreamProcess();
      process.onMessage = (_) {
        process.writeRaw('not-json');
        process.writeJson(_successResponse(_requestId));
      };

      await expectLater(
        _probe(process: process).probe(),
        throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.invalidStream)),
      );
    });

    test('rejects an oversized stdout line and closes the peer', () async {
      final process = _FakeStreamProcess();
      process.onMessage = (_) {
        process.writeRaw(
          jsonEncode(<String, Object?>{'type': 'future', 'padding': 'x' * 256}),
        );
        process.writeJson(_successResponse(_requestId));
      };

      await expectLater(
        _probe(process: process, maxLineBytes: 64).probe(),
        throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.invalidStream)),
      );
      expect(process.stdinClosed, isTrue);
    });

    test('rejects a matching success without an object payload', () async {
      final process = _FakeStreamProcess();
      process.onMessage = (_) {
        process.writeJson(<String, Object?>{
          'type': 'control_response',
          'response': <String, Object?>{
            'subtype': 'success',
            'request_id': _requestId,
            'response': 'invalid',
          },
        });
      };

      await expectLater(
        _probe(process: process).probe(),
        throwsA(_failure(ClaudeCodeCliMetadataProbeFailure.invalidResponse)),
      );
    });
  });
}

ClaudeCodeCliMetadataProbe _probe({
  AgentProviderConfig config = AgentProviderConfig.defaultClaudeCode,
  required _FakeStreamProcess process,
  _RecordingProcessStarter? starter,
  Duration timeout = const Duration(seconds: 1),
  int maxLineBytes = 4 * 1024 * 1024,
}) {
  return ClaudeCodeCliMetadataProbe(
    config: config,
    timeout: timeout,
    workingDirectory: '/fixture/workspace',
    locator: const _StaticClaudeCodeCliLocator(),
    processStarter: (starter ?? _RecordingProcessStarter(process)).start,
    requestIdFactory: () => _requestId,
    maxLineBytes: maxLineBytes,
  );
}

Matcher _failure(ClaudeCodeCliMetadataProbeFailure failure) {
  return isA<ClaudeCodeCliMetadataProbeException>().having(
    (error) => error.failure,
    'failure',
    failure,
  );
}

Map<String, Object?> _successResponse(
  String requestId, {
  String model = 'default',
}) {
  return <String, Object?>{
    'type': 'control_response',
    'response': <String, Object?>{
      'subtype': 'success',
      'request_id': requestId,
      'response': <String, Object?>{
        'models': <Object?>[
          <String, Object?>{'value': model, 'displayName': model},
        ],
        'account': <String, Object?>{'subscriptionType': 'Claude Pro'},
      },
    },
  };
}

Map<String, Object?> _readFixture(String name) {
  return _map(jsonDecode(File('$_fixtureRoot/$name').readAsStringSync()));
}

Map<String, Object?> _map(Object? value) {
  if (value is! Map) {
    throw StateError('Expected a JSON object, got ${value.runtimeType}');
  }
  return value.map(
    (key, dynamic item) => MapEntry(key.toString(), item as Object?),
  );
}

class _StaticClaudeCodeCliLocator extends ClaudeCodeCliLocator {
  const _StaticClaudeCodeCliLocator();

  static const result = ResolvedCliCommand(
    displayPath: '/fixture/claude',
    executable: '/fixture/claude',
  );

  @override
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async =>
      result;
}

class _RecordingProcessStarter {
  _RecordingProcessStarter(this.process);

  final _FakeStreamProcess process;
  String? executable;
  List<String>? arguments;
  String? workingDirectory;
  Map<String, String>? environment;

  Future<Process> start(
    String executable,
    List<String> arguments, {
    String? workingDirectory,
    Map<String, String>? environment,
  }) async {
    this.executable = executable;
    this.arguments = List<String>.of(arguments);
    this.workingDirectory = workingDirectory;
    this.environment = environment == null
        ? null
        : Map<String, String>.of(environment);
    process.start();
    return process;
  }
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
  void Function(Map<String, Object?> message)? onMessage;
  bool stdinClosed = false;
  int killCount = 0;

  bool get exited => _exitCode.isCompleted;
  bool get stdoutClosed => _stdoutBytes.isClosed;
  bool get stderrClosed => _stderrBytes.isClosed;

  void start() {
    _stdinBytes.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final decoded = jsonDecode(line);
          if (decoded is Map) {
            final message = _map(decoded);
            receivedMessages.add(message);
            onMessage?.call(message);
          }
        }, onDone: () => stdinClosed = true);
  }

  void writeJson(Map<String, Object?> value) {
    writeRaw(jsonEncode(value));
  }

  void writeRaw(String value) {
    if (!_stdoutBytes.isClosed) {
      _stdoutBytes.add(utf8.encode('$value\n'));
    }
  }

  void exit(int code) {
    if (!_exitCode.isCompleted) {
      _exitCode.complete(code);
      unawaited(_closeController(_stdoutBytes));
      unawaited(_closeController(_stderrBytes));
    }
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
    killCount += 1;
    exit(0);
    return true;
  }
}

class _FakeStdinConsumer implements StreamConsumer<List<int>> {
  const _FakeStdinConsumer(this.controller);

  final StreamController<List<int>> controller;

  @override
  Future<void> addStream(Stream<List<int>> stream) {
    return stream.listen(controller.add).asFuture<void>();
  }

  @override
  Future<void> close() => controller.close();
}

Future<void> _closeController(StreamController<List<int>> controller) async {
  if (!controller.isClosed) {
    await controller.close();
  }
}

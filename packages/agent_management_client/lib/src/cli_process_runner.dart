// Public dependency name intentionally differs from the private field.
// ignore_for_file: prefer_initializing_formals

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Result of one bounded CLI process execution.
final class CliProcessResult {
  /// Creates a process result.
  const CliProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.elapsed,
  });

  /// Native process exit code.
  final int exitCode;

  /// Bounded decoded standard output.
  final String stdout;

  /// Bounded decoded standard error.
  final String stderr;

  /// Wall-clock execution duration.
  final Duration elapsed;

  /// Whether the process exited successfully.
  bool get succeeded => exitCode == 0;

  /// Non-empty stdout and stderr joined for non-sensitive parsing only.
  String get combinedOutput => <String>[
    if (stdout.trim().isNotEmpty) stdout.trim(),
    if (stderr.trim().isNotEmpty) stderr.trim(),
  ].join('\n');
}

/// Minimal closeable process surface used by [CliProcessRunner].
abstract interface class CliProcessHandle {
  /// Raw stdout byte stream.
  Stream<List<int>> get stdout;

  /// Raw stderr byte stream.
  Stream<List<int>> get stderr;

  /// Native process exit code.
  Future<int> get exitCode;

  /// Requests process termination.
  bool kill();
}

/// Starts a process using an already-resolved executable and argument list.
typedef CliProcessStarter = Future<CliProcessHandle> Function(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
});

/// Runs CLI commands with timeout, malformed UTF-8, and output caps contained.
final class CliProcessRunner {
  /// Creates a runner with an injectable process boundary.
  const CliProcessRunner({CliProcessStarter starter = _startIoProcess})
    : _starter = starter;

  final CliProcessStarter _starter;

  /// Executes [arguments] after the resolved command's launcher arguments.
  Future<CliProcessResult> run(
    ResolvedCliProcessCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputCharacters = 64 * 1024,
    Map<String, String>? environment,
  }) async {
    if (maxOutputCharacters < 0) {
      throw ArgumentError.value(
        maxOutputCharacters,
        'maxOutputCharacters',
        'must not be negative',
      );
    }
    final effective = command.processCommandFor(arguments);
    final stopwatch = Stopwatch()..start();
    final process = await _starter(
      effective.executable,
      effective.arguments,
      environment: environment,
    );
    final stdoutBuffer = _CappedTextBuffer(maxOutputCharacters);
    final stderrBuffer = _CappedTextBuffer(maxOutputCharacters);
    final stdoutDone = process.stdout
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stdoutBuffer.add);
    final stderrDone = process.stderr
        .transform(const Utf8Decoder(allowMalformed: true))
        .forEach(stderrBuffer.add);

    try {
      final exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('Agent command timed out', timeout);
        },
      );
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
      return CliProcessResult(
        exitCode: exitCode,
        stdout: stdoutBuffer.value,
        stderr: stderrBuffer.value,
        elapsed: stopwatch.elapsed,
      );
    } finally {
      stopwatch.stop();
    }
  }
}

final class _CappedTextBuffer {
  _CappedTextBuffer(this.maxCharacters);

  final int maxCharacters;
  final StringBuffer _buffer = StringBuffer();
  int _length = 0;

  void add(String value) {
    if (_length >= maxCharacters || value.isEmpty) {
      return;
    }
    final remaining = maxCharacters - _length;
    final chunk = value.length <= remaining
        ? value
        : value.substring(0, remaining);
    _buffer.write(chunk);
    _length += chunk.length;
  }

  String get value => _buffer.toString();
}

Future<CliProcessHandle> _startIoProcess(
  String executable,
  List<String> arguments, {
  Map<String, String>? environment,
}) async {
  final process = await Process.start(
    executable,
    arguments,
    environment: environment,
  );
  return _IoCliProcessHandle(process);
}

final class _IoCliProcessHandle implements CliProcessHandle {
  const _IoCliProcessHandle(this._process);

  final Process _process;

  @override
  Future<int> get exitCode => _process.exitCode;

  @override
  Stream<List<int>> get stderr => _process.stderr;

  @override
  Stream<List<int>> get stdout => _process.stdout;

  @override
  bool kill() => _process.kill();
}

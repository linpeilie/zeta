import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';

/// CLI 子进程执行结果。
class CliProcessResult {
  const CliProcessResult({
    required this.exitCode,
    required this.stdout,
    required this.stderr,
    required this.elapsed,
  });

  final int exitCode;
  final String stdout;
  final String stderr;
  final Duration elapsed;

  bool get succeeded => exitCode == 0;

  String get combinedOutput {
    final parts = <String>[
      if (stdout.trim().isNotEmpty) stdout.trim(),
      if (stderr.trim().isNotEmpty) stderr.trim(),
    ];
    return parts.join('\n');
  }
}

/// 使用参数数组执行 CLI，并在超时或输出过大时主动收敛资源。
class CliProcessRunner {
  const CliProcessRunner();

  Future<CliProcessResult> run(
    ResolvedCliCommand command,
    List<String> arguments, {
    Duration timeout = const Duration(seconds: 30),
    int maxOutputCharacters = 64 * 1024,
    Map<String, String>? environment,
  }) async {
    final stopwatch = Stopwatch()..start();
    final process = await Process.start(
      command.executable,
      command.argumentsFor(arguments),
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

    late final int exitCode;
    try {
      exitCode = await process.exitCode.timeout(
        timeout,
        onTimeout: () {
          process.kill();
          throw TimeoutException('CLI command timed out', timeout);
        },
      );
      await Future.wait(<Future<void>>[stdoutDone, stderrDone]);
    } finally {
      stopwatch.stop();
    }

    return CliProcessResult(
      exitCode: exitCode,
      stdout: stdoutBuffer.value,
      stderr: stderrBuffer.value,
      elapsed: stopwatch.elapsed,
    );
  }
}

class _CappedTextBuffer {
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

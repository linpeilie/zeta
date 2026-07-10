import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 可安全执行的 CLI 命令描述。
class ResolvedCliCommand {
  const ResolvedCliCommand({
    required this.displayPath,
    required this.executable,
    this.prefixArguments = const <String>[],
  });

  /// 用户看到的真实 CLI 文件路径。
  final String displayPath;

  /// 传给 [Process.start] 的启动器。
  final String executable;

  /// Windows 脚本包装器所需的固定参数。
  final List<String> prefixArguments;

  List<String> argumentsFor(List<String> arguments) {
    return <String>[...prefixArguments, ...arguments];
  }
}

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

/// 在已保存路径、PATH 与常见安装目录中定位 Codex CLI。
class CodexCliLocator {
  const CodexCliLocator();

  /// 校验用户选择的文件并转换为可执行启动器。
  Future<ResolvedCliCommand?> resolvePath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      return null;
    }
    return _resolveLauncher(path);
  }

  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
    final candidates = <String>[
      if (config.extra['cliPath'] case final String path) path,
      if (_looksLikePath(config.command)) config.command,
      ..._pathCandidates(),
      ..._commonCandidates(),
    ];
    final seen = <String>{};
    for (final raw in candidates) {
      final path = raw.trim();
      if (path.isEmpty) {
        continue;
      }
      final normalized = Platform.isWindows ? path.toLowerCase() : path;
      if (!seen.add(normalized)) {
        continue;
      }
      final type = await FileSystemEntity.type(path, followLinks: true);
      if (type == FileSystemEntityType.file) {
        return _resolveLauncher(path);
      }
    }
    return null;
  }

  Iterable<String> _pathCandidates() sync* {
    final rawPath = Platform.environment['PATH'] ?? '';
    if (rawPath.isEmpty) {
      return;
    }
    final names = Platform.isWindows
        ? const <String>['codex.exe', 'codex.ps1', 'codex.cmd', 'codex.bat']
        : const <String>['codex'];
    for (final directory in rawPath.split(Platform.isWindows ? ';' : ':')) {
      final trimmed = directory.trim().replaceAll('"', '');
      if (trimmed.isEmpty) {
        continue;
      }
      for (final name in names) {
        yield _join(trimmed, name);
      }
    }
  }

  Iterable<String> _commonCandidates() sync* {
    final home = _userHome;
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      final localAppData = Platform.environment['LOCALAPPDATA'];
      if (appData != null) {
        yield _join(_join(appData, 'npm'), 'codex.ps1');
        yield _join(_join(appData, 'npm'), 'codex.cmd');
      }
      if (localAppData != null) {
        yield _join(
          _join(_join(localAppData, 'Programs'), 'codex'),
          'codex.exe',
        );
      }
      if (home != null) {
        yield _join(_join(_join(home, '.local'), 'bin'), 'codex.exe');
      }
      return;
    }

    if (home != null) {
      yield _join(_join(_join(home, '.local'), 'bin'), 'codex');
      yield _join(_join(_join(home, '.npm-global'), 'bin'), 'codex');
    }
    yield '/usr/local/bin/codex';
    yield '/opt/homebrew/bin/codex';
    yield '/usr/bin/codex';
  }

  ResolvedCliCommand _resolveLauncher(String path) {
    if (!Platform.isWindows) {
      return ResolvedCliCommand(displayPath: path, executable: path);
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.ps1')) {
      final windowsRoot = Platform.environment['SystemRoot'] ?? r'C:\Windows';
      final powerShell = _join(
        _join(
          _join(_join(windowsRoot, 'System32'), 'WindowsPowerShell'),
          'v1.0',
        ),
        'powershell.exe',
      );
      return ResolvedCliCommand(
        displayPath: path,
        executable: powerShell,
        prefixArguments: <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-File',
          path,
        ],
      );
    }
    if (lower.endsWith('.cmd') || lower.endsWith('.bat')) {
      return ResolvedCliCommand(
        displayPath: path,
        executable: 'cmd.exe',
        prefixArguments: <String>['/d', '/s', '/c', path],
      );
    }
    return ResolvedCliCommand(displayPath: path, executable: path);
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

bool _looksLikePath(String value) {
  return value.contains('/') || value.contains('\\') || File(value).isAbsolute;
}

String? get _userHome {
  return Platform.environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

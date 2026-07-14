import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 已通过多信号探测确认的 Cursor CLI 身份。
class CursorCliIdentity {
  const CursorCliIdentity({required this.productName, this.version});

  final String productName;
  final String? version;
}

/// Cursor CLI 定位结果，同时携带已验证的产品身份。
class ResolvedCursorCliCommand {
  const ResolvedCursorCliCommand({
    required this.command,
    required this.identity,
  });

  final ResolvedCliCommand command;
  final CursorCliIdentity identity;

  String get displayPath => command.displayPath;
  String get executable => command.executable;

  List<String> argumentsFor(List<String> arguments) {
    return command.argumentsFor(arguments);
  }
}

/// 测试可替换的 Cursor CLI 身份探测器。
typedef CursorCliIdentityProbe =
    Future<CursorCliIdentity?> Function(ResolvedCliCommand command);

/// 定位 Cursor CLI，并防止把 Grok 等同名 `agent` 命令误当成 Cursor。
class CursorCliLocator {
  const CursorCliLocator({this.environment, this.identityProbe});

  final Map<String, String>? environment;
  final CursorCliIdentityProbe? identityProbe;

  Map<String, String> get _environment => environment ?? Platform.environment;

  /// 校验用户选择的文件；basename 仅用于筛选，最终仍必须通过身份探测。
  Future<ResolvedCursorCliCommand?> resolvePath(String path) async {
    if (!looksLikeCursorCliPath(path)) {
      return null;
    }
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      return null;
    }
    return _verify(_resolveLauncher(path));
  }

  /// 按已保存路径、PATH 与官方常见目录逐个探测，身份不符时继续尝试。
  Future<ResolvedCursorCliCommand?> locate(AgentProviderConfig config) async {
    final candidates = <String>[
      if (config.extra['cliPath'] case final String path) path,
      if (_launcherScriptPath(config) case final String path) path,
      if (_looksLikePath(config.command) &&
          !_isWindowsShellLauncher(config.command))
        config.command,
      ..._pathCandidates(),
      ..._commonCandidates(),
    ];
    final seen = <String>{};
    for (final raw in candidates) {
      final path = raw.trim();
      if (path.isEmpty || !looksLikeCursorCliPath(path)) {
        continue;
      }
      final normalized = Platform.isWindows ? path.toLowerCase() : path;
      if (!seen.add(normalized)) {
        continue;
      }
      final type = await FileSystemEntity.type(path, followLinks: true);
      if (type != FileSystemEntityType.file) {
        continue;
      }
      final verified = await _verify(_resolveLauncher(path));
      if (verified != null) {
        return verified;
      }
    }
    return null;
  }

  Future<ResolvedCursorCliCommand?> _verify(ResolvedCliCommand command) async {
    final identity = await (identityProbe ?? _probeCursorIdentity)(command);
    if (identity == null) {
      return null;
    }
    return ResolvedCursorCliCommand(command: command, identity: identity);
  }

  Iterable<String> _pathCandidates() sync* {
    final rawPath = _environment['PATH'] ?? '';
    if (rawPath.isEmpty) {
      return;
    }
    final names = Platform.isWindows
        ? const <String>[
            'cursor-agent.exe',
            'cursor-agent.cmd',
            'cursor-agent.bat',
            'cursor-agent.ps1',
            'agent.exe',
            'agent.cmd',
            'agent.bat',
            'agent.ps1',
          ]
        : const <String>['cursor-agent', 'agent'];
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
    final home = _environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Platform.isWindows) {
      if (home != null && home.isNotEmpty) {
        yield _join(_join(_join(home, '.local'), 'bin'), 'cursor-agent.exe');
        yield _join(_join(_join(home, '.local'), 'bin'), 'agent.exe');
      }
      final appData = _environment['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        yield _join(_join(appData, 'npm'), 'cursor-agent.cmd');
        yield _join(_join(appData, 'npm'), 'agent.cmd');
        yield _join(_join(appData, 'npm'), 'cursor-agent.ps1');
        yield _join(_join(appData, 'npm'), 'agent.ps1');
      }
      return;
    }
    if (home != null && home.isNotEmpty) {
      yield _join(_join(_join(home, '.local'), 'bin'), 'cursor-agent');
      yield _join(_join(_join(home, '.local'), 'bin'), 'agent');
    }
    yield '/usr/local/bin/cursor-agent';
    yield '/usr/local/bin/agent';
    yield '/opt/homebrew/bin/cursor-agent';
    yield '/opt/homebrew/bin/agent';
    yield '/usr/bin/cursor-agent';
    yield '/usr/bin/agent';
  }

  ResolvedCliCommand _resolveLauncher(String path) {
    if (!Platform.isWindows) {
      return ResolvedCliCommand(displayPath: path, executable: path);
    }
    final lower = path.toLowerCase();
    if (lower.endsWith('.ps1')) {
      final windowsRoot = _environment['SystemRoot'] ?? r'C:\Windows';
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

  String? _launcherScriptPath(AgentProviderConfig config) {
    if (!Platform.isWindows || !_isWindowsShellLauncher(config.command)) {
      return null;
    }
    final fileIndex = config.arguments.indexWhere(
      (argument) => argument.toLowerCase() == '-file',
    );
    if (fileIndex >= 0 && fileIndex + 1 < config.arguments.length) {
      return config.arguments[fileIndex + 1];
    }
    final commandIndex = config.arguments.indexWhere(
      (argument) => argument.toLowerCase() == '/c',
    );
    if (commandIndex >= 0 && commandIndex + 1 < config.arguments.length) {
      return config.arguments[commandIndex + 1];
    }
    return null;
  }
}

/// basename 只作为候选筛选；`agent` 必须再经过 [CursorCliLocator] 身份探测。
bool looksLikeCursorCliPath(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final basename = (slash >= 0 ? normalized.substring(slash + 1) : normalized)
      .toLowerCase();
  return basename == 'agent' ||
      basename.startsWith('agent.') ||
      basename == 'cursor-agent' ||
      basename.startsWith('cursor-agent.');
}

Future<CursorCliIdentity?> _probeCursorIdentity(
  ResolvedCliCommand command,
) async {
  try {
    final version = await _runProbe(command, const <String>['--version']);
    final about = await _runProbe(command, const <String>[
      'about',
      '--format',
      'json',
    ]);
    final acpHelp = await _runProbe(command, const <String>['help', 'acp']);
    final identityText =
        '${version.output}\n${about.output}\n${acpHelp.output}';
    final normalized = identityText.toLowerCase();
    final isCursor =
        normalized.contains('cursor') &&
        !RegExp(r'\bgrok\b', caseSensitive: false).hasMatch(identityText);
    final supportsAcp =
        acpHelp.exitCode == 0 && acpHelp.output.toLowerCase().contains('acp');
    if (!isCursor || !supportsAcp) {
      return null;
    }
    final versionMatch = RegExp(
      r'\b(\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?)\b',
    ).firstMatch(version.output);
    return CursorCliIdentity(
      productName: 'Cursor Agent',
      version: versionMatch?.group(1),
    );
  } catch (_) {
    return null;
  }
}

Future<_ProbeResult> _runProbe(
  ResolvedCliCommand command,
  List<String> arguments,
) async {
  final process = await Process.start(
    command.executable,
    command.argumentsFor(arguments),
  );
  final stdoutFuture = process.stdout
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final stderrFuture = process.stderr
      .transform(const Utf8Decoder(allowMalformed: true))
      .join();
  final exitCode = await process.exitCode.timeout(
    const Duration(seconds: 8),
    onTimeout: () {
      process.kill();
      throw TimeoutException('Cursor CLI identity probe timed out');
    },
  );
  final output = '${await stdoutFuture}\n${await stderrFuture}'.trim();
  return _ProbeResult(exitCode: exitCode, output: output);
}

class _ProbeResult {
  const _ProbeResult({required this.exitCode, required this.output});

  final int exitCode;
  final String output;
}

bool _looksLikePath(String value) {
  return value.contains('/') || value.contains('\\') || File(value).isAbsolute;
}

bool _isWindowsShellLauncher(String value) {
  if (!Platform.isWindows) {
    return false;
  }
  final normalized = value.replaceAll('/', '\\').toLowerCase();
  final name = normalized.substring(normalized.lastIndexOf('\\') + 1);
  return name == 'powershell.exe' || name == 'pwsh.exe' || name == 'cmd.exe';
}

String _join(String parent, String child) {
  if (parent.endsWith(Platform.pathSeparator)) {
    return '$parent$child';
  }
  return '$parent${Platform.pathSeparator}$child';
}

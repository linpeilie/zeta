import 'dart:io';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 可安全执行的 Codex CLI 命令描述。
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

/// 在已保存路径、PATH 与常见安装目录中定位 Codex CLI。
class CodexCliLocator {
  const CodexCliLocator({this.environment});

  /// 仅用于测试或宿主覆盖；默认使用当前进程环境。
  final Map<String, String>? environment;

  Map<String, String> get _environment => environment ?? Platform.environment;

  /// 校验用户选择的文件并转换为可执行启动器。
  Future<ResolvedCliCommand?> resolvePath(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      return null;
    }
    return _resolveLauncher(path);
  }

  /// 定位当前可用的 CLI，已保存路径失效时会继续自动探测。
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
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
    final rawPath = _environment['PATH'] ?? '';
    if (rawPath.isEmpty) {
      return;
    }
    // cmd/bat 会直接继承子进程管道，优先于可能重编码输出的 PowerShell。
    final names = Platform.isWindows
        ? const <String>['codex.exe', 'codex.cmd', 'codex.bat', 'codex.ps1']
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
    final home = _environment[Platform.isWindows ? 'USERPROFILE' : 'HOME'];
    if (Platform.isWindows) {
      final appData = _environment['APPDATA'];
      final localAppData = _environment['LOCALAPPDATA'];
      if (localAppData != null) {
        // Codex Desktop 安装的 CLI 优先使用原生 exe。
        yield _join(
          _join(
            _join(_join(_join(localAppData, 'Programs'), 'OpenAI'), 'Codex'),
            'bin',
          ),
          'codex.exe',
        );
        yield _join(
          _join(_join(localAppData, 'Programs'), 'codex'),
          'codex.exe',
        );
      }
      if (home != null) {
        yield _join(_join(_join(home, '.local'), 'bin'), 'codex.exe');
      }
      if (appData != null) {
        yield _join(_join(appData, 'npm'), 'codex.cmd');
        yield _join(_join(appData, 'npm'), 'codex.ps1');
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

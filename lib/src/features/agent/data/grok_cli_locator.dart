import 'dart:io';

import 'package:zeta/src/features/agent/data/codex_cli_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 在已保存路径、PATH 与常见安装目录中定位 Grok CLI。
class GrokCliLocator {
  const GrokCliLocator({this.environment});

  /// 仅用于测试或宿主覆盖；默认使用当前进程环境。
  final Map<String, String>? environment;

  Map<String, String> get _environment => environment ?? Platform.environment;

  /// 校验用户选择的文件并转换为可执行启动器。
  ///
  /// 仅接受文件名像 `grok` 的路径，避免误用 Codex 等其它 CLI。
  Future<ResolvedCliCommand?> resolvePath(String path) async {
    if (!looksLikeGrokCliPath(path)) {
      return null;
    }
    final type = await FileSystemEntity.type(path, followLinks: true);
    if (type != FileSystemEntityType.file) {
      return null;
    }
    return _resolveLauncher(path);
  }

  /// 定位当前可用的 CLI，已保存路径失效时会继续自动探测。
  ///
  /// 会跳过文件名不像 Grok 的候选（例如误写入的 Codex `cliPath`）。
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
      if (path.isEmpty || !looksLikeGrokCliPath(path)) {
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
    final names = Platform.isWindows
        ? const <String>['grok.exe', 'grok.cmd', 'grok.bat', 'grok.ps1']
        : const <String>['grok'];
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
    if (home == null) {
      return;
    }
    // 官方安装默认放在 ~/.grok/bin
    if (Platform.isWindows) {
      yield _join(_join(_join(home, '.grok'), 'bin'), 'grok.exe');
      yield _join(_join(_join(home, '.local'), 'bin'), 'grok.exe');
      final appData = _environment['APPDATA'];
      if (appData != null) {
        yield _join(_join(appData, 'npm'), 'grok.cmd');
        yield _join(_join(appData, 'npm'), 'grok.ps1');
      }
      return;
    }
    yield _join(_join(_join(home, '.grok'), 'bin'), 'grok');
    yield _join(_join(_join(home, '.local'), 'bin'), 'grok');
    yield _join(_join(_join(home, '.npm-global'), 'bin'), 'grok');
    yield '/usr/local/bin/grok';
    yield '/opt/homebrew/bin/grok';
    yield '/usr/bin/grok';
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

/// 路径 basename 是否像 Grok CLI（`grok` / `grok.exe` 等）。
bool looksLikeGrokCliPath(String path) {
  final name = _cliBasename(path);
  return name == 'grok' || name.startsWith('grok.');
}

String _cliBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final base = slash >= 0 ? normalized.substring(slash + 1) : normalized;
  return base.toLowerCase();
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

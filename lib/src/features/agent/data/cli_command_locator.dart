import 'dart:io';

import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// CLI 路径是否指向普通文件的可替换检查入口。
typedef CliFileExists = Future<bool> Function(String path);

/// 已解析且可安全交给 [Process.start] 的 CLI 启动器。
class ResolvedCliCommand {
  const ResolvedCliCommand({
    required this.displayPath,
    required this.executable,
    this.prefixArguments = const <String>[],
  });

  /// 用户看到的真实 CLI 文件路径。
  final String displayPath;

  /// 传给 [Process.start] 的原生可执行文件或系统 shell。
  final String executable;

  /// Windows 脚本包装器所需的固定参数。
  final List<String> prefixArguments;

  List<String> argumentsFor(List<String> arguments) {
    return <String>[...prefixArguments, ...arguments];
  }

  ResolvedCliProcessCommand processCommandFor(List<String> arguments) {
    return ResolvedCliProcessCommand(
      executable: executable,
      arguments: argumentsFor(arguments),
      displayPath: displayPath,
    );
  }
}

/// 最终传给 [Process.start] 的完整命令。
class ResolvedCliProcessCommand {
  const ResolvedCliProcessCommand({
    required this.executable,
    required this.arguments,
    required this.displayPath,
  });

  final String executable;
  final List<String> arguments;
  final String displayPath;
}

/// Provider 无关的 CLI 路径定位与 Windows 启动器解析。
///
/// Windows 只接受原生 `.exe` 与可显式包装的 `.cmd` / `.bat` / `.ps1`。
/// npm 同目录生成的无扩展名 POSIX shim 会被跳过，并继续尝试其 Windows
/// sibling，避免把 `#!/bin/sh` 文件直接传给 [Process.start]。
class CliCommandLocator {
  const CliCommandLocator({
    required this.executableName,
    this.environment,
    this.additionalCandidates = const <String>[],
    this.isWindows,
    this.fileExists,
  });

  final String executableName;
  final Map<String, String>? environment;
  final List<String> additionalCandidates;

  /// 测试可覆盖目标平台；生产默认使用当前平台。
  final bool? isWindows;

  /// 测试可替换文件系统检查。
  final CliFileExists? fileExists;

  bool get _isWindows => isWindows ?? Platform.isWindows;

  Map<String, String> get _environment => environment ?? Platform.environment;

  /// 校验用户给定路径并转换为可执行启动器。
  Future<ResolvedCliCommand?> resolvePath(String path) async {
    final trimmed = path.trim();
    if (!_isSupportedCandidate(trimmed) || !await _exists(trimmed)) {
      return null;
    }
    return _resolveLauncher(trimmed);
  }

  /// 按已保存路径、PATH 和 Provider 补充目录定位当前可用 CLI。
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) async {
    final configuredPath = config.extra['cliPath'];
    final configuredCommand = config.command.trim();
    final candidates = <String>[
      if (configuredPath is String)
        ..._configuredPathCandidates(configuredPath),
      if (_launcherScriptPath(config) case final String path)
        ..._configuredPathCandidates(path),
      if (_looksLikePath(configuredCommand) &&
          !_isWindowsShellLauncher(configuredCommand))
        ..._configuredPathCandidates(configuredCommand),
      ..._pathCandidates(),
      ...additionalCandidates,
    ];
    final seen = <String>{};
    for (final raw in candidates) {
      final path = raw.trim();
      if (!_isSupportedCandidate(path)) {
        continue;
      }
      final normalized = _isWindows ? path.toLowerCase() : path;
      if (!seen.add(normalized) || !await _exists(path)) {
        continue;
      }
      return _resolveLauncher(path);
    }
    return null;
  }

  Iterable<String> _configuredPathCandidates(String rawPath) sync* {
    final path = rawPath.trim();
    if (path.isEmpty) {
      return;
    }
    yield path;
    if (!_isWindows || !_looksLikePath(path)) {
      return;
    }

    final lower = path.toLowerCase();
    var basePath = path;
    for (final extension in const <String>['.exe', '.cmd', '.bat', '.ps1']) {
      if (lower.endsWith(extension)) {
        basePath = path.substring(0, path.length - extension.length);
        break;
      }
    }
    if (_cliBasename(basePath) != executableName.toLowerCase()) {
      return;
    }
    for (final extension in const <String>['.exe', '.cmd', '.bat', '.ps1']) {
      final sibling = '$basePath$extension';
      if (sibling.toLowerCase() != lower) {
        yield sibling;
      }
    }
  }

  Iterable<String> _pathCandidates() sync* {
    final rawPath = _environment['PATH'] ?? '';
    if (rawPath.isEmpty) {
      return;
    }
    final names = _isWindows
        ? <String>[
            '$executableName.exe',
            '$executableName.cmd',
            '$executableName.bat',
            '$executableName.ps1',
          ]
        : <String>[executableName];
    for (final directory in rawPath.split(_isWindows ? ';' : ':')) {
      final trimmed = directory.trim().replaceAll('"', '');
      if (trimmed.isEmpty) {
        continue;
      }
      for (final name in names) {
        yield joinCliPath(trimmed, name, isWindows: _isWindows);
      }
    }
  }

  bool _isSupportedCandidate(String path) {
    if (path.isEmpty || !looksLikeCliPath(path, executableName)) {
      return false;
    }
    if (!_isWindows) {
      return true;
    }
    final base = _cliBasename(path);
    final name = executableName.toLowerCase();
    return base == '$name.exe' ||
        base == '$name.cmd' ||
        base == '$name.bat' ||
        base == '$name.ps1';
  }

  Future<bool> _exists(String path) async {
    final override = fileExists;
    if (override != null) {
      return override(path);
    }
    return await FileSystemEntity.type(path, followLinks: true) ==
        FileSystemEntityType.file;
  }

  ResolvedCliCommand _resolveLauncher(String path) {
    if (!_isWindows) {
      return ResolvedCliCommand(displayPath: path, executable: path);
    }
    final lower = path.toLowerCase();
    final windowsRoot = _environment['SystemRoot'] ?? r'C:\Windows';
    if (lower.endsWith('.ps1')) {
      final powerShell = joinCliPath(
        joinCliPath(
          joinCliPath(
            joinCliPath(windowsRoot, 'System32', isWindows: true),
            'WindowsPowerShell',
            isWindows: true,
          ),
          'v1.0',
          isWindows: true,
        ),
        'powershell.exe',
        isWindows: true,
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
      final commandPrompt = joinCliPath(
        joinCliPath(windowsRoot, 'System32', isWindows: true),
        'cmd.exe',
        isWindows: true,
      );
      // `call` 让 cmd 正确执行带空格的 batch 路径，并把后续协议参数继续转交。
      return ResolvedCliCommand(
        displayPath: path,
        executable: commandPrompt,
        prefixArguments: <String>['/d', '/s', '/c', 'call', path],
      );
    }
    return ResolvedCliCommand(displayPath: path, executable: path);
  }

  String? _launcherScriptPath(AgentProviderConfig config) {
    if (!_isWindows || !_isWindowsShellLauncher(config.command)) {
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

  bool _looksLikePath(String value) {
    return value.contains('/') ||
        value.contains('\\') ||
        RegExp(r'^[A-Za-z]:').hasMatch(value);
  }

  bool _isWindowsShellLauncher(String value) {
    if (!_isWindows) {
      return false;
    }
    final name = _cliBasename(value);
    return name == 'powershell.exe' || name == 'pwsh.exe' || name == 'cmd.exe';
  }
}

/// Provider 通用的用户级与系统级 CLI 安装候选。
List<String> standardCliInstallCandidates({
  required String executableName,
  required Map<String, String> environment,
  required bool isWindows,
}) {
  final candidates = <String>[];
  final home = environment[isWindows ? 'USERPROFILE' : 'HOME'];
  if (isWindows) {
    if (home != null && home.isNotEmpty) {
      candidates.add(
        joinCliPath(
          joinCliPath(
            joinCliPath(home, '.local', isWindows: true),
            'bin',
            isWindows: true,
          ),
          '$executableName.exe',
          isWindows: true,
        ),
      );
    }
    final appData = environment['APPDATA'];
    if (appData != null && appData.isNotEmpty) {
      final npmDirectory = joinCliPath(appData, 'npm', isWindows: true);
      candidates
        ..add(joinCliPath(npmDirectory, '$executableName.cmd', isWindows: true))
        ..add(
          joinCliPath(npmDirectory, '$executableName.ps1', isWindows: true),
        );
    }
    return List<String>.unmodifiable(candidates);
  }

  if (home != null && home.isNotEmpty) {
    candidates
      ..add(
        joinCliPath(
          joinCliPath(
            joinCliPath(home, '.local', isWindows: false),
            'bin',
            isWindows: false,
          ),
          executableName,
          isWindows: false,
        ),
      )
      ..add(
        joinCliPath(
          joinCliPath(
            joinCliPath(home, '.npm-global', isWindows: false),
            'bin',
            isWindows: false,
          ),
          executableName,
          isWindows: false,
        ),
      );
  }
  candidates
    ..add('/usr/local/bin/$executableName')
    ..add('/opt/homebrew/bin/$executableName')
    ..add('/usr/bin/$executableName');
  return List<String>.unmodifiable(candidates);
}

/// basename 是否属于指定 CLI；平台过滤由 [CliCommandLocator] 负责。
bool looksLikeCliPath(String path, String executableName) {
  final base = _cliBasename(path);
  final name = executableName.toLowerCase();
  return base == name || base.startsWith('$name.');
}

/// 使用目标平台分隔符拼接 CLI 探测路径。
String joinCliPath(String parent, String child, {required bool isWindows}) {
  if (parent.isEmpty) {
    return child;
  }
  if (parent.endsWith('/') || parent.endsWith('\\')) {
    return '$parent$child';
  }
  return '$parent${isWindows ? '\\' : '/'}$child';
}

String _cliBasename(String path) {
  final normalized = path.replaceAll('\\', '/');
  final slash = normalized.lastIndexOf('/');
  final base = slash >= 0 ? normalized.substring(slash + 1) : normalized;
  return base.toLowerCase();
}

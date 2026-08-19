import 'dart:io';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Replaceable check for a regular CLI file.
typedef ClaudeCodeCliFileExists = Future<bool> Function(String path);

/// Locates Claude Code from persisted configuration, PATH, and known install
/// roots.
class ClaudeCodeCliLocator {
  /// Creates a locator with optional host and filesystem overrides.
  const ClaudeCodeCliLocator({
    this.environment,
    bool? isWindows,
    this.fileExists,
  }) : _isWindowsOverride = isWindows;

  /// Optional environment override for hosts and tests.
  final Map<String, String>? environment;

  /// Optional asynchronous file-existence check used by tests and hosts.
  final ClaudeCodeCliFileExists? fileExists;

  final bool? _isWindowsOverride;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;
  Map<String, String> get _environment => environment ?? Platform.environment;

  /// Validates a user-selected Claude Code path.
  Future<ResolvedCliProcessCommand?> resolvePath(String path) async {
    final candidate = path.trim();
    if (!_isSupported(candidate) || !await _exists(candidate)) {
      return null;
    }
    return _resolveLauncher(candidate);
  }

  /// Locates the effective executable, continuing after stale saved paths.
  Future<ResolvedCliProcessCommand?> locate(AgentProviderConfig config) async {
    final values = <String, String>{..._environment, ...config.environment};
    final candidates = <String>[
      if (config.extra['cliPath'] case final String path) path,
      if (_looksLikePath(config.command)) config.command,
      ..._pathCandidates(values),
      ..._commonCandidates(values),
    ];
    final seen = <String>{};
    for (final raw in candidates) {
      final candidate = raw.trim();
      final identity = _isWindows ? candidate.toLowerCase() : candidate;
      if (!seen.add(identity) ||
          !_isSupported(candidate) ||
          !await _exists(candidate)) {
        continue;
      }
      return _resolveLauncher(candidate);
    }
    return null;
  }

  Iterable<String> _pathCandidates(Map<String, String> values) sync* {
    final path = values['PATH'] ?? '';
    final names = _isWindows
        ? const <String>['claude.exe', 'claude.cmd', 'claude.bat', 'claude.ps1']
        : const <String>['claude'];
    for (final directory in path.split(_isWindows ? ';' : ':')) {
      final normalized = directory.trim().replaceAll('"', '');
      if (normalized.isEmpty) {
        continue;
      }
      for (final name in names) {
        yield _join(normalized, name);
      }
    }
  }

  Iterable<String> _commonCandidates(Map<String, String> values) sync* {
    if (_isWindows) {
      final localAppData = values['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        yield _join(
          localAppData,
          'Microsoft',
          'WinGet',
          'Links',
          'claude.exe',
        );
      }
      final home = values['USERPROFILE'];
      if (home != null && home.isNotEmpty) {
        yield _join(home, '.local', 'bin', 'claude.exe');
      }
      final appData = values['APPDATA'];
      if (appData != null && appData.isNotEmpty) {
        yield _join(appData, 'npm', 'claude.cmd');
      }
      return;
    }
    final home = values['HOME'];
    if (home != null && home.isNotEmpty) {
      yield _join(home, '.local', 'bin', 'claude');
      yield _join(home, '.npm-global', 'bin', 'claude');
    }
    yield '/usr/local/bin/claude';
    yield '/opt/homebrew/bin/claude';
    yield '/usr/bin/claude';
  }

  bool _isSupported(String path) {
    if (path.isEmpty || !looksLikeClaudeCodeCliPath(path)) {
      return false;
    }
    if (!_isWindows) {
      return true;
    }
    return const <String>{
      'claude.exe',
      'claude.cmd',
      'claude.bat',
      'claude.ps1',
    }.contains(_basename(path).toLowerCase());
  }

  Future<bool> _exists(String path) {
    final override = fileExists;
    return override != null
        ? override(path)
        : Future<bool>.value(
            FileSystemEntity.typeSync(path) == FileSystemEntityType.file,
          );
  }

  ResolvedCliProcessCommand _resolveLauncher(String path) {
    if (!_isWindows || path.toLowerCase().endsWith('.exe')) {
      return ResolvedCliProcessCommand(
        executable: path,
        arguments: const <String>[],
        displayPath: path,
      );
    }
    final windowsRoot = _environment['SystemRoot'] ?? r'C:\Windows';
    if (path.toLowerCase().endsWith('.ps1')) {
      return ResolvedCliProcessCommand(
        executable: _join(
          windowsRoot,
          'System32',
          'WindowsPowerShell',
          'v1.0',
          'powershell.exe',
        ),
        arguments: <String>[
          '-NoLogo',
          '-NoProfile',
          '-NonInteractive',
          '-File',
          path,
        ],
        displayPath: path,
      );
    }
    return ResolvedCliProcessCommand(
      executable: _join(windowsRoot, 'System32', 'cmd.exe'),
      arguments: <String>['/d', '/s', '/c', 'call', path],
      displayPath: path,
    );
  }

  String _join(
    String first,
    String second, [
    String? third,
    String? fourth,
    String? fifth,
    String? sixth,
  ]) {
    final separator = _isWindows ? r'\' : '/';
    final prefix = !_isWindows && first.startsWith('/')
        ? '/'
        : _isWindows && first.startsWith(r'\\')
        ? r'\\'
        : '';
    final joined = <String?>[first, second, third, fourth, fifth, sixth]
        .whereType<String>()
        .map((part) => part.replaceAll(RegExp(r'^[\\/]+|[\\/]+$'), ''))
        .join(separator);
    return '$prefix$joined';
  }
}

/// Whether [path] has an exact Claude Code executable basename.
bool looksLikeClaudeCodeCliPath(String path) {
  return const <String>{
    'claude',
    'claude.exe',
    'claude.cmd',
    'claude.bat',
    'claude.ps1',
  }.contains(_basename(path).toLowerCase());
}

bool _looksLikePath(String value) =>
    value.contains('/') || value.contains(r'\') || value.contains(':');

String _basename(String path) => path.split(RegExp(r'[\\/]')).last;

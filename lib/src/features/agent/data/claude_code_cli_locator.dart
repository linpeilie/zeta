import 'dart:io';

import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 在已保存路径、PATH 与常见安装目录中定位 Claude Code CLI。
class ClaudeCodeCliLocator {
  const ClaudeCodeCliLocator({
    this.environment,
    bool? isWindows,
    this._fileExists,
  }) : _isWindowsOverride = isWindows;

  /// 仅用于测试或宿主覆盖；默认使用当前进程环境。
  final Map<String, String>? environment;

  final bool? _isWindowsOverride;
  final CliFileExists? _fileExists;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  Map<String, String> get _baseEnvironment =>
      environment ?? Platform.environment;

  /// 校验用户给定路径并转换为可执行启动器。
  Future<ResolvedCliCommand?> resolvePath(String path) {
    return _locator(_baseEnvironment).resolvePath(path);
  }

  /// 定位当前可用的 CLI，Windows 会跳过 npm 的无扩展名 POSIX shim。
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) {
    final effectiveEnvironment = <String, String>{
      ..._baseEnvironment,
      ...config.environment,
    };
    return _locator(effectiveEnvironment).locate(config);
  }

  CliCommandLocator _locator(Map<String, String> effectiveEnvironment) {
    return CliCommandLocator(
      executableName: 'claude',
      environment: effectiveEnvironment,
      additionalCandidates: _commonCandidates(effectiveEnvironment),
      isWindows: _isWindows,
      fileExists: _fileExists,
    );
  }

  List<String> _commonCandidates(Map<String, String> effectiveEnvironment) {
    final candidates = <String>[];
    if (_isWindows) {
      final localAppData = effectiveEnvironment['LOCALAPPDATA'];
      if (localAppData != null && localAppData.isNotEmpty) {
        candidates.add(
          joinCliPath(
            joinCliPath(
              joinCliPath(
                joinCliPath(localAppData, 'Microsoft', isWindows: true),
                'WinGet',
                isWindows: true,
              ),
              'Links',
              isWindows: true,
            ),
            'claude.exe',
            isWindows: true,
          ),
        );
      }
    }
    candidates.addAll(
      standardCliInstallCandidates(
        executableName: 'claude',
        environment: effectiveEnvironment,
        isWindows: _isWindows,
      ),
    );
    return List<String>.unmodifiable(candidates);
  }
}

/// 路径 basename 是否像 Claude Code CLI（`claude` / `claude.exe` 等）。
bool looksLikeClaudeCodeCliPath(String path) =>
    looksLikeCliPath(path, 'claude');

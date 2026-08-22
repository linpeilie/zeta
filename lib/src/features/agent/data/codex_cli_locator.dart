import 'dart:io';

import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

export 'package:zeta/src/features/agent/data/cli_command_locator.dart'
    show ResolvedCliCommand;

/// 在已保存路径、PATH 与常见安装目录中定位 Codex CLI。
class CodexCliLocator {
  const CodexCliLocator({this.environment, bool? isWindows, this._fileExists})
    : _isWindowsOverride = isWindows;

  /// 仅用于测试或宿主覆盖；默认使用当前进程环境。
  final Map<String, String>? environment;

  final bool? _isWindowsOverride;
  final CliFileExists? _fileExists;

  bool get _isWindows => _isWindowsOverride ?? Platform.isWindows;

  Map<String, String> get _baseEnvironment =>
      environment ?? Platform.environment;

  /// 校验用户选择的文件并转换为可执行启动器。
  ///
  /// 仅接受文件名像 `codex` 的路径，避免误用 Grok 等其它 CLI。
  Future<ResolvedCliCommand?> resolvePath(String path) {
    return _locator(_baseEnvironment).resolvePath(path);
  }

  /// 定位当前可用的 CLI，已保存路径失效时会继续自动探测。
  ///
  /// 会跳过文件名不像 Codex 的候选（例如误写入的 Grok `cliPath`）。
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) {
    final effectiveEnvironment = <String, String>{
      ..._baseEnvironment,
      ...config.environment,
    };
    return _locator(effectiveEnvironment).locate(config);
  }

  CliCommandLocator _locator(Map<String, String> effectiveEnvironment) {
    return CliCommandLocator(
      executableName: 'codex',
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
        // Codex Desktop 安装的 CLI 优先使用原生 exe。
        candidates
          ..add(
            joinCliPath(
              joinCliPath(
                joinCliPath(
                  joinCliPath(
                    joinCliPath(localAppData, 'Programs', isWindows: true),
                    'OpenAI',
                    isWindows: true,
                  ),
                  'Codex',
                  isWindows: true,
                ),
                'bin',
                isWindows: true,
              ),
              'codex.exe',
              isWindows: true,
            ),
          )
          ..add(
            joinCliPath(
              joinCliPath(
                joinCliPath(localAppData, 'Programs', isWindows: true),
                'codex',
                isWindows: true,
              ),
              'codex.exe',
              isWindows: true,
            ),
          );
      }
    }
    candidates.addAll(
      standardCliInstallCandidates(
        executableName: 'codex',
        environment: effectiveEnvironment,
        isWindows: _isWindows,
      ),
    );
    return List<String>.unmodifiable(candidates);
  }
}

/// 路径 basename 是否像 Codex CLI（`codex` / `codex.exe` 等）。
bool looksLikeCodexCliPath(String path) => looksLikeCliPath(path, 'codex');

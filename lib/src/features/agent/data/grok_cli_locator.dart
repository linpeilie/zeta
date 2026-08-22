import 'dart:io';

import 'package:zeta/src/features/agent/data/cli_command_locator.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 在已保存路径、PATH 与常见安装目录中定位 Grok CLI。
class GrokCliLocator {
  const GrokCliLocator({this.environment, bool? isWindows, this._fileExists})
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
  /// 仅接受文件名像 `grok` 的路径，避免误用 Codex 等其它 CLI。
  Future<ResolvedCliCommand?> resolvePath(String path) {
    return _locator(_baseEnvironment).resolvePath(path);
  }

  /// 定位当前可用的 CLI，已保存路径失效时会继续自动探测。
  ///
  /// 会跳过文件名不像 Grok 的候选（例如误写入的 Codex `cliPath`）。
  Future<ResolvedCliCommand?> locate(AgentProviderConfig config) {
    final effectiveEnvironment = <String, String>{
      ..._baseEnvironment,
      ...config.environment,
    };
    return _locator(effectiveEnvironment).locate(config);
  }

  CliCommandLocator _locator(Map<String, String> effectiveEnvironment) {
    return CliCommandLocator(
      executableName: 'grok',
      environment: effectiveEnvironment,
      additionalCandidates: _commonCandidates(effectiveEnvironment),
      isWindows: _isWindows,
      fileExists: _fileExists,
    );
  }

  List<String> _commonCandidates(Map<String, String> effectiveEnvironment) {
    final candidates = <String>[];
    final home = effectiveEnvironment[_isWindows ? 'USERPROFILE' : 'HOME'];
    if (home != null && home.isNotEmpty) {
      candidates.add(
        joinCliPath(
          joinCliPath(
            joinCliPath(home, '.grok', isWindows: _isWindows),
            'bin',
            isWindows: _isWindows,
          ),
          _isWindows ? 'grok.exe' : 'grok',
          isWindows: _isWindows,
        ),
      );
    }
    candidates.addAll(
      standardCliInstallCandidates(
        executableName: 'grok',
        environment: effectiveEnvironment,
        isWindows: _isWindows,
      ),
    );
    return List<String>.unmodifiable(candidates);
  }
}

/// 路径 basename 是否像 Grok CLI（`grok` / `grok.exe` 等）。
bool looksLikeGrokCliPath(String path) => looksLikeCliPath(path, 'grok');

import 'dart:convert';
import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 全局 provider 配置的旧版 shared_preferences key。
const String agentProviderConfigStorageKey = 'zeta.agent.providers.v1';

/// Agent provider 配置仓库。
///
/// 这里保存的是全局 provider 定义和当前默认 provider；项目级 thread id 不放在这里。
abstract class AgentProviderConfigStore {
  /// 加载 provider 设置，失败时由实现回退到默认 Codex。
  Future<AgentProviderSettings> load();

  /// 保存 provider 设置。
  Future<void> save(AgentProviderSettings settings);
}

/// 基于 JSON 文件的生产配置仓库。
class FileAgentProviderConfigStore implements AgentProviderConfigStore {
  FileAgentProviderConfigStore({required File file})
    : _storage = AtomicTextFile(file);

  final AtomicTextFile _storage;

  @override
  Future<AgentProviderSettings> load() async {
    try {
      return _decodeSettings(await _storage.read());
    } on IOException {
      // 配置文件不可读时继续使用内置 provider，不阻断应用启动。
      return const AgentProviderSettings();
    } on FormatException {
      // 配置文件不可读时继续使用内置 provider，不阻断应用启动。
      return const AgentProviderSettings();
    }
  }

  @override
  Future<void> save(AgentProviderSettings settings) async {
    await _storage.write(jsonEncode(settings.toJson()));
  }
}

/// 通过回调读写 JSON 的配置仓库。
///
/// 主要用于 widget test 或未来的宿主环境注入。
class CallbackAgentProviderConfigStore implements AgentProviderConfigStore {
  const CallbackAgentProviderConfigStore({
    required this.loadJson,
    required this.saveJson,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;

  @override
  Future<AgentProviderSettings> load() async {
    return _decodeSettings(await loadJson());
  }

  @override
  Future<void> save(AgentProviderSettings settings) {
    return saveJson(jsonEncode(settings.toJson()));
  }
}

/// 内存版配置仓库。
///
/// 测试启动 MainApp 时使用它，避免 widget test 触碰真实本地偏好设置。
class MemoryAgentProviderConfigStore implements AgentProviderConfigStore {
  MemoryAgentProviderConfigStore([AgentProviderSettings? settings])
    : _settings = settings ?? const AgentProviderSettings();

  AgentProviderSettings _settings;

  @override
  Future<AgentProviderSettings> load() async => _settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    _settings = settings;
  }
}

/// 宽容解析 provider 设置。
///
/// 配置为空、损坏或版本不匹配时返回默认值，让 Agent 面板可以继续显示。
AgentProviderSettings _decodeSettings(String? value) {
  if (value == null || value.isEmpty) {
    return const AgentProviderSettings();
  }

  try {
    final decoded = jsonDecode(value);
    return AgentProviderSettings.tryDecode(decoded);
  } catch (_) {
    return const AgentProviderSettings();
  }
}

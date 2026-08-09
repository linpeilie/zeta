import 'dart:io';

import 'package:zeta/src/core/storage/atomic_text_file.dart';
import 'package:zeta/src/features/agent/application/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

export 'package:zeta/src/features/agent/application/agent_provider_config_store.dart'
    show AgentProviderConfigStore;

/// 全局 provider 配置的旧版 shared_preferences key。
const String agentProviderConfigStorageKey = 'zeta.agent.providers.v1';

/// 基于 JSON 文件的生产配置仓库。
class FileAgentProviderConfigStore implements AgentProviderConfigStore {
  factory FileAgentProviderConfigStore({
    required File file,
    required AgentProviderSettingsCodec codec,
  }) => FileAgentProviderConfigStore._(AtomicTextFile(file), codec);

  FileAgentProviderConfigStore._(this._storage, this._codec);

  final AtomicTextFile _storage;
  final AgentProviderSettingsCodec _codec;

  @override
  Future<AgentProviderSettings> load() async {
    try {
      return _codec.decodeJson(await _storage.read());
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
    await _storage.write(_codec.encodeJson(settings));
  }
}

/// 通过回调读写 JSON 的配置仓库。
///
/// 主要用于 widget test 或未来的宿主环境注入。
class CallbackAgentProviderConfigStore implements AgentProviderConfigStore {
  const CallbackAgentProviderConfigStore({
    required this.loadJson,
    required this.saveJson,
    required this.codec,
  });

  final Future<String?> Function() loadJson;
  final Future<void> Function(String value) saveJson;
  final AgentProviderSettingsCodec codec;

  @override
  Future<AgentProviderSettings> load() async {
    return codec.decodeJson(await loadJson());
  }

  @override
  Future<void> save(AgentProviderSettings settings) {
    return saveJson(codec.encodeJson(settings));
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

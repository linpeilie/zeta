import 'dart:io';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

import 'package:zeta/src/features/agent/data/agent_provider_config_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 基于 JSON 文件的生产配置仓库。
class FileAgentProviderConfigStore implements AgentProviderConfigStore {
  factory FileAgentProviderConfigStore({
    required ZetaTextFile storage,
    required AgentProviderSettingsCodec codec,
  }) => FileAgentProviderConfigStore._(storage, codec);

  FileAgentProviderConfigStore._(this._storage, this._codec);

  final ZetaTextFile _storage;
  final AgentProviderSettingsCodec _codec;

  @override
  Future<AgentProviderSettings> load() async {
    try {
      return _codec.decodeJson(await _storage.read());
    } on IOException {
      // 配置文件不可读时继续使用内置 provider，不阻断应用启动。
      return _codec.fallbackSettings;
    } on FormatException {
      // 配置文件不可读时继续使用内置 provider，不阻断应用启动。
      return _codec.fallbackSettings;
    }
  }

  @override
  Future<void> save(AgentProviderSettings settings) async {
    await _storage.write(_codec.encodeJson(settings));
  }
}

/// 内存版配置仓库。
///
/// 测试启动 MainApp 时使用它，避免 widget test 触碰真实本地偏好设置。
class MemoryAgentProviderConfigStore implements AgentProviderConfigStore {
  MemoryAgentProviderConfigStore([AgentProviderSettings? settings])
    : _settings = settings ?? builtInAgentProviderSettings;

  AgentProviderSettings _settings;

  @override
  Future<AgentProviderSettings> load() async => _settings;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    _settings = settings;
  }
}

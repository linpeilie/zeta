import 'dart:convert';

import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 当前 Provider settings 的 data codec。
final class AgentProviderSettingsCodec {
  factory AgentProviderSettingsCodec({
    required AgentProviderDefinitionCatalog providerDefinitions,
  }) => AgentProviderSettingsCodec._(providerDefinitions);

  AgentProviderSettingsCodec._(AgentProviderDefinitionCatalog definitions)
    : _providerDefinitions = definitions;

  final AgentProviderDefinitionCatalog _providerDefinitions;

  /// 损坏、空白或未知版本输入使用的插件目录默认快照。
  AgentProviderSettings get fallbackSettings =>
      _providerDefinitions.defaultSettings;

  /// 宽容读取 JSON 文本；空白、损坏或不支持版本均回退内置设置。
  AgentProviderSettings decodeJson(String? value) {
    if (value == null || value.trim().isEmpty) {
      return fallbackSettings;
    }
    try {
      return decode(jsonDecode(value));
    } catch (_) {
      return fallbackSettings;
    }
  }

  /// 解码当前 settings 对象。
  AgentProviderSettings decode(Object? value) {
    final settings = _objectMap(value);
    final version = settings['version'];
    if (version != AgentProviderSettings.currentVersion) {
      return fallbackSettings;
    }
    final providers = _providerDefinitions.ensureDefaultProviders(
      _decodeProviderList(settings['providers']),
    );
    final activeProviderId =
        decodeOptionalString(settings['activeProviderId']) ??
        _providerDefinitions.defaultDefinition.providerId;
    return AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId:
          providers.any((provider) => provider.id == activeProviderId)
          ? activeProviderId
          : _providerDefinitions.defaultDefinition.providerId,
    );
  }

  /// 解码单个 provider；供配置编辑与 fixture 复用。
  AgentProviderConfig? decodeProvider(Object? value) {
    return _decodeProvider(value);
  }

  /// 只写当前 domain 白名单字段。
  String encodeJson(AgentProviderSettings settings) {
    return jsonEncode(settings.toJson());
  }

  AgentProviderConfig? _decodeProvider(Object? value) {
    final map = decodeObjectMap(value);
    if (map.isEmpty) {
      return null;
    }
    final id = decodeOptionalString(map['id']);
    final displayName = decodeOptionalString(map['displayName']);
    final command = decodeOptionalString(map['command']);
    final kind = _providerDefinitions.decodeProviderType(
      decodeOptionalString(map['kind']),
    );
    if (id == null ||
        displayName == null ||
        command == null ||
        kind == null ||
        !_providerDefinitions.acceptsConfigIdentity(id, kind)) {
      return null;
    }
    return AgentProviderConfig(
      id: id,
      displayName: _providerDefinitions.normalizeDisplayName(id, displayName),
      kind: kind,
      command: command,
      arguments: List<String>.unmodifiable(decodeStringList(map['arguments'])),
      environment: Map<String, String>.unmodifiable(
        decodeStringMap(map['environment']),
      ),
      defaultModel: decodeOptionalString(map['defaultModel']),
      selectedModel: decodeOptionalString(map['selectedModel']),
      selectedReasoningEffort: decodeOptionalString(
        map['selectedReasoningEffort'],
      ),
      selectedServiceTier: decodeOptionalString(map['selectedServiceTier']),
      modelPreferences: _decodeModelPreferences(map['modelPreferences']),
      selectedPermissionOptionId: _normalizedOptionId(
        decodeOptionalString(map['selectedPermissionOptionId']),
      ),
      enabled: map['enabled'] is bool ? map['enabled'] as bool : true,
      extra: decodeObjectMap(map['extra']),
    );
  }

  List<AgentProviderConfig> _decodeProviderList(Object? value) {
    if (value is! List) {
      return _providerDefinitions.defaultSettings.providers;
    }
    final providers = <AgentProviderConfig>[];
    final seen = <String>{};
    for (final item in value) {
      final provider = _decodeProvider(item);
      if (provider != null && seen.add(provider.id)) {
        providers.add(provider);
      }
    }
    return providers;
  }
}

Map<String, AgentModelPreference> _decodeModelPreferences(Object? value) {
  final decoded = <String, AgentModelPreference>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final preference = AgentModelPreference.tryDecode(entry.value);
      if (preference != null) {
        decoded[preference.modelId] = preference;
      }
    }
  }
  return Map<String, AgentModelPreference>.unmodifiable(decoded);
}

Map<String, Object?> _objectMap(Object? value) {
  if (value is! Map) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(
    value.map((key, item) => MapEntry(key.toString(), item)),
  );
}

String? _normalizedOptionId(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

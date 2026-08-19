import 'dart:convert';

import 'package:zeta/src/features/agent/data/agent_provider_permission_migration.dart';
import 'package:zeta/src/features/agent/domain/agent_model_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_model_selection_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_models.dart';

/// Provider settings 的版本化 data codec。
///
/// V2 `selectedPermissionOptionId` 只要存在就作为唯一权限真源；仅当该 key
/// 完全缺失时，才按 Provider kind 调用 legacy migrator。domain 始终只看到
/// 归一化后的中立 optionId。
final class AgentProviderSettingsCodec {
  factory AgentProviderSettingsCodec({
    required AgentProviderPermissionMigrationRegistry migrationRegistry,
  }) => AgentProviderSettingsCodec._(migrationRegistry);

  AgentProviderSettingsCodec._(this._migrationRegistry);

  final AgentProviderPermissionMigrationRegistry _migrationRegistry;

  /// 宽容读取 JSON 文本；空白、损坏或不支持版本均回退内置设置。
  AgentProviderSettings decodeJson(String? value) {
    if (value == null || value.trim().isEmpty) {
      return const AgentProviderSettings();
    }
    try {
      return decode(jsonDecode(value));
    } catch (_) {
      return const AgentProviderSettings();
    }
  }

  /// 解码 settings 对象，并在进入 domain 前迁移每个 provider 配置。
  AgentProviderSettings decode(Object? value) {
    final settings = _objectMap(value);
    final version = settings['version'];
    if (version is! int ||
        !AgentProviderSettings.supportedVersions.contains(version)) {
      return const AgentProviderSettings();
    }
    final providers = _ensureBuiltinProviders(
      _decodeProviderList(settings['providers'], migrate: _migrateProviderMap),
    );
    final activeProviderId =
        decodeOptionalString(settings['activeProviderId']) ??
        defaultAgentProviderId;
    return AgentProviderSettings(
      providers: List<AgentProviderConfig>.unmodifiable(providers),
      activeProviderId:
          providers.any((provider) => provider.id == activeProviderId)
          ? activeProviderId
          : providers.first.id,
    );
  }

  /// 解码单个 provider；供配置编辑、fixture 与迁移测试复用。
  AgentProviderConfig? decodeProvider(Object? value) {
    return _decodeProvider(_migrateProviderMap(value));
  }

  /// 只写 V2 domain 白名单字段。
  String encodeJson(AgentProviderSettings settings) {
    return jsonEncode(settings.toJson());
  }

  Object? _migrateProviderMap(Object? value) {
    final raw = _objectMap(value);
    if (raw.isEmpty || raw.containsKey('selectedPermissionOptionId')) {
      return raw;
    }
    final decoded = _decodeProvider(raw);
    if (decoded == null) {
      return raw;
    }
    final migratedOptionId = _normalizedOptionId(
      _migrationRegistry.migrateLegacyOptionId(
        providerKind: decoded.kind,
        legacyConfig: Map<String, Object?>.unmodifiable(raw),
      ),
    );
    if (migratedOptionId == null) {
      return raw;
    }
    return <String, Object?>{
      ...raw,
      'selectedPermissionOptionId': migratedOptionId,
    };
  }
}

AgentProviderConfig? _decodeProvider(Object? value) {
  final map = decodeObjectMap(value);
  if (map.isEmpty) {
    return null;
  }
  final id = decodeOptionalString(map['id']);
  final displayName = decodeOptionalString(map['displayName']);
  final command = decodeOptionalString(map['command']);
  final kind = _providerKind(decodeOptionalString(map['kind']));
  if (id == null || displayName == null || command == null || kind == null) {
    return null;
  }
  return AgentProviderConfig(
    id: id,
    displayName: AgentProviderConfig.normalizeDisplayName(id, displayName),
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

Map<String, AgentModelPreference> _decodeModelPreferences(Object? value) {
  final decoded = <String, AgentModelPreference>{};
  if (value is Map) {
    for (final entry in value.entries) {
      final preference = AgentModelPreference.tryDecode(entry.value);
      if (preference != null) {
        decoded[preference.modelId] = preference;
      }
    }
  } else if (value is List) {
    for (final item in value) {
      final preference = AgentModelPreference.tryDecode(item);
      if (preference != null) {
        decoded[preference.modelId] = preference;
      }
    }
  }
  return Map<String, AgentModelPreference>.unmodifiable(decoded);
}

List<AgentProviderConfig> _decodeProviderList(
  Object? value, {
  required Object? Function(Object? value) migrate,
}) {
  if (value is! List) {
    return const <AgentProviderConfig>[
      AgentProviderConfig.defaultCodex,
      AgentProviderConfig.defaultGrok,
    ];
  }
  final providers = <AgentProviderConfig>[];
  final seen = <String>{};
  for (final item in value) {
    final provider = _decodeProvider(migrate(item));
    if (provider != null && seen.add(provider.id)) {
      providers.add(provider);
    }
  }
  return providers;
}

List<AgentProviderConfig> _ensureBuiltinProviders(
  List<AgentProviderConfig> providers,
) {
  final result = List<AgentProviderConfig>.from(providers);
  final ids = result.map((provider) => provider.id).toSet();
  if (!ids.contains(defaultAgentProviderId)) {
    result.insert(0, AgentProviderConfig.defaultCodex);
  }
  if (!ids.contains(grokAgentProviderId)) {
    result.add(AgentProviderConfig.defaultGrok);
  }
  return result;
}

AgentProviderKind? _providerKind(String? value) {
  for (final kind in AgentProviderKind.values) {
    if (kind.name == value) {
      return kind;
    }
  }
  return null;
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

import 'dart:convert';

import 'package:zeta/src/features/agent/data/agent_provider_permission_migration.dart';
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
    if (settings.isEmpty) {
      return const AgentProviderSettings();
    }
    final providers = settings['providers'];
    if (providers is! List) {
      return AgentProviderSettings.tryDecode(settings);
    }
    return AgentProviderSettings.tryDecode(<String, Object?>{
      ...settings,
      'providers': <Object?>[
        for (final provider in providers) _migrateProviderMap(provider),
      ],
    });
  }

  /// 解码单个 provider；供配置编辑、fixture 与迁移测试复用。
  AgentProviderConfig? decodeProvider(Object? value) {
    return AgentProviderConfig.tryDecode(_migrateProviderMap(value));
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
    final decoded = AgentProviderConfig.tryDecode(raw);
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

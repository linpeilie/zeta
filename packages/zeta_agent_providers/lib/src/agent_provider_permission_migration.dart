import 'package:zeta_agent_providers/src/mappers/grok_permission_mode_codec.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// 旧 Provider 权限偏好到中立 optionId 的迁移端口。
///
/// 实现只消费 Zeta 自有 provider JSON 的内存快照，不执行任何文件或用户目录 IO。
abstract interface class AgentProviderPermissionPreferenceMigrator {
  /// 从当前 Provider 的 legacy 配置字段推导中立 optionId。
  String? migrateLegacyOptionId(Map<String, Object?> legacyConfig);
}

/// 按 Provider kind 选择专属迁移器的不可变注册表。
final class AgentProviderPermissionMigrationRegistry {
  AgentProviderPermissionMigrationRegistry(
    Map<AgentProviderKind, AgentProviderPermissionPreferenceMigrator> migrators,
  ) : _migrators =
          Map<
            AgentProviderKind,
            AgentProviderPermissionPreferenceMigrator
          >.unmodifiable(migrators);

  final Map<AgentProviderKind, AgentProviderPermissionPreferenceMigrator>
  _migrators;

  /// 已注册迁移器的 Provider kind，不允许调用方修改。
  Set<AgentProviderKind> get registeredKinds =>
      Set<AgentProviderKind>.unmodifiable(_migrators.keys);

  /// 未注册的 Provider 不猜测 legacy 权限语义。
  String? migrateLegacyOptionId({
    required AgentProviderKind providerKind,
    required Map<String, Object?> legacyConfig,
  }) {
    return _migrators[providerKind]?.migrateLegacyOptionId(legacyConfig);
  }
}

/// Codex V1 profile/approval/sandbox → 中立 optionId。
final class CodexPermissionPreferenceMigrator
    implements AgentProviderPermissionPreferenceMigrator {
  const CodexPermissionPreferenceMigrator();

  @override
  String? migrateLegacyOptionId(Map<String, Object?> legacyConfig) {
    final profileId = _nonEmptyString(
      legacyConfig['selectedPermissionProfileId'],
    );
    if (profileId != null) {
      return profileId;
    }
    final approval = _nonEmptyString(legacyConfig['selectedApprovalPolicy']);
    final sandbox = _nonEmptyString(legacyConfig['selectedSandboxPolicy']);
    if (approval == null || sandbox == null) {
      return null;
    }
    final normalizedApproval = switch (approval) {
      'untrusted' || 'on-request' || 'never' => approval,
      'on-failure' => 'on-request',
      _ => null,
    };
    final normalizedSandbox = switch (sandbox) {
      'readOnly' || 'workspaceWrite' || 'dangerFullAccess' => sandbox,
      'read-only' => 'readOnly',
      'workspace-write' => 'workspaceWrite',
      'danger-full-access' => 'dangerFullAccess',
      _ => null,
    };
    return switch ((normalizedApproval, normalizedSandbox)) {
      ('on-request', 'readOnly') => ':read-only',
      ('on-request', 'workspaceWrite') => ':workspace',
      ('never', 'dangerFullAccess') => ':danger-full-access',
      _ => null,
    };
  }
}

/// Grok V1 mode → 中立 optionId。
final class GrokPermissionPreferenceMigrator
    implements AgentProviderPermissionPreferenceMigrator {
  const GrokPermissionPreferenceMigrator();

  @override
  String? migrateLegacyOptionId(Map<String, Object?> legacyConfig) {
    if (!legacyConfig.containsKey('selectedPermissionMode')) {
      return null;
    }
    final raw = _nonEmptyString(legacyConfig['selectedPermissionMode']);
    return GrokPermissionModeCodec.wireId(GrokPermissionModeCodec.parse(raw));
  }
}

String? _nonEmptyString(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

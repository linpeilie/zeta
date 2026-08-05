import 'package:zeta/src/features/agent/domain/agent_permission_selection_models.dart';

/// Grok ACP 权限模式编解码（协议私货，仅 Grok data 层使用）。
///
/// 对齐 grok-build：
/// - `session/new|load` 的 `_meta.yoloMode` / `_meta.autoMode`
/// - 扩展通知 `x.ai/yolo_mode_changed`
enum GrokPermissionMode { defaultMode, ask, auto, alwaysApprove }

/// Grok permission mode ↔ wire / 会话 meta / 通知参数。
abstract final class GrokPermissionModeCodec {
  static const String defaultWireId = 'ask';
  static const String clientIdentifier = 'zeta';

  static String wireId(GrokPermissionMode mode) {
    return switch (mode) {
      GrokPermissionMode.defaultMode => 'default',
      GrokPermissionMode.ask => 'ask',
      GrokPermissionMode.auto => 'auto',
      GrokPermissionMode.alwaysApprove => 'always-approve',
    };
  }

  /// 未知或空值 fail-closed 到 [GrokPermissionMode.ask]。
  static GrokPermissionMode parse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return GrokPermissionMode.ask;
    }
    return switch (normalized) {
      'default' => GrokPermissionMode.defaultMode,
      'ask' => GrokPermissionMode.ask,
      'auto' => GrokPermissionMode.auto,
      'always-approve' ||
      'always_approve' ||
      'alwaysapprove' ||
      'yolo' ||
      'bypasspermissions' ||
      'bypass_permissions' => GrokPermissionMode.alwaysApprove,
      _ => GrokPermissionMode.ask,
    };
  }

  static String displayLabel(GrokPermissionMode mode) {
    return switch (mode) {
      GrokPermissionMode.defaultMode => 'Default',
      GrokPermissionMode.ask => 'Ask',
      GrokPermissionMode.auto => 'Auto',
      GrokPermissionMode.alwaysApprove => 'Always approve',
    };
  }

  /// `session/new` / `session/load` 完整 `_meta`。
  static Map<String, Object?> sessionMeta(GrokPermissionMode mode) {
    final flags = switch (mode) {
      GrokPermissionMode.alwaysApprove => const <String, Object?>{
        'yoloMode': true,
      },
      GrokPermissionMode.auto => const <String, Object?>{'autoMode': true},
      GrokPermissionMode.defaultMode ||
      GrokPermissionMode.ask => const <String, Object?>{},
    };
    return <String, Object?>{...flags, 'clientIdentifier': clientIdentifier};
  }

  /// `x.ai/yolo_mode_changed` 参数。
  static Map<String, Object?> yoloModeChangedParams(GrokPermissionMode mode) {
    final wire = wireId(mode);
    return switch (mode) {
      GrokPermissionMode.alwaysApprove => <String, Object?>{
        'permission_mode': wire,
        'yolo_mode': true,
        'auto_mode': false,
        'clientIdentifier': clientIdentifier,
      },
      GrokPermissionMode.auto => <String, Object?>{
        'permission_mode': wire,
        'yolo_mode': false,
        'auto_mode': true,
        'clientIdentifier': clientIdentifier,
      },
      GrokPermissionMode.defaultMode ||
      GrokPermissionMode.ask => <String, Object?>{
        'permission_mode': wire,
        'yolo_mode': false,
        'auto_mode': false,
        'clientIdentifier': clientIdentifier,
      },
    };
  }

  /// 中立权限选项 catalog（Always approve 置末）。
  static List<AgentPermissionProfileSummary> catalogAsOptions() {
    const order = <GrokPermissionMode>[
      GrokPermissionMode.defaultMode,
      GrokPermissionMode.ask,
      GrokPermissionMode.auto,
      GrokPermissionMode.alwaysApprove,
    ];
    return List<AgentPermissionProfileSummary>.unmodifiable(
      order.map(
        (mode) => AgentPermissionProfileSummary(
          id: wireId(mode),
          allowed: true,
          description: displayLabel(mode),
        ),
      ),
    );
  }
}

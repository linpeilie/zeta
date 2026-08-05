import 'package:zeta/src/features/agent/domain/agent_permission_selection_models.dart';

/// Grok ACP 权限模式编解码（协议私货，仅 Grok data 层使用）。
///
/// ## 协议证据（Grok Build 0.2.118 已安装文档）
///
/// - [22-permissions-and-safety.md]：`default` 与 **ask** 是同一交互基线；
///   产品名 Always-approve 对应 `bypassPermissions`；`auto` 为 classifier 模式。
/// - [15-agent-mode.md] `session/new` `_meta`：
///   - `yoloMode: true` → always-approve
///   - `autoMode: true` → auto（always-approve 已开时被 supersede）
///   - 文档只记录 **true 开启** 高权限；未记录 false 关闭。
/// - CLI 默认（无 `--always-approve` / `--yolo`）为 ask 基线。
/// - 扩展方法正式前缀文档为 `x.ai/`；Zeta 实测 client→agent 请求
///   （`_x.ai/billing`、`_x.ai/skills/list`）必须用 `_x.ai/`，裸 `x.ai/skills/list`
///   返回 -32601。
///
/// ## 实现选择
///
/// - UI 只暴露 Ask / Auto / Always approve；`default`、空值、未知值 fail-closed 到 Ask。
/// - Ask 的 `session/new|load` meta 不发明 `yoloMode:false`（文档未验证）；依赖
///   process 不以 `--always-approve` 启动作为安全基线，并用 live 通知的显式 false
///   关闭高权限（见 [yoloModeChangedParams]）。
/// - live 通知只发 `_x.ai/yolo_mode_changed`（与 billing/skills 一致），不再双发。
enum GrokPermissionMode { ask, auto, alwaysApprove }

/// Grok permission mode ↔ wire / 会话 meta / 通知参数。
abstract final class GrokPermissionModeCodec {
  static const String defaultWireId = 'ask';
  static const String clientIdentifier = 'zeta';

  /// Client→agent 权限 live 通知 method（单 method，避免双发副作用）。
  ///
  /// 选择 `_x.ai/`：与 0.2.x 上可验证的 client→agent 扩展请求前缀一致。
  static const String yoloModeChangedMethod = '_x.ai/yolo_mode_changed';

  /// catalog 稳定顺序：Ask → Auto → Always approve。
  static const List<GrokPermissionMode> catalogOrder = <GrokPermissionMode>[
    GrokPermissionMode.ask,
    GrokPermissionMode.auto,
    GrokPermissionMode.alwaysApprove,
  ];

  static String wireId(GrokPermissionMode mode) {
    return switch (mode) {
      GrokPermissionMode.ask => 'ask',
      GrokPermissionMode.auto => 'auto',
      GrokPermissionMode.alwaysApprove => 'always-approve',
    };
  }

  /// 未知、空值与旧 `default` 别名一律 fail-closed 到 [GrokPermissionMode.ask]。
  static GrokPermissionMode parse(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return GrokPermissionMode.ask;
    }
    return switch (normalized) {
      // 文档：default (**ask**)；旧配置别名一并收口。
      'default' || 'ask' => GrokPermissionMode.ask,
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
      GrokPermissionMode.ask => 'Ask',
      GrokPermissionMode.auto => 'Auto',
      GrokPermissionMode.alwaysApprove => 'Always approve',
    };
  }

  /// `session/new` / `session/load` 完整 `_meta`。
  ///
  /// Ask：仅 `clientIdentifier`（文档默认基线为 ask；不发送未验证的 false）。
  /// Auto / Always approve：只发送文档记录的 true 开启字段。
  static Map<String, Object?> sessionMeta(GrokPermissionMode mode) {
    final flags = switch (mode) {
      GrokPermissionMode.alwaysApprove => const <String, Object?>{
        'yoloMode': true,
      },
      GrokPermissionMode.auto => const <String, Object?>{'autoMode': true},
      GrokPermissionMode.ask => const <String, Object?>{},
    };
    return <String, Object?>{...flags, 'clientIdentifier': clientIdentifier};
  }

  /// live 权限切换参数（`_x.ai/yolo_mode_changed`）。
  ///
  /// Ask 显式 `yolo_mode:false` + `auto_mode:false`，用于 Always approve/Auto
  /// 切回 Ask 后停止自动批准（与 session meta 的“仅 true 开启”策略互补）。
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
      GrokPermissionMode.ask => <String, Object?>{
        'permission_mode': wire,
        'yolo_mode': false,
        'auto_mode': false,
        'clientIdentifier': clientIdentifier,
      },
    };
  }

  /// 中立权限选项 catalog（固定三模式）。
  static List<AgentPermissionProfileSummary> catalogAsOptions() {
    return List<AgentPermissionProfileSummary>.unmodifiable(
      catalogOrder.map(
        (mode) => AgentPermissionProfileSummary(
          id: wireId(mode),
          allowed: true,
          description: displayLabel(mode),
        ),
      ),
    );
  }
}

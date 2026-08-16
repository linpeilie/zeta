import 'package:zeta/src/features/agent/domain/agent_permission_policy_models.dart';

/// Claude Code CLI `--permission-mode` 枚举（协议私货，仅 CC data 层）。
enum ClaudeCodePermissionMode { ask, acceptEdits, plan, bypass }

/// 中立 optionId ↔ CLI `--permission-mode` 双向编解码。
///
/// | Zeta optionId | CLI wire |
/// |---|---|
/// | `:ask` | `default` |
/// | `:accept-edits` | `acceptEdits` |
/// | `:plan` | `plan` |
/// | `:bypass` | `bypassPermissions` |
///
/// 未知 / 空值 **fail-closed 到 `:ask`**，绝不落到 `:bypass`。
abstract final class ClaudeCodePermissionModeCodec {
  static const String optionAsk = ':ask';
  static const String optionAcceptEdits = ':accept-edits';
  static const String optionPlan = ':plan';
  static const String optionBypass = ':bypass';

  static const String wireDefault = 'default';
  static const String wireAcceptEdits = 'acceptEdits';
  static const String wirePlan = 'plan';
  static const String wireBypassPermissions = 'bypassPermissions';

  /// catalog 稳定顺序（UI 从保守到激进）。
  static const List<ClaudeCodePermissionMode> catalogOrder =
      <ClaudeCodePermissionMode>[
        ClaudeCodePermissionMode.ask,
        ClaudeCodePermissionMode.acceptEdits,
        ClaudeCodePermissionMode.plan,
        ClaudeCodePermissionMode.bypass,
      ];

  /// 默认中立 optionId。
  static const String defaultOptionId = optionAsk;

  /// 默认 CLI wire 值。
  static const String defaultWireMode = wireDefault;

  static String optionId(ClaudeCodePermissionMode mode) {
    return switch (mode) {
      ClaudeCodePermissionMode.ask => optionAsk,
      ClaudeCodePermissionMode.acceptEdits => optionAcceptEdits,
      ClaudeCodePermissionMode.plan => optionPlan,
      ClaudeCodePermissionMode.bypass => optionBypass,
    };
  }

  /// 中立 optionId → CLI `--permission-mode` 参数值。
  static String toCliPermissionMode(ClaudeCodePermissionMode mode) {
    return switch (mode) {
      ClaudeCodePermissionMode.ask => wireDefault,
      ClaudeCodePermissionMode.acceptEdits => wireAcceptEdits,
      ClaudeCodePermissionMode.plan => wirePlan,
      ClaudeCodePermissionMode.bypass => wireBypassPermissions,
    };
  }

  /// 中立 optionId 字符串 → CLI wire（未知值 → `default`）。
  static String optionIdToCliPermissionMode(String? optionId) {
    return toCliPermissionMode(parseOptionId(optionId));
  }

  /// CLI wire → 中立 optionId 字符串（未知值 → `:ask`）。
  static String cliPermissionModeToOptionId(String? wire) {
    return optionId(parseCliPermissionMode(wire));
  }

  /// 解析中立 optionId；未知 / 空 → [ClaudeCodePermissionMode.ask]。
  static ClaudeCodePermissionMode parseOptionId(String? raw) {
    final normalized = raw?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) {
      return ClaudeCodePermissionMode.ask;
    }
    return switch (normalized) {
      ':ask' || 'ask' => ClaudeCodePermissionMode.ask,
      ':accept-edits' ||
      'accept-edits' ||
      'acceptedits' ||
      'accept_edits' => ClaudeCodePermissionMode.acceptEdits,
      ':plan' || 'plan' => ClaudeCodePermissionMode.plan,
      ':bypass' ||
      'bypass' ||
      'bypasspermissions' ||
      'bypass_permissions' ||
      'yolo' => ClaudeCodePermissionMode.bypass,
      // 绝不默认到 bypass。
      _ => ClaudeCodePermissionMode.ask,
    };
  }

  /// 解析 CLI `--permission-mode`；未知 / 空 → [ClaudeCodePermissionMode.ask]。
  static ClaudeCodePermissionMode parseCliPermissionMode(String? raw) {
    final normalized = raw?.trim();
    if (normalized == null || normalized.isEmpty) {
      return ClaudeCodePermissionMode.ask;
    }
    // CLI 值大小写敏感官方为 camelCase；解析时做宽松归一。
    final lower = normalized.toLowerCase();
    return switch (lower) {
      'default' || 'ask' => ClaudeCodePermissionMode.ask,
      'acceptedits' ||
      'accept-edits' ||
      'accept_edits' => ClaudeCodePermissionMode.acceptEdits,
      'plan' => ClaudeCodePermissionMode.plan,
      'bypasspermissions' ||
      'bypass-permissions' ||
      'bypass_permissions' ||
      'bypass' ||
      'yolo' => ClaudeCodePermissionMode.bypass,
      _ => ClaudeCodePermissionMode.ask,
    };
  }

  static String displayLabel(ClaudeCodePermissionMode mode) {
    return switch (mode) {
      ClaudeCodePermissionMode.ask => 'Ask',
      ClaudeCodePermissionMode.acceptEdits => 'Accept edits',
      ClaudeCodePermissionMode.plan => 'Plan',
      ClaudeCodePermissionMode.bypass => 'Bypass permissions',
    };
  }

  static String displayDescription(ClaudeCodePermissionMode mode) {
    return switch (mode) {
      ClaudeCodePermissionMode.ask => '每个高风险工具都询问',
      ClaudeCodePermissionMode.acceptEdits => '自动允许编辑类工具，其他仍询问',
      ClaudeCodePermissionMode.plan => '只读并产出计划，不执行副作用',
      ClaudeCodePermissionMode.bypass => '跳过权限检查（高风险）',
    };
  }

  /// 中立 [AgentPermissionCatalog]（port / adapter 使用）。
  static AgentPermissionCatalog catalog() {
    final options = catalogOrder
        .map(
          (mode) => AgentPermissionOption(
            id: optionId(mode),
            label: displayLabel(mode),
            description: displayDescription(mode),
            allowed: true,
            planningOnly: mode == ClaudeCodePermissionMode.plan,
          ),
        )
        .toList(growable: false);
    return AgentPermissionCatalog(
      options: options,
      defaultOptionId: defaultOptionId,
    );
  }
}

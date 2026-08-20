import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// Claude Code CLI `--permission-mode` 枚举（协议私货，仅 CC data 层）。
enum ClaudeCodePermissionMode {
  /// Ask before high-risk tool calls.
  ask,

  /// Automatically accept file edits.
  acceptEdits,

  /// Restrict the runtime to planning.
  plan,

  /// Bypass tool permission checks.
  bypass,
}

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
  /// Neutral option id for ask mode.
  static const String optionAsk = ':ask';

  /// Neutral option id for automatic edit approval.
  static const String optionAcceptEdits = ':accept-edits';

  /// Neutral option id for planning mode.
  static const String optionPlan = ':plan';

  /// Neutral option id for bypass mode.
  static const String optionBypass = ':bypass';

  /// CLI wire value for ask mode.
  static const String wireDefault = 'default';

  /// CLI wire value for automatic edit approval.
  static const String wireAcceptEdits = 'acceptEdits';

  /// CLI wire value for planning mode.
  static const String wirePlan = 'plan';

  /// CLI wire value for bypass mode.
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

  /// Runs `optionId`.
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

  /// Maps one provider mode to app-owned presentation copy.
  static AgentPermissionOptionCopyCode copyCode(
    ClaudeCodePermissionMode mode,
  ) {
    return switch (mode) {
      ClaudeCodePermissionMode.ask => AgentPermissionOptionCopyCode.ask,
      ClaudeCodePermissionMode.acceptEdits =>
        AgentPermissionOptionCopyCode.acceptEdits,
      ClaudeCodePermissionMode.plan => AgentPermissionOptionCopyCode.plan,
      ClaudeCodePermissionMode.bypass =>
        AgentPermissionOptionCopyCode.bypassPermissions,
    };
  }

  /// 中立 [AgentPermissionCatalog]（port / adapter 使用）。
  static AgentPermissionCatalog catalog() {
    final options = catalogOrder
        .map(
          (mode) => AgentPermissionOption(
            id: optionId(mode),
            copyCode: copyCode(mode),
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

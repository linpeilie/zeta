import 'package:agent_provider_contracts/src/models/agent_permission_policy_models.dart';
import 'package:meta/meta.dart';

/// Agent 对话运行模式的中立分类。
///
/// Provider 新增但 Zeta 尚未识别的模式映射为 [unknown]，避免协议演进阻断历史读取。
enum AgentConversationModeKind {
  /// Provider 的普通对话模式。
  defaultMode,

  /// Provider 的计划模式。
  plan,

  /// Zeta 尚未识别、但需要宽容保留的 Provider 模式。
  unknown,
}

/// Provider 中立的对话模式标识。
///
/// 标识始终使用去除首尾空白后的小写值；已知值映射为稳定的 [kind]，
/// 未知值仍保留规范化后的原始标识。
@immutable
final class AgentConversationModeId {
  /// 从外部字符串创建模式标识。
  ///
  /// 空字符串不具备稳定身份，会抛出 [ArgumentError]。读取不可信外部数据时应使用
  /// [tryFromRaw]。
  factory AgentConversationModeId.fromRaw(String rawValue) {
    final normalized = normalize(rawValue);
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        rawValue,
        'rawValue',
        'Conversation mode id cannot be empty',
      );
    }
    return switch (normalized) {
      'default' => defaultMode,
      'plan' => plan,
      _ => AgentConversationModeId._(
        rawValue: normalized,
        kind: AgentConversationModeKind.unknown,
      ),
    };
  }
  const AgentConversationModeId._({required this.rawValue, required this.kind});

  /// 默认对话模式。
  static const AgentConversationModeId defaultMode = AgentConversationModeId._(
    rawValue: 'default',
    kind: AgentConversationModeKind.defaultMode,
  );

  /// 计划对话模式。
  static const AgentConversationModeId plan = AgentConversationModeId._(
    rawValue: 'plan',
    kind: AgentConversationModeKind.plan,
  );

  /// 宽容读取外部模式值；类型错误或空字符串返回 null。
  static AgentConversationModeId? tryFromRaw(Object? rawValue) {
    if (rawValue is! String || normalize(rawValue).isEmpty) {
      return null;
    }
    return AgentConversationModeId.fromRaw(rawValue);
  }

  /// 规范化 Provider 提供的模式标识。
  static String normalize(String rawValue) => rawValue.trim().toLowerCase();

  /// 规范化后的 Provider 模式标识。
  final String rawValue;

  /// Zeta 已知的模式分类。
  final AgentConversationModeKind kind;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationModeId &&
      other.rawValue == rawValue &&
      other.kind == kind;

  @override
  int get hashCode => Object.hash(rawValue, kind);

  @override
  String toString() => rawValue;
}

/// Provider 暴露的单个对话模式预设。
@immutable
final class AgentConversationModePreset {
  /// 创建一个 Provider 中立的对话模式预设。
  const AgentConversationModePreset({
    required this.id,
    required this.displayName,
    this.suggestedModelId,
    this.suggestedReasoningEffort,
    this.isSelectable = true,
  });

  /// Provider 中立的模式标识。
  final AgentConversationModeId id;

  /// Provider 建议展示给用户的名称。
  final String displayName;

  /// 预设建议的模型；为空时由下一回合配置补齐有效模型。
  final String? suggestedModelId;

  /// 预设建议的推理深度；为空时沿用当前模型选择。
  final String? suggestedReasoningEffort;

  /// 当前预设是否允许用户主动选择。
  final bool isSelectable;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationModePreset &&
      other.id == id &&
      other.displayName == displayName &&
      other.suggestedModelId == suggestedModelId &&
      other.suggestedReasoningEffort == suggestedReasoningEffort &&
      other.isSelectable == isSelectable;

  @override
  int get hashCode => Object.hash(
    id,
    displayName,
    suggestedModelId,
    suggestedReasoningEffort,
    isSelectable,
  );
}

/// 当前 Provider 可用的对话模式目录。
@immutable
final class AgentConversationModeCatalog {
  /// 创建目录并对 [presets] 做防御性复制。
  AgentConversationModeCatalog({
    required Iterable<AgentConversationModePreset> presets,
  }) : presets = List<AgentConversationModePreset>.unmodifiable(presets);

  /// Provider 返回顺序下的不可修改预设快照。
  final List<AgentConversationModePreset> presets;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationModeCatalog &&
      _orderedEquals(other.presets, presets);

  @override
  int get hashCode => Object.hashAll(presets);
}

/// 一次新回合实际使用的对话模式选择。
///
/// [modeId] 可以承载服务端回写的未知模式；协议编码器在提交前仍需拒绝未知模式。
@immutable
final class AgentConversationModeSelection {
  /// 创建一次有效模式选择；空白 [effectiveModelId] 会抛出 [ArgumentError]。
  AgentConversationModeSelection({
    required this.modeId,
    required String effectiveModelId,
    String? effectiveReasoningEffort,
  }) : effectiveModelId = _requireNonEmpty(
         effectiveModelId,
         'effectiveModelId',
       ),
       effectiveReasoningEffort = _normalizeOptional(effectiveReasoningEffort);

  /// 本回合选择的模式。
  final AgentConversationModeId modeId;

  /// 补齐预设后实际提交的非空模型 id。
  final String effectiveModelId;

  /// 补齐预设后实际提交的推理深度。
  final String? effectiveReasoningEffort;

  @override
  bool operator ==(Object other) =>
      other is AgentConversationModeSelection &&
      other.modeId == modeId &&
      other.effectiveModelId == effectiveModelId &&
      other.effectiveReasoningEffort == effectiveReasoningEffort;

  @override
  int get hashCode =>
      Object.hash(modeId, effectiveModelId, effectiveReasoningEffort);
}

/// 一次 `turn/start`（及同请求边界）的不可变 Agent 配置快照。
@immutable
final class AgentTurnConfiguration {
  /// 创建一个与后续 UI 选择相互隔离的回合配置。
  ///
  /// [permissionSnapshot] 为 application 已按优先级冻结的中立请求快照；
  /// Provider 只在其来源为 fallback 时沿用旧默认逻辑。
  const AgentTurnConfiguration({
    this.conversationMode,
    this.permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  });

  /// 本回合的对话模式；为空表示 Provider 沿用原有发送行为。
  final AgentConversationModeSelection? conversationMode;

  /// 本请求所属 thread 的权限快照。
  final AgentPermissionRequestSnapshot permissionSnapshot;

  /// 复制并覆盖部分字段。
  AgentTurnConfiguration copyWith({
    AgentConversationModeSelection? conversationMode,
    AgentPermissionRequestSnapshot? permissionSnapshot,
  }) {
    return AgentTurnConfiguration(
      conversationMode: conversationMode ?? this.conversationMode,
      permissionSnapshot: permissionSnapshot ?? this.permissionSnapshot,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentTurnConfiguration &&
      other.conversationMode == conversationMode &&
      other.permissionSnapshot == permissionSnapshot;

  @override
  int get hashCode => Object.hash(conversationMode, permissionSnapshot);
}

String _requireNonEmpty(String value, String name) {
  final normalized = value.trim();
  if (normalized.isEmpty) {
    throw ArgumentError.value(value, name, '$name cannot be empty');
  }
  return normalized;
}

String? _normalizeOptional(String? value) {
  final normalized = value?.trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

bool _orderedEquals<T>(List<T> first, List<T> second) {
  if (identical(first, second)) {
    return true;
  }
  if (first.length != second.length) {
    return false;
  }
  for (var index = 0; index < first.length; index += 1) {
    if (first[index] != second[index]) {
      return false;
    }
  }
  return true;
}

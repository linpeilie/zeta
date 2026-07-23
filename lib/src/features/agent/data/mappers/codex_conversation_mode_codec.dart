part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 统一解码 Codex 通知与历史中的协作模式表示。
///
/// 在线 `thread/read` 与本地 JSONL 可能分别保存字符串或带 `mode` 的对象；
/// 此 codec 只返回中立 Domain 类型，缺失/损坏值返回 null，未知非空值原样保留。
final class _CodexConversationModeCodec {
  const _CodexConversationModeCodec();

  AgentConversationModeId? modeIdFromValue(Object? value) {
    final rawMode = switch (value) {
      String() => value,
      Map() => _string(_map(value)['mode']),
      _ => null,
    };
    return AgentConversationModeId.tryFromRaw(rawMode);
  }

  AgentConversationModeSelection? selectionFromValue(Object? value) {
    if (value is! Map) {
      return null;
    }
    final mode = _map(value);
    final modeId = modeIdFromValue(mode);
    final settings = _map(mode['settings']);
    final model = _string(settings['model']);
    if (modeId == null || model == null || model.trim().isEmpty) {
      return null;
    }
    return AgentConversationModeSelection(
      modeId: modeId,
      effectiveModelId: model,
      effectiveReasoningEffort: _string(settings['reasoning_effort']),
    );
  }
}

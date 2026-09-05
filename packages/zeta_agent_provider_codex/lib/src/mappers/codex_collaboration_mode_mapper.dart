part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 将 `collaborationMode/list` 的实验协议响应宽容映射为中立领域目录。
class _CodexCollaborationModeMapper {
  _CodexCollaborationModeMapping catalogFromResult(Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'collaborationMode/list response must be an object',
      );
    }
    final response = _map(value);
    final data = response['data'];
    if (data is! List) {
      throw const FormatException(
        'collaborationMode/list response.data must be an array',
      );
    }

    final presets = <AgentConversationModePreset>[];
    final seenModeIds = <String>{};
    var invalidEntryCount = 0;
    var duplicateEntryCount = 0;
    for (final value in data) {
      final preset = _presetFromEntry(value);
      if (preset == null) {
        invalidEntryCount += 1;
        continue;
      }
      if (!seenModeIds.add(preset.id.rawValue)) {
        duplicateEntryCount += 1;
        continue;
      }
      presets.add(preset);
    }

    return _CodexCollaborationModeMapping(
      catalog: AgentConversationModeCatalog(presets: presets),
      invalidEntryCount: invalidEntryCount,
      duplicateEntryCount: duplicateEntryCount,
    );
  }

  AgentConversationModePreset? _presetFromEntry(Object? value) {
    if (value is! Map) {
      return null;
    }
    final entry = _map(value);
    final displayName = _trimmedString(entry['name']);
    final modeId = AgentConversationModeId.tryFromRaw(entry['mode']);
    if (displayName == null || modeId == null) {
      return null;
    }

    final modelValue = entry['model'];
    final model = _trimmedString(modelValue);
    if (modelValue != null && model == null) {
      return null;
    }
    final effortValue = entry['reasoning_effort'];
    final effort = _trimmedString(effortValue);
    if (effortValue != null && effort == null) {
      return null;
    }

    return AgentConversationModePreset(
      id: modeId,
      displayName: displayName,
      suggestedModelId: model,
      suggestedReasoningEffort: effort,
    );
  }

  String? _trimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

final class _CodexCollaborationModeMapping {
  const _CodexCollaborationModeMapping({
    required this.catalog,
    required this.invalidEntryCount,
    required this.duplicateEntryCount,
  });

  final AgentConversationModeCatalog catalog;
  final int invalidEntryCount;
  final int duplicateEntryCount;
}

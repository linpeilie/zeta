import 'package:zeta/src/features/agent/domain/agent_skill_models.dart';

/// 将 Grok ACP `_x.ai/skills/list` 响应宽容映射为中立 [AgentSkillsCatalog]。
///
/// 响应可能带 ACP `ExtMethodResult` envelope（`{"result": {"skills": [...]}}`），
/// 也可能直接是 `{"skills": [...]}`；两者都容忍。
class GrokSkillsMapping {
  const GrokSkillsMapping({
    required this.entry,
    required this.invalidEntryCount,
    required this.droppedSkillCount,
  });

  /// 该 cwd 下的 skill 目录条目。
  final AgentSkillsCatalogEntry entry;

  /// 无法解析的响应/条目数。
  final int invalidEntryCount;

  /// 因缺少关键字段或处于禁用态而被丢弃的 skill 数。
  final int droppedSkillCount;
}

/// 将 `_x.ai/skills/list` 的单个 cwd 响应映射为一个目录条目。
GrokSkillsMapping mapGrokSkillsEntry(Object? raw, {required String cwd}) {
  final response = _asStringKeyedMap(raw);
  if (response == null) {
    return GrokSkillsMapping(
      entry: AgentSkillsCatalogEntry(
        cwd: cwd,
        skills: const <AgentSkillMetadata>[],
      ),
      invalidEntryCount: 1,
      droppedSkillCount: 0,
    );
  }

  // ACP `ExtMethodResult` 会把数据包进 `result`；宽容取内层，否则用外层本身。
  final innerMap = _asStringKeyedMap(response['result']) ?? response;
  final skillsValue = innerMap['skills'];
  if (skillsValue is! List) {
    return GrokSkillsMapping(
      entry: AgentSkillsCatalogEntry(
        cwd: cwd,
        skills: const <AgentSkillMetadata>[],
      ),
      invalidEntryCount: 1,
      droppedSkillCount: 0,
    );
  }

  final skills = <AgentSkillMetadata>[];
  var droppedSkillCount = 0;
  for (final value in skillsValue) {
    final skill = _skillFromValue(value);
    if (skill == null) {
      droppedSkillCount += 1;
      continue;
    }
    if (!skill.enabled) {
      droppedSkillCount += 1;
      continue;
    }
    skills.add(skill);
  }

  return GrokSkillsMapping(
    entry: AgentSkillsCatalogEntry(cwd: cwd, skills: skills),
    invalidEntryCount: 0,
    droppedSkillCount: droppedSkillCount,
  );
}

AgentSkillMetadata? _skillFromValue(Object? value) {
  final skill = _asStringKeyedMap(value);
  if (skill == null) {
    return null;
  }
  final name = _trimmedString(skill['name']);
  final path = _trimmedString(skill['path']);
  if (name == null || path == null) {
    return null;
  }
  return AgentSkillMetadata(
    name: name,
    path: path,
    description: _trimmedString(skill['description']) ?? '',
    enabled: skill['enabled'] is bool ? skill['enabled'] as bool : true,
    displayName:
        _trimmedString(skill['displayName']) ??
        _trimmedString(skill['display_name']),
    shortDescription:
        _trimmedString(skill['shortDescription']) ??
        _trimmedString(skill['short_description']),
    scope: _trimmedString(skill['scope']),
  );
}

String? _trimmedString(Object? value) {
  if (value is! String) {
    return null;
  }
  final normalized = value.trim();
  return normalized.isEmpty ? null : normalized;
}

Map<String, Object?>? _asStringKeyedMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

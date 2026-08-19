part of '../datasources/app_server/codex_app_server_agent_provider.dart';

/// 将 `skills/list` 响应宽容映射为中立 [AgentSkillsCatalog]。
class _CodexSkillsMapper {
  _CodexSkillsMapping catalogFromResult(
    Object? value, {
    bool includeDisabled = false,
  }) {
    if (value is! Map) {
      throw const FormatException('skills/list response must be an object');
    }
    final response = _map(value);
    final data = response['data'];
    if (data is! List) {
      throw const FormatException('skills/list response.data must be an array');
    }

    final entries = <AgentSkillsCatalogEntry>[];
    var invalidEntryCount = 0;
    var droppedSkillCount = 0;
    for (final value in data) {
      final mapped = _entryFromValue(value, includeDisabled: includeDisabled);
      if (mapped == null) {
        invalidEntryCount += 1;
        continue;
      }
      droppedSkillCount += mapped.droppedSkillCount;
      entries.add(mapped.entry);
    }

    return _CodexSkillsMapping(
      catalog: AgentSkillsCatalog(entries: entries),
      invalidEntryCount: invalidEntryCount,
      droppedSkillCount: droppedSkillCount,
    );
  }

  _CodexSkillsEntryMapping? _entryFromValue(
    Object? value, {
    required bool includeDisabled,
  }) {
    if (value is! Map) {
      return null;
    }
    final entry = _map(value);
    final cwd = _trimmedString(entry['cwd']) ?? '';
    final skillsValue = entry['skills'];
    if (skillsValue is! List) {
      return null;
    }

    final skills = <AgentSkillMetadata>[];
    var droppedSkillCount = 0;
    final diagnostics = <String>[];
    for (final skillValue in skillsValue) {
      final skill = _skillFromValue(skillValue);
      if (skill == null) {
        droppedSkillCount += 1;
        continue;
      }
      if (!includeDisabled && !skill.enabled) {
        droppedSkillCount += 1;
        continue;
      }
      skills.add(skill);
    }

    final errorsValue = entry['errors'];
    if (errorsValue is List) {
      for (final errorValue in errorsValue) {
        final message = _skillErrorMessage(errorValue);
        if (message != null) {
          diagnostics.add(message);
        }
      }
    }

    return _CodexSkillsEntryMapping(
      entry: AgentSkillsCatalogEntry(
        cwd: cwd,
        skills: skills,
        errors: diagnostics,
      ),
      droppedSkillCount: droppedSkillCount,
    );
  }

  AgentSkillMetadata? _skillFromValue(Object? value) {
    if (value is! Map) {
      return null;
    }
    final skill = _map(value);
    final name = _trimmedString(skill['name']);
    final path = _absolutePath(skill['path']);
    if (name == null || path == null) {
      return null;
    }
    final description = _trimmedString(skill['description']) ?? '';
    final enabled = skill['enabled'] is! bool || skill['enabled']! as bool;
    final interface = _map(skill['interface']);
    return AgentSkillMetadata(
      name: name,
      path: path,
      description: description,
      enabled: enabled,
      displayName: _trimmedString(interface['displayName']),
      shortDescription:
          _trimmedString(interface['shortDescription']) ??
          _trimmedString(skill['shortDescription']),
      defaultPrompt: _trimmedString(interface['defaultPrompt']),
      scope: _trimmedString(skill['scope']),
    );
  }

  String? _skillErrorMessage(Object? value) {
    if (value is String) {
      return _trimmedString(value);
    }
    if (value is! Map) {
      return null;
    }
    final error = _map(value);
    return _trimmedString(error['message']) ??
        _trimmedString(error['summary']) ??
        _trimmedString(error['error']);
  }

  String? _absolutePath(Object? value) {
    if (value is String) {
      return _trimmedString(value);
    }
    if (value is! Map) {
      return null;
    }
    final map = _map(value);
    return _trimmedString(map['path']) ??
        _trimmedString(map['absolutePath']) ??
        _trimmedString(map['value']);
  }

  String? _trimmedString(Object? value) {
    if (value is! String) {
      return null;
    }
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }
}

final class _CodexSkillsMapping {
  const _CodexSkillsMapping({
    required this.catalog,
    required this.invalidEntryCount,
    required this.droppedSkillCount,
  });

  final AgentSkillsCatalog catalog;
  final int invalidEntryCount;
  final int droppedSkillCount;
}

final class _CodexSkillsEntryMapping {
  const _CodexSkillsEntryMapping({
    required this.entry,
    required this.droppedSkillCount,
  });

  final AgentSkillsCatalogEntry entry;
  final int droppedSkillCount;
}

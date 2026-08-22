import 'package:flutter/foundation.dart';

/// Skill 目录与元数据的中立领域模型。
///
/// 只保留 UI / 发送所需的白名单字段，不透传 Provider 原始 payload。

/// 单条 Skill 元数据。
@immutable
final class AgentSkillMetadata {
  const AgentSkillMetadata({
    required this.name,
    required this.path,
    required this.description,
    required this.enabled,
    this.displayName,
    this.shortDescription,
    this.defaultPrompt,
    this.scope,
  });

  /// Skill 稳定标识（协议 `name`，也用于 `$name` marker）。
  final String name;

  /// Skill 定义文件的绝对路径。
  final String path;

  /// 完整描述。
  final String description;

  /// 是否对当前会话可用。
  final bool enabled;

  /// 可选展示名。
  final String? displayName;

  /// 可选短描述。
  final String? shortDescription;

  /// 插入后可预填的默认提示。
  final String? defaultPrompt;

  /// Provider 侧作用域（如 user/repo/system）。
  final String? scope;

  /// Chip / 列表优先展示的标签。
  String get label {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return name;
  }

  @override
  bool operator ==(Object other) =>
      other is AgentSkillMetadata &&
      other.name == name &&
      other.path == path &&
      other.description == description &&
      other.enabled == enabled &&
      other.displayName == displayName &&
      other.shortDescription == shortDescription &&
      other.defaultPrompt == defaultPrompt &&
      other.scope == scope;

  @override
  int get hashCode => Object.hash(
    name,
    path,
    description,
    enabled,
    displayName,
    shortDescription,
    defaultPrompt,
    scope,
  );
}

/// 某一 cwd 下的 Skill 列表快照条目。
@immutable
final class AgentSkillsCatalogEntry {
  AgentSkillsCatalogEntry({
    required this.cwd,
    required Iterable<AgentSkillMetadata> skills,
    Iterable<String> errors = const <String>[],
  }) : skills = List<AgentSkillMetadata>.unmodifiable(skills),
       errors = List<String>.unmodifiable(errors);

  /// 查询时使用的工作目录。
  final String cwd;

  /// 该目录下可用的 skill（通常已过滤禁用项）。
  final List<AgentSkillMetadata> skills;

  /// 加载诊断信息（不阻断整表）。
  final List<String> errors;

  @override
  bool operator ==(Object other) =>
      other is AgentSkillsCatalogEntry &&
      other.cwd == cwd &&
      listEquals(other.skills, skills) &&
      listEquals(other.errors, errors);

  @override
  int get hashCode =>
      Object.hash(cwd, Object.hashAll(skills), Object.hashAll(errors));
}

/// Provider 返回的 Skill 目录快照。
@immutable
final class AgentSkillsCatalog {
  AgentSkillsCatalog({required Iterable<AgentSkillsCatalogEntry> entries})
    : entries = List<AgentSkillsCatalogEntry>.unmodifiable(entries);

  /// 空目录。
  static final empty = AgentSkillsCatalog(
    entries: const <AgentSkillsCatalogEntry>[],
  );

  /// 按 cwd 分组的条目。
  final List<AgentSkillsCatalogEntry> entries;

  /// 展平后的全部 skill（保持条目顺序）。
  List<AgentSkillMetadata> get allSkills => <AgentSkillMetadata>[
    for (final entry in entries) ...entry.skills,
  ];

  /// 按名称/描述过滤启用 skill。
  List<AgentSkillMetadata> query(String rawQuery) {
    final query = rawQuery.trim().toLowerCase();
    final skills = allSkills;
    if (query.isEmpty) {
      return List<AgentSkillMetadata>.unmodifiable(skills);
    }
    return List<AgentSkillMetadata>.unmodifiable(
      skills.where((skill) {
        final parts = <String>[skill.name, skill.description];
        final displayName = skill.displayName;
        if (displayName != null && displayName.isNotEmpty) {
          parts.add(displayName);
        }
        final shortDescription = skill.shortDescription;
        if (shortDescription != null && shortDescription.isNotEmpty) {
          parts.add(shortDescription);
        }
        return parts.join('\n').toLowerCase().contains(query);
      }),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AgentSkillsCatalog && listEquals(other.entries, entries);

  @override
  int get hashCode => Object.hashAll(entries);
}

/// 发送时携带的 skill 引用（不要求完整元数据）。
@immutable
final class AgentSkillRef {
  const AgentSkillRef({
    required this.name,
    required this.path,
    this.displayName,
  });

  final String name;
  final String path;

  /// 可选展示名；Chip / 列表项优先使用，不影响协议 `$name`。
  final String? displayName;

  /// Chip / 列表优先展示的标签（displayName，否则 name）。
  String get label {
    final trimmed = displayName?.trim();
    if (trimmed != null && trimmed.isNotEmpty) {
      return trimmed;
    }
    return name;
  }

  /// 协议文本 marker：`$name`。
  String get marker => '\$$name';

  /// Codex 用户消息中的 markdown 链接形态（Chip tooltip 使用）。
  String get markdownLink => '[$marker]($path)';

  @override
  bool operator ==(Object other) =>
      other is AgentSkillRef &&
      other.name == name &&
      other.path == path &&
      other.displayName == displayName;

  @override
  int get hashCode => Object.hash(name, path, displayName);
}

import 'package:zeta_agent_core/zeta_agent_core.dart';

/// Skill picker 候选：能力关闭时为空，否则按 name / 描述做子串过滤。
///
/// 过滤规则与 [AgentSkillsCatalog.query] 对齐（含 displayName / shortDescription）。
List<AgentSkillMetadata> filterAgentSkillCandidates(
  Iterable<AgentSkillMetadata> skills, {
  required bool canUseSkills,
  String query = '',
}) {
  if (!canUseSkills) {
    return const <AgentSkillMetadata>[];
  }
  return AgentSkillsCatalog(
    entries: [
      AgentSkillsCatalogEntry(
        cwd: '',
        skills: List<AgentSkillMetadata>.unmodifiable(skills),
      ),
    ],
  ).query(query);
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_skill_candidates.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

const _creator = AgentSkillMetadata(
  name: 'skill-creator',
  path: '/a/SKILL.md',
  description: 'Create or update a skill',
  enabled: true,
  displayName: 'Skill Creator',
);

const _triage = AgentSkillMetadata(
  name: 'triage',
  path: '/b/SKILL.md',
  description: 'Triage flaky CI',
  enabled: true,
  shortDescription: 'flaky',
);

void main() {
  group('filterAgentSkillCandidates', () {
    test('能力关闭时始终为空', () {
      expect(
        filterAgentSkillCandidates(
          const [_creator, _triage],
          canUseSkills: false,
          query: 'creator',
        ),
        isEmpty,
      );
    });

    test('空查询返回全部候选', () {
      final result = filterAgentSkillCandidates(
        const [_creator, _triage],
        canUseSkills: true,
        query: '',
      );
      expect(result.map((skill) => skill.name), <String>[
        'skill-creator',
        'triage',
      ]);
    });

    test('按 name / 描述 / displayName / shortDescription 过滤', () {
      expect(
        filterAgentSkillCandidates(
          const [_creator, _triage],
          canUseSkills: true,
          query: 'creator',
        ).single.name,
        'skill-creator',
      );
      expect(
        filterAgentSkillCandidates(
          const [_creator, _triage],
          canUseSkills: true,
          query: 'Skill Creator',
        ).single.name,
        'skill-creator',
      );
      expect(
        filterAgentSkillCandidates(
          const [_creator, _triage],
          canUseSkills: true,
          query: 'flaky',
        ).single.name,
        'triage',
      );
    });

    test('空白查询视为空；无匹配返回空列表', () {
      expect(
        filterAgentSkillCandidates(
          const [_creator],
          canUseSkills: true,
          query: '  ',
        ).single.name,
        'skill-creator',
      );
      expect(
        filterAgentSkillCandidates(
          const [_creator],
          canUseSkills: true,
          query: 'xyz',
        ),
        isEmpty,
      );
    });
  });
}

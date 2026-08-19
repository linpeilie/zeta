import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  const creator = AgentSkillMetadata(
    name: 'skill-creator',
    path: '/skills/skill-creator/SKILL.md',
    description: 'Create or update a skill',
    enabled: true,
    displayName: 'Skill Creator',
  );
  const triage = AgentSkillMetadata(
    name: 'triage',
    path: '/skills/triage/SKILL.md',
    description: 'Triage flaky CI',
    enabled: true,
  );

  test('skill metadata and refs expose presentation-neutral labels', () {
    expect(creator.label, 'Skill Creator');
    expect(triage.label, 'triage');
    const ref = AgentSkillRef(
      name: 'skill-creator',
      path: '/skills/skill-creator/SKILL.md',
      displayName: 'Skill Creator',
    );
    expect(ref.label, 'Skill Creator');
    expect(ref.marker, r'$skill-creator');
    expect(
      ref.markdownLink,
      r'[$skill-creator](/skills/skill-creator/SKILL.md)',
    );
  });

  test('catalog queries immutable entries', () {
    final source = <AgentSkillMetadata>[creator, triage];
    final entry = AgentSkillsCatalogEntry(cwd: '/repo', skills: source);
    source.clear();
    final catalog = AgentSkillsCatalog(
      entries: <AgentSkillsCatalogEntry>[entry],
    );
    expect(catalog.query('creator'), <AgentSkillMetadata>[creator]);
    expect(catalog.query('flaky'), <AgentSkillMetadata>[triage]);
    expect(catalog.allSkills, <AgentSkillMetadata>[creator, triage]);
    expect(() => catalog.allSkills.clear(), throwsUnsupportedError);
    expect(AgentSkillsCatalog.empty.entries, isEmpty);
  });

  test('skill user input preserves the typed reference', () {
    const input = AgentUserInput.skill(
      name: 'skill-creator',
      path: '/skills/skill-creator/SKILL.md',
    );
    expect(input, isA<AgentSkillUserInput>());
    expect((input as AgentSkillUserInput).name, 'skill-creator');
  });
}

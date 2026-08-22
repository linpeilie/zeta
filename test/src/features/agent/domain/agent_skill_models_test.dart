import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_static_capabilities.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentSkillMetadata', () {
    test('prefers displayName for label', () {
      const skill = AgentSkillMetadata(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
        description: 'Create skills',
        enabled: true,
        displayName: 'Skill Creator',
      );

      expect(skill.label, 'Skill Creator');
    });
  });

  group('AgentSkillRef', () {
    test('prefers displayName for label', () {
      const ref = AgentSkillRef(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
        displayName: 'Skill Creator',
      );

      expect(ref.label, 'Skill Creator');
    });

    test('falls back to name when displayName is empty', () {
      const ref = AgentSkillRef(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
        displayName: '  ',
      );

      expect(ref.label, 'skill-creator');
    });

    test('exposes Codex-aligned marker and markdownLink', () {
      const ref = AgentSkillRef(
        name: 'beautify-github-readme',
        path: '/Users/me/.agents/skills/beautify-github-readme/SKILL.md',
        displayName: 'Beautify README',
      );

      expect(ref.marker, r'$beautify-github-readme');
      expect(
        ref.markdownLink,
        r'[$beautify-github-readme](/Users/me/.agents/skills/beautify-github-readme/SKILL.md)',
      );
    });
  });

  group('AgentSkillsCatalog', () {
    test('queries by name and description', () {
      final catalog = AgentSkillsCatalog(
        entries: [
          AgentSkillsCatalogEntry(
            cwd: '/repo',
            skills: const [
              AgentSkillMetadata(
                name: 'skill-creator',
                path: '/a/SKILL.md',
                description: 'Create or update a skill',
                enabled: true,
              ),
              AgentSkillMetadata(
                name: 'triage',
                path: '/b/SKILL.md',
                description: 'Triage flaky CI',
                enabled: true,
              ),
            ],
          ),
        ],
      );

      expect(catalog.query('creator').single.name, 'skill-creator');
      expect(catalog.query('flaky').single.name, 'triage');
      expect(catalog.query('').length, 2);
    });
  });

  group('AgentUserInput.skill', () {
    test('exposes name and path', () {
      const input = AgentUserInput.skill(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
      );

      expect(input, isA<AgentSkillUserInput>());
      final skill = input as AgentSkillUserInput;
      expect(skill.name, 'skill-creator');
      expect(skill.path, '/skills/skill-creator/SKILL.md');
    });
  });

  group('AgentProviderCapabilities.supportsSkillInput', () {
    test('enables Codex and Grok', () {
      expect(
        AgentProviderStaticCapabilities.codexAppServer.supportsSkillInput,
        isTrue,
      );
      expect(
        AgentProviderStaticCapabilities.grokAcp.supportsSkillInput,
        isTrue,
      );
    });
  });
}

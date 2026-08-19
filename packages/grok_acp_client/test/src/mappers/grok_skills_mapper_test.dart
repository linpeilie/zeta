import 'package:grok_acp_client/src/mappers/grok_skills_mapper.dart';
import 'package:test/test.dart';

import '../../testing/fixture_reader.dart';

void main() {
  group('mapGrokSkillsEntry', () {
    test('maps skills/list envelope with snake_case skill fields', () {
      final raw = readFixtureJsonMap('grok/acp/xai_skills_list_response.json');

      final mapping = mapGrokSkillsEntry(raw, cwd: '/repo');

      expect(mapping.invalidEntryCount, 0);
      // pdf 处于禁用态，被 dropped。
      expect(mapping.droppedSkillCount, 1);
      final entry = mapping.entry;
      expect(entry.cwd, '/repo');
      expect(entry.skills, hasLength(3));

      final createSkill = entry.skills[0];
      expect(createSkill.name, 'create-skill');
      expect(createSkill.displayName, 'Create Skill');
      expect(createSkill.shortDescription, 'Scaffold a skill');
      expect(createSkill.description, contains('SKILL.md'));
      expect(createSkill.path, endsWith('create-skill/SKILL.md'));
      expect(createSkill.scope, 'user');
      expect(createSkill.enabled, isTrue);

      final findSession = entry.skills[1];
      expect(findSession.name, 'find-session');
      expect(findSession.scope, 'local');
      expect(findSession.displayName, isNull);

      final planReview = entry.skills[2];
      expect(planReview.name, 'plan-review');
      expect(planReview.displayName, 'Plan Review');
      expect(planReview.shortDescription, 'Review plans');
      expect(planReview.scope, 'plugin');
    });

    test('tolerates bare skills payload without the result envelope', () {
      final mapping = mapGrokSkillsEntry(<String, Object?>{
        'skills': <Object?>[
          <String, Object?>{
            'name': 'bare',
            'path': '/repo/.grok/skills/bare/SKILL.md',
          },
        ],
      }, cwd: '/repo');

      expect(mapping.invalidEntryCount, 0);
      expect(mapping.entry.skills, hasLength(1));
      expect(mapping.entry.skills.single.name, 'bare');
      expect(mapping.entry.skills.single.description, isEmpty);
      expect(mapping.entry.skills.single.enabled, isTrue);
    });

    test('tolerates camelCase display fields as fallback', () {
      final mapping = mapGrokSkillsEntry(<String, Object?>{
        'skills': <Object?>[
          <String, Object?>{
            'name': 'cam',
            'displayName': 'Camel',
            'shortDescription': 'short',
            'path': '/repo/.grok/skills/cam/SKILL.md',
          },
        ],
      }, cwd: '/repo');

      final skill = mapping.entry.skills.single;
      expect(skill.displayName, 'Camel');
      expect(skill.shortDescription, 'short');
    });

    test('drops skills missing name or path', () {
      final mapping = mapGrokSkillsEntry(<String, Object?>{
        'skills': <Object?>[
          <String, Object?>{'name': 'no-path'},
          <String, Object?>{'path': '/repo/x/SKILL.md'},
          'not-a-map',
          <String, Object?>{
            'name': 'ok',
            'path': '/repo/.grok/skills/ok/SKILL.md',
          },
        ],
      }, cwd: '/repo');

      expect(mapping.droppedSkillCount, 3);
      expect(mapping.entry.skills, hasLength(1));
      expect(mapping.entry.skills.single.name, 'ok');
    });

    test('reports invalid payload as empty entry', () {
      final invalid = mapGrokSkillsEntry(null, cwd: '/repo');
      expect(invalid.invalidEntryCount, 1);
      expect(invalid.entry.skills, isEmpty);

      final notObject = mapGrokSkillsEntry('nope', cwd: '/repo');
      expect(notObject.invalidEntryCount, 1);
      expect(notObject.entry.skills, isEmpty);

      final noSkills = mapGrokSkillsEntry(<String, Object?>{
        'result': <String, Object?>{},
      }, cwd: '/repo');
      expect(noSkills.invalidEntryCount, 1);
      expect(noSkills.entry.skills, isEmpty);
    });
  });
}

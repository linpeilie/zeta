import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/composer_document.dart';

void main() {
  group('ComposerDocumentController', () {
    test('inserts skill as sentinel and serializes to \$name', () {
      final controller = ComposerDocumentController();
      controller.text = 'please ';
      controller.selection = const TextSelection.collapsed(offset: 7);
      controller.insertSkill(
        const AgentSkillMetadata(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create skills',
          enabled: true,
          displayName: 'Skill Creator',
        ),
      );

      expect(controller.text.contains(kComposerSkillSentinel), isTrue);
      expect(controller.skills.single.name, 'skill-creator');
      expect(controller.skills.single.label, 'Skill Creator');

      final serialized = controller.serialize();
      expect(serialized.text, contains(r'$skill-creator'));
      expect(serialized.skills.single.path, '/skills/skill-creator/SKILL.md');
    });

    test('replaces active \$query when inserting skill', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: r'$ski',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(controller.activeSkillQuery, 'ski');

      controller.insertSkill(
        const AgentSkillMetadata(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create skills',
          enabled: true,
        ),
      );

      expect(controller.text.contains(r'$ski'), isFalse);
      expect(controller.skills, hasLength(1));
    });

    test('removes skill when sentinel is deleted', () {
      final controller = ComposerDocumentController();
      controller.insertSkill(
        const AgentSkillMetadata(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create skills',
          enabled: true,
        ),
      );
      expect(controller.skills, hasLength(1));

      controller.value = TextEditingValue.empty;
      expect(controller.skills, isEmpty);
    });

    test('deduplicates skills by path on serialize', () {
      final controller = ComposerDocumentController();
      const skill = AgentSkillMetadata(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
        description: 'Create skills',
        enabled: true,
      );
      controller.insertSkill(skill);
      // 在 token 后追加纯文本时保留 sentinel，再插入第二个同 path skill。
      final withTail = '${controller.text} and again ';
      controller.value = TextEditingValue(
        text: withTail,
        selection: TextSelection.collapsed(offset: withTail.length),
      );
      controller.insertSkill(skill);

      final serialized = controller.serialize();
      expect(serialized.skills, hasLength(1));
      expect(r'$skill-creator'.allMatches(serialized.text).length, 2);
    });
  });
}

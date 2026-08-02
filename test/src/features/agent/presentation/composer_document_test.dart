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

    test('detects active slash query only after start or whitespace', () {
      final controller = ComposerDocumentController();

      controller.value = const TextEditingValue(
        text: '/',
        selection: TextSelection.collapsed(offset: 1),
      );
      expect(controller.activeSlashQuery, '');

      controller.value = const TextEditingValue(
        text: '/pla',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(controller.activeSlashQuery, 'pla');

      controller.value = const TextEditingValue(
        text: 'hello /pl',
        selection: TextSelection.collapsed(offset: 9),
      );
      expect(controller.activeSlashQuery, 'pl');

      controller.value = const TextEditingValue(
        text: 'hello/',
        selection: TextSelection.collapsed(offset: 6),
      );
      expect(controller.activeSlashQuery, isNull);

      controller.value = const TextEditingValue(
        text: '/Users/foo',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(controller.activeSlashQuery, isNull);
    });

    test('consumes active slash query without inserting content', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: 'note /plan more',
        selection: TextSelection.collapsed(offset: 10),
      );
      expect(controller.activeSlashQuery, 'plan');

      controller.consumeActiveSlashQuery();
      expect(controller.text, 'note  more');
      expect(controller.selection.baseOffset, 5);
      expect(controller.activeSlashQuery, isNull);
    });

    test('replaces active /query when inserting skill', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: '/ski',
        selection: TextSelection.collapsed(offset: 4),
      );
      expect(controller.activeSlashQuery, 'ski');

      controller.insertSkill(
        const AgentSkillMetadata(
          name: 'skill-creator',
          path: '/skills/skill-creator/SKILL.md',
          description: 'Create skills',
          enabled: true,
        ),
      );

      expect(controller.text.contains('/ski'), isFalse);
      expect(controller.skills, hasLength(1));
      expect(controller.activeSlashQuery, isNull);
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

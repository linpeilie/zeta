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

  group('detectMentionToken', () {
    test('基础 @token', () {
      final token = detectMentionToken('@foo', 4);
      expect(token, isNotNull);
      expect(token!.start, 0);
      expect(token.end, 4);
      expect(token.query, 'foo');
    });

    test('带前缀文本', () {
      final token = detectMentionToken('hello @bar', 10);
      expect(token!.start, 6);
      expect(token.end, 10);
      expect(token.query, 'bar');
    });

    test('光标位于 token 中间', () {
      final token = detectMentionToken('@foo/bar', 5);
      expect(token!.start, 0);
      expect(token.end, 8);
      expect(token.query, 'foo/');
    });

    test('刚输入 @ 时 query 为空', () {
      final token = detectMentionToken('@', 1);
      expect(token, isNotNull);
      expect(token!.query, '');
    });

    test('email 守卫：@ 前为字母/数字/下划线时不触发', () {
      expect(detectMentionToken('user@example', 12), isNull);
      expect(detectMentionToken('test_@foo', 9), isNull);
    });

    test('光标越过 token 结束时不触发', () {
      expect(detectMentionToken('@foo bar', 5), isNull);
      expect(detectMentionToken('@foo bar', 8), isNull);
    });

    test('token 以逗号/分号结束', () {
      final comma = detectMentionToken('@foo,@bar', 4);
      expect(comma!.start, 0);
      expect(comma.end, 4);
      expect(comma.query, 'foo');
      final semicolon = detectMentionToken('@foo;rest', 4);
      expect(semicolon!.start, 0);
      expect(semicolon.end, 4);
      expect(semicolon.query, 'foo');
    });

    test('空文本 / 光标为 0 时不触发', () {
      expect(detectMentionToken('', 0), isNull);
      expect(detectMentionToken('@foo', 0), isNull);
    });

    test('多个 @ 取光标前最右侧', () {
      final token = detectMentionToken('@first @second', 14);
      expect(token!.start, 7);
      expect(token.end, 14);
      expect(token.query, 'second');
    });

    test('@ 前为特殊字符时触发', () {
      expect(detectMentionToken('(@foo', 5), isNotNull);
      expect(detectMentionToken(' @foo', 5), isNotNull);
      expect(detectMentionToken(',@foo', 5), isNotNull);
    });

    test('光标在 token 末尾返回完整 query', () {
      final token = detectMentionToken('@foo/bar', 8);
      expect(token!.query, 'foo/bar');
    });
  });

  group('activeMentionQuery / activeMentionRange', () {
    void setValue(
      ComposerDocumentController controller,
      String text,
      int cursor,
    ) {
      controller.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: cursor),
      );
    }

    test('查询与范围匹配 @token', () {
      final controller = ComposerDocumentController();
      setValue(controller, '@lib/ma', 7);
      expect(controller.activeMentionQuery, 'lib/ma');
      expect(controller.activeMentionRange, const TextRange(start: 0, end: 7));
    });

    test('非折叠选区返回 null', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: '@foo bar',
        selection: TextSelection(baseOffset: 1, extentOffset: 3),
      );
      expect(controller.activeMentionQuery, isNull);
      expect(controller.activeMentionRange, isNull);
    });

    test('光标越过 token 时返回 null', () {
      final controller = ComposerDocumentController();
      setValue(controller, '@foo bar', 8);
      expect(controller.activeMentionQuery, isNull);
      expect(controller.activeMentionRange, isNull);
    });
  });

  group('ComposerDocumentController insertMention', () {
    test('inserts mention as sentinel and serializes to @name', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: 'please ',
        selection: TextSelection.collapsed(offset: 7),
      );
      controller.insertMention(name: 'main.dart', path: '/repo/lib/main.dart');

      expect(controller.text.contains(kComposerSkillSentinel), isTrue);
      expect(controller.mentions.single.name, 'main.dart');
      expect(controller.mentions.single.path, '/repo/lib/main.dart');

      final serialized = controller.serialize();
      expect(serialized.text, contains('@main.dart'));
      expect(serialized.mentions.single.path, '/repo/lib/main.dart');
    });

    test('replaces active @query when inserting mention', () {
      final controller = ComposerDocumentController();
      controller.value = const TextEditingValue(
        text: '@lib/ma',
        selection: TextSelection.collapsed(offset: 7),
      );
      expect(controller.activeMentionQuery, 'lib/ma');

      controller.insertMention(name: 'main.dart', path: '/repo/lib/main.dart');

      expect(controller.text.contains('@lib/ma'), isFalse);
      expect(controller.mentions, hasLength(1));
      expect(controller.serialize().text, '@main.dart');
    });

    test('removes mention when sentinel is deleted', () {
      final controller = ComposerDocumentController();
      controller.insertMention(name: 'main.dart', path: '/repo/lib/main.dart');
      expect(controller.mentions, hasLength(1));

      controller.value = TextEditingValue.empty;
      expect(controller.mentions, isEmpty);
      expect(controller.hasContent, isFalse);
    });

    test('serializes mixed skills and mentions with dedup', () {
      final controller = ComposerDocumentController();
      const skill = AgentSkillMetadata(
        name: 'skill-creator',
        path: '/skills/skill-creator/SKILL.md',
        description: 'Create skills',
        enabled: true,
      );
      controller.insertSkill(skill);
      // 在 skill token 后追加文本与 @query，再插入 mention。
      final withTail = '${controller.text} and @ma';
      controller.value = TextEditingValue(
        text: withTail,
        selection: TextSelection.collapsed(offset: withTail.length),
      );
      controller.insertMention(name: 'main.dart', path: '/repo/lib/main.dart');

      final serialized = controller.serialize();
      expect(serialized.text, contains(r'$skill-creator'));
      expect(serialized.text, contains('@main.dart'));
      expect(serialized.skills.single.path, '/skills/skill-creator/SKILL.md');
      expect(serialized.mentions.single.path, '/repo/lib/main.dart');
    });

    test('hasContent true for only mention', () {
      final controller = ComposerDocumentController();
      expect(controller.hasContent, isFalse);

      controller.insertMention(name: 'main.dart', path: '/repo/lib/main.dart');
      expect(controller.hasContent, isTrue);
    });
  });
}

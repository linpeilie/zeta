import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';

void main() {
  group('ClaudeCodePermissionModeCodec', () {
    test('four optionIds round-trip with CLI wire values', () {
      const pairs = <(ClaudeCodePermissionMode, String, String)>[
        (
          ClaudeCodePermissionMode.ask,
          ClaudeCodePermissionModeCodec.optionAsk,
          ClaudeCodePermissionModeCodec.wireDefault,
        ),
        (
          ClaudeCodePermissionMode.acceptEdits,
          ClaudeCodePermissionModeCodec.optionAcceptEdits,
          ClaudeCodePermissionModeCodec.wireAcceptEdits,
        ),
        (
          ClaudeCodePermissionMode.plan,
          ClaudeCodePermissionModeCodec.optionPlan,
          ClaudeCodePermissionModeCodec.wirePlan,
        ),
        (
          ClaudeCodePermissionMode.bypass,
          ClaudeCodePermissionModeCodec.optionBypass,
          ClaudeCodePermissionModeCodec.wireBypassPermissions,
        ),
      ];

      for (final (mode, optionId, wire) in pairs) {
        expect(ClaudeCodePermissionModeCodec.optionId(mode), optionId);
        expect(ClaudeCodePermissionModeCodec.toCliPermissionMode(mode), wire);
        expect(ClaudeCodePermissionModeCodec.parseOptionId(optionId), mode);
        expect(
          ClaudeCodePermissionModeCodec.parseCliPermissionMode(wire),
          mode,
        );
        // 双向字符串往返
        expect(
          ClaudeCodePermissionModeCodec.optionIdToCliPermissionMode(optionId),
          wire,
        );
        expect(
          ClaudeCodePermissionModeCodec.cliPermissionModeToOptionId(wire),
          optionId,
        );
      }
    });

    test('unknown and empty values fail-closed to :ask not :bypass', () {
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId(null),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId(''),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId('  '),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId(':unknown'),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId('garbage'),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode(null),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode(''),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode('not-a-mode'),
        ClaudeCodePermissionMode.ask,
      );
      // 关键：未知值绝不能落到 bypass
      expect(
        ClaudeCodePermissionModeCodec.optionIdToCliPermissionMode('???'),
        ClaudeCodePermissionModeCodec.wireDefault,
      );
      expect(
        ClaudeCodePermissionModeCodec.cliPermissionModeToOptionId('???'),
        ClaudeCodePermissionModeCodec.optionAsk,
      );
      expect(
        ClaudeCodePermissionModeCodec.optionIdToCliPermissionMode('???'),
        isNot(ClaudeCodePermissionModeCodec.wireBypassPermissions),
      );
    });

    test('accepts common CLI and option aliases', () {
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode('default'),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode('acceptEdits'),
        ClaudeCodePermissionMode.acceptEdits,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode('accept-edits'),
        ClaudeCodePermissionMode.acceptEdits,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseCliPermissionMode(
          'bypassPermissions',
        ),
        ClaudeCodePermissionMode.bypass,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId('ask'),
        ClaudeCodePermissionMode.ask,
      );
      expect(
        ClaudeCodePermissionModeCodec.parseOptionId('accept_edits'),
        ClaudeCodePermissionMode.acceptEdits,
      );
    });

    test('catalog exposes four options with default :ask', () {
      final catalog = ClaudeCodePermissionModeCodec.catalog();
      expect(catalog.defaultOptionId, ClaudeCodePermissionModeCodec.optionAsk);
      expect(catalog.options, hasLength(4));
      expect(catalog.options.map((o) => o.id).toList(), <String>[
        ClaudeCodePermissionModeCodec.optionAsk,
        ClaudeCodePermissionModeCodec.optionAcceptEdits,
        ClaudeCodePermissionModeCodec.optionPlan,
        ClaudeCodePermissionModeCodec.optionBypass,
      ]);
      for (final option in catalog.options) {
        expect(option.allowed, isTrue);
        expect(option.label, isNotEmpty);
        expect(catalog.optionById(option.id), option);
      }
      expect(
        catalog
            .optionById(ClaudeCodePermissionModeCodec.optionPlan)
            ?.planningOnly,
        isTrue,
      );
      expect(
        catalog
            .optionById(ClaudeCodePermissionModeCodec.optionAsk)
            ?.planningOnly,
        isFalse,
      );
      expect(
        catalog
            .optionById(ClaudeCodePermissionModeCodec.optionAcceptEdits)
            ?.planningOnly,
        isFalse,
      );
      expect(
        catalog
            .optionById(ClaudeCodePermissionModeCodec.optionBypass)
            ?.planningOnly,
        isFalse,
      );
    });
  });
}

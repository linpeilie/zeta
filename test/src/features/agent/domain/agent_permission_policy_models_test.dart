import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentPermissionOption', () {
    test('equality and hashCode use value fields', () {
      const a = AgentPermissionOption(
        id: 'ask',
        label: 'Ask',
        description: 'Prompt first',
        allowed: true,
      );
      const b = AgentPermissionOption(
        id: 'ask',
        label: 'Ask',
        description: 'Prompt first',
        allowed: true,
      );
      const c = AgentPermissionOption(
        id: 'auto',
        label: 'Auto',
        allowed: false,
      );

      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
      expect(a.planningOnly, isFalse);
    });

    test('planningOnly defaults to false and participates in equality', () {
      const omitted = AgentPermissionOption(id: 'ask', label: 'Ask');
      const explicitFalse = AgentPermissionOption(
        id: 'ask',
        label: 'Ask',
        planningOnly: false,
      );
      const planning = AgentPermissionOption(
        id: 'ask',
        label: 'Ask',
        planningOnly: true,
      );

      expect(omitted.planningOnly, isFalse);
      expect(omitted, equals(explicitFalse));
      expect(omitted.hashCode, explicitFalse.hashCode);
      expect(omitted, isNot(equals(planning)));
      expect(planning.planningOnly, isTrue);
    });
  });

  group('AgentPermissionCatalog', () {
    test('exposes unmodifiable options and default option id', () {
      final catalog = AgentPermissionCatalog(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
          AgentPermissionOption(id: 'auto', label: 'Auto'),
        ],
        defaultOptionId: 'ask',
      );

      expect(catalog.defaultOptionId, 'ask');
      expect(catalog.options.map((o) => o.id), <String>['ask', 'auto']);
      expect(catalog.optionById('auto')?.label, 'Auto');
      expect(catalog.optionById('missing'), isNull);
      expect(
        () => catalog.options.add(
          const AgentPermissionOption(id: 'x', label: 'X'),
        ),
        throwsUnsupportedError,
      );
    });

    test('equality compares default and ordered options', () {
      final left = AgentPermissionCatalog(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
        ],
        defaultOptionId: 'ask',
      );
      final right = AgentPermissionCatalog(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
        ],
        defaultOptionId: 'ask',
      );
      final differentDefault = AgentPermissionCatalog(
        options: const <AgentPermissionOption>[
          AgentPermissionOption(id: 'ask', label: 'Ask'),
        ],
        defaultOptionId: 'other',
      );

      expect(left, equals(right));
      expect(left, isNot(equals(differentDefault)));
    });
  });

  group('AgentPermissionSelection', () {
    test('is optionId-only value object', () {
      const a = AgentPermissionSelection(optionId: 'team-safe');
      const b = AgentPermissionSelection(optionId: 'team-safe');
      const c = AgentPermissionSelection(optionId: 'ask');

      expect(a.optionId, 'team-safe');
      expect(a, equals(b));
      expect(a.hashCode, b.hashCode);
      expect(a, isNot(equals(c)));
    });
  });

  group('AgentPermissionApplyResult', () {
    test('carries normalized selection, scope and warning', () {
      const result = AgentPermissionApplyResult(
        normalizedSelection: AgentPermissionSelection(optionId: 'ask'),
        scope: AgentPermissionApplyScope.nextSession,
        warning: 'Takes effect next session',
      );

      expect(result.normalizedSelection.optionId, 'ask');
      expect(result.scope, AgentPermissionApplyScope.nextSession);
      expect(result.warning, 'Takes effect next session');
      expect(
        result,
        equals(
          const AgentPermissionApplyResult(
            normalizedSelection: AgentPermissionSelection(optionId: 'ask'),
            scope: AgentPermissionApplyScope.nextSession,
            warning: 'Takes effect next session',
          ),
        ),
      );
    });
  });
}

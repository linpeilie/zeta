import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CursorRetirementPolicy', () {
    test('falls back in memory without changing legacy settings', () {
      final settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig.defaultGrok,
          AgentProviderConfig.defaultCursor.copyWith(
            enabled: true,
            extra: const <String, Object?>{'legacyMarker': 'keep-me'},
          ),
        ],
        activeProviderId: cursorAgentProviderId,
      );
      final before = settings.toJson();

      final resolution = CursorRetirementPolicy.resolve(settings);

      expect(resolution.effectiveProvider.id, defaultAgentProviderId);
      expect(resolution.hasRuntimeProvider, isTrue);
      expect(resolution.unavailableReason, contains('已软下线'));
      expect(resolution.unavailableReason, contains('Codex CLI'));
      expect(settings.toJson(), before);
    });

    test('returns a stable unavailable state when no provider is enabled', () {
      final settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex.copyWith(enabled: false),
          AgentProviderConfig.defaultGrok.copyWith(enabled: false),
          AgentProviderConfig.defaultCursor.copyWith(enabled: true),
        ],
        activeProviderId: cursorAgentProviderId,
      );

      final first = CursorRetirementPolicy.resolve(settings);
      final second = CursorRetirementPolicy.resolve(settings);

      expect(first.hasRuntimeProvider, isFalse);
      expect(second.hasRuntimeProvider, isFalse);
      expect(first.effectiveProvider.enabled, isFalse);
      expect(first.unavailableReason, contains('没有已启用'));
      expect(second.unavailableReason, first.unavailableReason);
    });

    test('filters Cursor by id or runtime kind from product catalogs', () {
      final renamedCursor = AgentProviderConfig.defaultCursor.copyWith(
        id: 'legacy-cursor-alias',
        displayName: 'Legacy alias',
        enabled: true,
      );

      final providers =
          CursorRetirementPolicy.supportedProviders(<AgentProviderConfig>[
            AgentProviderConfig.defaultCodex,
            AgentProviderConfig.defaultCursor,
            renamedCursor,
            AgentProviderConfig.defaultGrok,
          ]);

      expect(providers.map((provider) => provider.id), <String>[
        defaultAgentProviderId,
        grokAgentProviderId,
      ]);
    });
  });
}

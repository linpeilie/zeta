import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentProviderConfigStore', () {
    test('loads the default Codex provider when storage is empty', () async {
      final store = CallbackAgentProviderConfigStore(
        loadJson: () async => null,
        saveJson: (_) async {},
      );

      final settings = await store.load();

      expect(settings.activeProvider.id, defaultAgentProviderId);
      expect(settings.activeProvider.command, 'codex');
      expect(settings.activeProvider.arguments, <String>[
        'app-server',
        '--stdio',
      ]);
    });

    test('saves provider settings as versioned JSON', () async {
      String? saved;
      final store = CallbackAgentProviderConfigStore(
        loadJson: () async => saved,
        saveJson: (value) async {
          saved = value;
        },
      );
      const settings = AgentProviderSettings(
        providers: <AgentProviderConfig>[
          AgentProviderConfig.defaultCodex,
          AgentProviderConfig(
            id: 'claude',
            displayName: 'Claude Code',
            kind: AgentProviderKind.claudeCode,
            command: 'claude',
          ),
        ],
        activeProviderId: 'claude',
      );

      await store.save(settings);
      final raw = jsonDecode(saved!) as Map<String, Object?>;

      expect(raw['version'], 1);
      expect(raw['activeProviderId'], 'claude');
      expect(await store.load(), isA<AgentProviderSettings>());
      expect((await store.load()).activeProvider.id, 'claude');
    });
  });
}

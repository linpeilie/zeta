import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AcpSessionConfigMapper', () {
    const mapper = AcpSessionConfigMapper();

    test('prefers config options and decodes select and boolean values', () {
      final snapshot = mapper.mapSessionSetup(<String, Object?>{
        'configOptions': <Object?>[
          <String, Object?>{
            'id': 'model',
            'name': 'Model',
            'category': 'model',
            'type': 'select',
            'currentValue': 'fast',
            'options': <Object?>[
              <String, Object?>{'value': 'fast', 'name': 'Fast'},
            ],
          },
          <String, Object?>{
            'id': 'brave',
            'name': 'Brave mode',
            'type': 'boolean',
            'currentValue': true,
          },
        ],
        'modes': <String, Object?>{
          'currentModeId': 'ask',
          'availableModes': <Object?>[],
        },
      });

      expect(snapshot.usesLegacyModes, isFalse);
      expect(snapshot.options, hasLength(2));
      expect(snapshot.options.first.category, 'model');
      expect(snapshot.options.first.values.single.id, 'fast');
      expect(snapshot.options.last.kind, AgentSessionConfigOptionKind.boolean);
      expect(snapshot.options.last.currentValue, isTrue);
    });

    test('falls back to legacy modes and applies current mode updates', () {
      final snapshot = mapper.mapSessionSetup(<String, Object?>{
        'modes': <String, Object?>{
          'currentModeId': 'ask',
          'availableModes': <Object?>[
            <String, Object?>{
              'id': 'ask',
              'name': 'Ask',
              'description': 'Read-only guidance',
            },
            <String, Object?>{'id': 'agent', 'name': 'Agent'},
          ],
        },
      });
      final updated = mapper.applyCurrentMode(snapshot.options, 'agent');

      expect(snapshot.usesLegacyModes, isTrue);
      expect(snapshot.options.single.category, 'mode');
      expect(updated.single.currentValue, 'agent');
      expect(updated.single.values.map((item) => item.id), <Object>[
        'ask',
        'agent',
      ]);
    });

    test('distinguishes missing config list from an empty list', () {
      expect(mapper.tryMapConfigOptions(null), isNull);
      expect(mapper.tryMapConfigOptions(const <Object?>[]), isEmpty);
    });
  });
}

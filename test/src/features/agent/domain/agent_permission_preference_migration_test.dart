import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentPermissionPreferenceMigration', () {
    group('Codex', () {
      test('profile id wins over approval/sandbox', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedPermissionProfileId: 'team-safe',
            selectedApprovalPolicy: 'never',
            selectedSandboxPolicy: 'dangerFullAccess',
          ),
          'team-safe',
        );
      });

      test('built-in option id is kept as opaque id', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedPermissionOptionId: ':workspace',
          ),
          ':workspace',
        );
      });

      test('legacy approval/sandbox maps to built-in option', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedApprovalPolicy: 'never',
            selectedSandboxPolicy: 'dangerFullAccess',
          ),
          ':danger-full-access',
        );
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedApprovalPolicy: 'on-request',
            selectedSandboxPolicy: 'readOnly',
          ),
          ':read-only',
        );
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedApprovalPolicy: 'on-request',
            selectedSandboxPolicy: 'workspaceWrite',
          ),
          ':workspace',
        );
      });

      test('custom profile without colon is preserved', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'codexAppServer',
            selectedPermissionProfileId: 'team-safe',
          ),
          'team-safe',
        );
      });
    });

    group('Grok (acp)', () {
      test('selectedPermissionOptionId auto is kept', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'acp',
            selectedPermissionOptionId: 'auto',
          ),
          'auto',
        );
      });

      test('legacy selectedPermissionMode default migrates to ask', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'acp',
            selectedPermissionMode: 'default',
          ),
          'ask',
        );
      });

      test('empty and unknown modes fail-closed to ask', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'acp',
            selectedPermissionMode: '',
          ),
          'ask',
        );
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'acp',
            selectedPermissionOptionId: 'not-a-mode',
          ),
          'ask',
        );
      });

      test('missing fields stay null', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(kindName: 'acp'),
          isNull,
        );
      });
    });

    group('unknown provider', () {
      test('only accepts generic optionId', () {
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'claudeCode',
            selectedPermissionOptionId: 'custom',
            selectedPermissionProfileId: ':workspace',
            selectedApprovalPolicy: 'never',
          ),
          'custom',
        );
        expect(
          AgentPermissionPreferenceMigration.resolveOptionId(
            kindName: 'claudeCode',
            selectedPermissionProfileId: 'ignored',
          ),
          isNull,
        );
      });
    });
  });

  group('AgentProviderConfig V2 persistence', () {
    test('V1 Codex built-in and custom migrate to optionId only', () {
      final builtIn = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedApprovalPolicy': 'never',
        'selectedSandboxPolicy': 'dangerFullAccess',
        'enabled': true,
      });
      expect(builtIn, isNotNull);
      expect(builtIn!.selectedPermissionOptionId, ':danger-full-access');

      final custom = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedPermissionProfileId': 'team-safe',
        'selectedApprovalPolicy': 'on-request',
        'selectedSandboxPolicy': 'workspaceWrite',
        'enabled': true,
      });
      expect(custom!.selectedPermissionOptionId, 'team-safe');

      final json = custom.toJson();
      expect(json['selectedPermissionOptionId'], 'team-safe');
    });

    test('V1 Grok default/unknown migrate to ask', () {
      final fromDefault = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'grok',
        'displayName': 'Grok',
        'kind': 'acp',
        'command': 'grok',
        'selectedPermissionMode': 'default',
        'enabled': true,
      });
      expect(fromDefault!.selectedPermissionOptionId, 'ask');

      final fromUnknown = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'grok',
        'displayName': 'Grok',
        'kind': 'acp',
        'command': 'grok',
        'selectedPermissionOptionId': 'weird',
        'enabled': true,
      });
      expect(fromUnknown!.selectedPermissionOptionId, 'ask');
    });

    test('V2 round-trip keeps only optionId', () {
      final original = AgentProviderConfig.defaultGrok.withPermissionPreference(
        'always-approve',
      );
      final encoded = original.toJson();
      expect(encoded['selectedPermissionOptionId'], 'always-approve');
      expect(encoded.containsKey('selectedPermissionMode'), isFalse);

      final decoded = AgentProviderConfig.tryDecode(encoded);
      expect(decoded!.selectedPermissionOptionId, 'always-approve');
      expect(decoded.resolvedPermissionOptionId, 'always-approve');
    });

    test('withPermissionPreference clears nullable preference', () {
      final withPref = AgentProviderConfig.defaultCodex
          .withPermissionPreference('team-safe');
      expect(withPref.selectedPermissionOptionId, 'team-safe');

      final cleared = withPref.withPermissionPreference(null);
      expect(cleared.selectedPermissionOptionId, isNull);

      final json = cleared.toJson();
      expect(json['selectedPermissionOptionId'], isNull);
      expect(json.containsKey('selectedApprovalPolicy'), isFalse);
    });

    test('copyWith sentinel distinguishes unset and explicit null', () {
      final base = AgentProviderConfig.defaultCodex.withPermissionPreference(
        'auto',
      );
      final kept = base.copyWith(displayName: 'Codex X');
      expect(kept.selectedPermissionOptionId, 'auto');

      final cleared = base.copyWith(selectedPermissionOptionId: null);
      expect(cleared.selectedPermissionOptionId, isNull);
    });

    test('damaged provider entry is skipped safely', () {
      final settings = AgentProviderSettings.tryDecode(<String, Object?>{
        'version': 2,
        'activeProviderId': 'codex',
        'providers': <Object?>[
          <String, Object?>{'id': 'broken'},
          AgentProviderConfig.defaultCodex
              .withPermissionPreference(':workspace')
              .toJson(),
        ],
      });
      expect(
        settings.providers.any(
          (p) => p.selectedPermissionOptionId == ':workspace',
        ),
        isTrue,
      );
    });

    test('settings accept V1 and write V2', () {
      final v1 = AgentProviderSettings.tryDecode(<String, Object?>{
        'version': 1,
        'activeProviderId': 'grok',
        'providers': <Object?>[
          <String, Object?>{
            'id': 'grok',
            'displayName': 'Grok',
            'kind': 'acp',
            'command': 'grok',
            'selectedPermissionMode': 'auto',
            'enabled': true,
          },
        ],
      });
      expect(v1.activeProviderId, 'grok');
      final grok = v1.providers.firstWhere((p) => p.id == 'grok');
      expect(grok.selectedPermissionOptionId, 'auto');

      final raw = v1.toJson();
      expect(raw['version'], AgentProviderSettings.currentVersion);
      expect(raw['version'], 2);

      final providers = raw['providers'] as List<Object?>;
      final grokJson = providers.cast<Map<String, Object?>>().firstWhere(
        (p) => p['id'] == 'grok',
      );
      expect(grokJson['selectedPermissionOptionId'], 'auto');
      expect(grokJson.containsKey('selectedPermissionMode'), isFalse);
    });

    test('unsupported settings version falls back to defaults', () {
      final settings = AgentProviderSettings.tryDecode(<String, Object?>{
        'version': 99,
        'providers': <Object?>[],
      });
      expect(settings.activeProviderId, defaultAgentProviderId);
    });
  });
}

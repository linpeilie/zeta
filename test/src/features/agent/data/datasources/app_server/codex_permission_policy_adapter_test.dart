import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CodexPermissionPolicyCodec', () {
    test(
      'custom profile id without colon binds profile and is not overwritten',
      () {
        final snapshot = CodexPermissionPolicyCodec.snapshotForProfileId(
          'team-safe',
        );
        expect(snapshot.optionId, 'team-safe');
        expect(snapshot.permissionProfileId, 'team-safe');
        expect(
          CodexPermissionPolicyCodec.protocolPermissionProfileId(snapshot),
          'team-safe',
        );
        // 即使默认 approval/sandbox 与 :workspace 相同，显式自定义 id 优先。
        expect(
          CodexPermissionPolicyCodec.protocolPermissionProfileId(snapshot),
          isNot(':workspace'),
        );
      },
    );

    test('built-in profiles expand approval and sandbox', () {
      final workspace = CodexPermissionPolicyCodec.snapshotForOptionId(
        ':workspace',
      );
      expect(workspace.sandboxPolicy, 'workspaceWrite');
      expect(workspace.approvalPolicy, 'on-request');
      expect(workspace.permissionProfileId, ':workspace');
    });

    test('legacy policies map to built-in option id', () {
      expect(
        CodexPermissionPolicyCodec.builtInOptionIdFromPolicies(
          approvalPolicy: 'never',
          sandboxPolicy: 'dangerFullAccess',
        ),
        ':danger-full-access',
      );
    });

    test('thread settings decode forms a complete snapshot', () {
      final snapshot = CodexPermissionPolicyCodec.decodeThreadSettings(
        <String, Object?>{
          'approvalPolicy': 'never',
          'sandboxPolicy': <String, Object?>{'type': 'danger-full-access'},
          'activePermissionProfile': <String, Object?>{'id': 'team-safe'},
        },
      );
      expect(snapshot, isNotNull);
      expect(snapshot!.permissionProfileId, 'team-safe');
      expect(snapshot.optionId, 'team-safe');
      expect(snapshot.approvalPolicy, 'never');
      expect(snapshot.sandboxPolicy, 'dangerFullAccess');
    });

    test('encode turn/thread permission fields prefer explicit profile', () {
      final snapshot = CodexPermissionPolicyCodec.snapshotForProfileId(
        'team-safe',
      );
      final thread = CodexPermissionPolicyCodec.encodeThreadPermissionFields(
        snapshot,
      );
      expect(thread['permissions'], 'team-safe');
      expect(thread.containsKey('sandbox'), isFalse);
      final turn = CodexPermissionPolicyCodec.encodeTurnPermissionFields(
        snapshot,
      );
      expect(turn['permissions'], 'team-safe');
      expect(turn.containsKey('sandboxPolicy'), isFalse);
    });

    test('config snapshot keeps explicit profile id from V2 optionId', () {
      final config = AgentProviderConfig.defaultCodex.withPermissionPreference(
        'team-safe',
      );
      final snapshot = CodexPermissionPolicyCodec.snapshotFromConfig(config);
      expect(snapshot.permissionProfileId, 'team-safe');
      expect(snapshot.optionId, 'team-safe');
    });
  });

  group('CodexPermissionPolicyAdapter', () {
    test('lists options across cursor pages', () async {
      var page = 0;
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          expect(method, 'permissionProfile/list');
          page += 1;
          if (page == 1) {
            expect(params['cursor'], isNull);
            return <String, Object?>{
              'data': <Object?>[
                <String, Object?>{
                  'id': ':workspace',
                  'allowed': true,
                  'description': 'Workspace write',
                },
              ],
              'nextCursor': 'c2',
            };
          }
          expect(params['cursor'], 'c2');
          return <String, Object?>{
            'data': <Object?>[
              <String, Object?>{
                'id': 'team-safe',
                'allowed': true,
                'description': 'Team safe',
              },
            ],
          };
        },
        onSelectionApplied: (_) {},
        currentSnapshot: () => const AgentPermissionSelectionSnapshot(),
      );

      final catalog = await adapter.listPermissionOptions();
      expect(catalog.options.map((o) => o.id).toList(), <String>[
        ':workspace',
        'team-safe',
      ]);
      expect(catalog.options.first.label, 'Workspace write');
      expect(catalog.options[1].label, 'Team safe');
      expect(catalog.defaultOptionId, ':workspace');
    });

    test('falls back to built-ins when list is unsupported', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          throw UnsupportedError('permissionProfile/list not available');
        },
        onSelectionApplied: (_) {},
        currentSnapshot: () => const AgentPermissionSelectionSnapshot(),
      );

      final catalog = await adapter.listPermissionOptions();
      expect(
        catalog.options.map((o) => o.id),
        containsAll(<String>[
          ':workspace',
          ':read-only',
          ':danger-full-access',
        ]),
      );
    });

    test(
      'apply custom profile writes snapshot without colon requirement',
      () async {
        AgentPermissionSelectionSnapshot? applied;
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                fail('list should not be called');
              },
          onSelectionApplied: (snapshot) => applied = snapshot,
          currentSnapshot: () => const AgentPermissionSelectionSnapshot(),
        );

        final result = await adapter.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'team-safe'),
        );
        expect(result.normalizedSelection.optionId, 'team-safe');
        expect(result.scope, AgentPermissionApplyScope.currentSession);
        expect(applied?.permissionProfileId, 'team-safe');
        expect(applied?.optionId, 'team-safe');
        expect(
          CodexPermissionPolicyCodec.protocolPermissionProfileId(applied!),
          'team-safe',
        );
      },
    );
  });
}

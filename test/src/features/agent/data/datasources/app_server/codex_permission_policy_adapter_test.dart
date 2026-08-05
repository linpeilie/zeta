import 'dart:async';

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

    test('encodes a built-in option from the neutral request snapshot', () {
      const request = AgentPermissionRequestSnapshot.resolved(
        selection: AgentPermissionSelection(optionId: ':danger-full-access'),
        source: AgentPermissionRequestSource.threadEffective,
      );
      final fallback = CodexPermissionPolicyCodec.snapshotForProfileId(
        ':workspace',
      );

      final runtime = CodexPermissionPolicyCodec.runtimeSnapshotForRequest(
        request,
        configFallback: fallback,
      );
      final thread =
          CodexPermissionPolicyCodec.encodeThreadRequestPermissionFields(
            request,
            configFallback: fallback,
          );
      final turn = CodexPermissionPolicyCodec.encodeTurnRequestPermissionFields(
        request,
        configFallback: fallback,
      );

      expect(runtime.permissionProfileId, ':danger-full-access');
      expect(runtime.approvalPolicy, 'never');
      expect(runtime.sandboxPolicy, 'dangerFullAccess');
      expect(thread, <String, Object?>{
        'approvalPolicy': 'never',
        'permissions': ':danger-full-access',
      });
      expect(turn, <String, Object?>{
        'approvalPolicy': 'never',
        'permissions': ':danger-full-access',
      });
    });

    test(
      'encodes custom profile and only falls back without request choice',
      () {
        const customRequest = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: 'team-safe'),
          source: AgentPermissionRequestSource.threadEffective,
        );
        const fallbackRequest =
            AgentPermissionRequestSnapshot.providerFallback();
        final fallback = CodexPermissionPolicyCodec.snapshotForProfileId(
          ':read-only',
        );

        expect(
          CodexPermissionPolicyCodec.encodeTurnRequestPermissionFields(
            customRequest,
            configFallback: fallback,
          ),
          <String, Object?>{
            'approvalPolicy': 'on-request',
            'permissions': 'team-safe',
          },
        );
        expect(
          CodexPermissionPolicyCodec.encodeTurnRequestPermissionFields(
            fallbackRequest,
            configFallback: fallback,
          ),
          <String, Object?>{
            'approvalPolicy': 'on-request',
            'permissions': ':read-only',
          },
        );
      },
    );
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
        fallbackOptionId: ':workspace',
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
        fallbackOptionId: ':workspace',
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

    test('rethrows timeout so caller can retain previous catalog', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          throw TimeoutException('permissionProfile/list timed out');
        },
        fallbackOptionId: ':workspace',
      );

      await expectLater(
        adapter.listPermissionOptions(),
        throwsA(isA<TimeoutException>()),
      );
    });

    test(
      'rethrows when a later page fails without returning partial data',
      () async {
        var page = 0;
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                page += 1;
                if (page == 1) {
                  return <String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{
                        'id': 'team-safe',
                        'allowed': true,
                        'description': 'Team safe',
                      },
                    ],
                    'nextCursor': 'page-2',
                  };
                }
                throw TimeoutException('page 2 timed out');
              },
          fallbackOptionId: ':workspace',
        );

        await expectLater(
          adapter.listPermissionOptions(),
          throwsA(isA<TimeoutException>()),
        );
      },
    );

    test('throws on malformed list response instead of built-ins', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          return 'not-an-object';
        },
        fallbackOptionId: ':workspace',
      );

      await expectLater(
        adapter.listPermissionOptions(),
        throwsA(isA<FormatException>()),
      );
    });

    test(
      'apply custom profile is pure and keeps configured fallback immutable',
      () async {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                fail('list should not be called');
              },
          fallbackOptionId: ':workspace',
        );

        final result = await adapter.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'team-safe'),
        );
        expect(result.normalizedSelection.optionId, 'team-safe');
        expect(result.scope, AgentPermissionApplyScope.currentSession);
        final emptyResult = await adapter.applyPermissionSelection(
          const AgentPermissionSelection(optionId: '  '),
        );
        expect(emptyResult.normalizedSelection.optionId, ':workspace');
      },
    );
  });
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('CodexPermissionPolicyCodec', () {
    test('keeps built-in labels and legacy aliases in the data codec', () {
      expect(
        CodexPermissionPolicyCodec.normalizeApprovalPolicy('on-failure'),
        'on-request',
      );
      expect(
        CodexPermissionPolicyCodec.snapshotForProfileId(
          ':read-only',
        ).displayLabel,
        'Read only',
      );
      expect(
        CodexPermissionPolicyCodec.snapshotForProfileId(
          ':workspace',
        ).displayLabel,
        'Workspace write',
      );
      expect(
        CodexPermissionPolicyCodec.snapshotForProfileId(
          ':danger-full-access',
        ).displayLabel,
        'Full access',
      );

      final opaque = CodexPermissionPolicyCodec.snapshotForOptionId('auto');
      expect(opaque.optionId, 'auto');
      expect(opaque.permissionProfileId, isNull);
    });

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

    test('terminates safely when the server repeats a cursor', () async {
      var calls = 0;
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          calls += 1;
          if (calls == 1) {
            expect(params, isEmpty);
            return <String, Object?>{
              'data': <Object?>[
                <String, Object?>{'id': ':workspace'},
              ],
              'nextCursor': 'repeat',
            };
          }
          expect(params['cursor'], 'repeat');
          return <String, Object?>{
            'data': <Object?>[
              <String, Object?>{'id': 'team-safe'},
            ],
            'nextCursor': 'repeat',
          };
        },
      );

      final catalog = await adapter.listPermissionOptions();

      expect(calls, 2);
      expect(catalog.options.map((option) => option.id), <String>[
        ':workspace',
        'team-safe',
      ]);
    });

    test('falls back to built-ins when list is unsupported', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          throw UnsupportedError('permissionProfile/list not available');
        },
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
      'keeps an explicit empty success empty instead of using built-ins',
      () async {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                return <String, Object?>{'data': <Object?>[]};
              },
        );

        final catalog = await adapter.listPermissionOptions();

        expect(catalog.options, isEmpty);
        expect(catalog.defaultOptionId, isEmpty);
      },
    );

    test('falls back only for explicit JSON-RPC method-not-found', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          throw const JsonRpcException(
            JsonRpcError(code: -32601, message: 'Method not found'),
          );
        },
      );

      final catalog = await adapter.listPermissionOptions();
      expect(
        catalog.options.map((option) => option.id),
        contains(':workspace'),
      );
    });

    test(
      'rethrows structured server failures even when text says unavailable',
      () async {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                throw const JsonRpcException(
                  JsonRpcError(
                    code: -32000,
                    message: 'temporarily not available while reconnecting',
                  ),
                );
              },
        );

        await expectLater(
          adapter.listPermissionOptions(),
          throwsA(isA<JsonRpcException>()),
        );
      },
    );

    test(
      'does not infer unsupported from an unstructured error message',
      () async {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                throw StateError('method not found after connection closed');
              },
        );

        await expectLater(
          adapter.listPermissionOptions(),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('rethrows timeout so caller can retain previous catalog', () async {
      final adapter = CodexPermissionPolicyAdapter(
        ensureInitialized: () async {},
        sendRequest: (method, {Map<String, Object?> params = const {}}) async {
          throw TimeoutException('permissionProfile/list timed out');
        },
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
      );

      await expectLater(
        adapter.listPermissionOptions(),
        throwsA(isA<FormatException>()),
      );
    });

    test('throws when a page contains a malformed option or cursor', () async {
      for (final response in <Map<String, Object?>>[
        <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'allowed': true},
          ],
        },
        <String, Object?>{
          'data': <Object?>[
            <String, Object?>{'id': ':workspace'},
          ],
          'nextCursor': 42,
        },
      ]) {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async =>
                  response,
        );

        await expectLater(
          adapter.listPermissionOptions(),
          throwsA(isA<FormatException>()),
        );
      }
    });

    test(
      'apply custom profile is pure and rejects an empty option id',
      () async {
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                fail('list should not be called');
              },
        );

        final result = await adapter.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'team-safe'),
        );
        expect(result.normalizedSelection.optionId, 'team-safe');
        expect(result.scope, AgentPermissionApplyScope.currentSession);
        await expectLater(
          adapter.applyPermissionSelection(
            const AgentPermissionSelection(optionId: '  '),
          ),
          throwsArgumentError,
        );
      },
    );
  });
}

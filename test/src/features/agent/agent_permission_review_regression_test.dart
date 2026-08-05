// Agent 权限 Review 问题（P-01～P-05）回归基线。
//
// - P-01～P-05：已修复，预期全部通过。

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_permission_selection_controller.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_app_server_agent_provider.dart';
import 'package:zeta/src/features/agent/data/datasources/app_server/codex_permission_policy_adapter.dart';
import 'package:zeta/src/features/agent/data/datasources/transport/json_rpc_stdio_transport.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('P-01: Codex request must use current thread effective permission', () {
    test(
      'thread A UI selection must appear in turn/start after thread B overwrote '
      'provider-global apply',
      () async {
        final peer = _ReviewFakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        addTearDown(controller.dispose);
        controller.bind(
          port: provider.permissionPolicy,
          persistedOptionId: ':workspace',
        );
        await controller.refreshOptions();

        // Thread A → team-safe（thread-local effective）。
        controller.bindThread('thread-a');
        await controller.selectOption(
          const AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
        );
        expect(controller.selectedOptionId, 'team-safe');

        // Thread B → :read-only。
        controller.bindThread('thread-b');
        await controller.selectOption(
          const AgentPermissionOption(id: ':read-only', label: 'Read only'),
        );
        expect(controller.selectedOptionId, ':read-only');

        // 切回 A：UI/controller effective 恢复为 team-safe。
        controller.bindThread('thread-a');
        expect(
          controller.selectedOptionId,
          'team-safe',
          reason: 'controller thread-local effective must restore for A',
        );

        // 模拟 ViewModel：将当前 thread effective 冻结进请求快照。
        final session = await provider.startSession(
          context: const AgentContext(projectPath: '/repo'),
          permissionSelection: controller.effectiveSelection,
        );
        await provider.sendMessage(
          session: session,
          message: 'from thread A',
          context: const AgentContext(projectPath: '/repo'),
          configuration: AgentTurnConfiguration(
            permissionSelection: controller.effectiveSelection,
          ),
        );

        final turnStartIndex = peer.requestMethods.lastIndexOf('turn/start');
        expect(
          turnStartIndex,
          isNot(-1),
          reason: 'sendMessage must issue turn/start',
        );
        final turnParams =
            peer.requestParams[turnStartIndex]! as Map<String, Object?>;

        // 关键断言：真实 JSON-RPC params，不能只看 controller UI state。
        expect(
          turnParams['permissions'],
          'team-safe',
          reason:
              'P-01: turn/start must encode the bound thread effective '
              'selection (team-safe), not the last provider-global apply '
              '(:read-only from thread B)',
        );
      },
    );

    test('two sequential turns for different thread effectives must not share '
        'the last applied provider snapshot', () async {
      final peer = _ReviewFakeJsonRpcPeer();
      final provider = CodexAppServerAgentProvider(
        config: AgentProviderConfig.defaultCodex,
        peer: peer,
      );
      addTearDown(provider.dispose);

      final controller = AgentConversationPermissionSelectionController(
        persistOptionId: (_) async {},
      );
      addTearDown(controller.dispose);
      controller.bind(
        port: provider.permissionPolicy,
        persistedOptionId: ':workspace',
      );
      await controller.refreshOptions();

      controller.bindThread('thread-a');
      await controller.selectOption(
        const AgentPermissionOption(id: 'team-safe', label: 'Team safe'),
      );
      final sessionA = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
        permissionSelection: controller.effectiveSelection,
      );
      await provider.sendMessage(
        session: sessionA,
        message: 'A',
        context: const AgentContext(projectPath: '/repo'),
        configuration: AgentTurnConfiguration(
          permissionSelection: controller.effectiveSelection,
        ),
      );

      controller.bindThread('thread-b');
      await controller.selectOption(
        const AgentPermissionOption(id: ':read-only', label: 'Read only'),
      );
      final sessionB = await provider.startSession(
        context: const AgentContext(projectPath: '/repo'),
        permissionSelection: controller.effectiveSelection,
      );
      await provider.sendMessage(
        session: sessionB,
        message: 'B',
        context: const AgentContext(projectPath: '/repo'),
        configuration: AgentTurnConfiguration(
          permissionSelection: controller.effectiveSelection,
        ),
      );

      // 切回 A 后再次发送：请求快照必须是 A 的 team-safe。
      controller.bindThread('thread-a');
      expect(controller.selectedOptionId, 'team-safe');
      await provider.sendMessage(
        session: sessionA,
        message: 'A again',
        context: const AgentContext(projectPath: '/repo'),
        configuration: AgentTurnConfiguration(
          permissionSelection: controller.effectiveSelection,
        ),
      );

      final turnPermissions = <String?>[];
      for (var i = 0; i < peer.requestMethods.length; i++) {
        if (peer.requestMethods[i] != 'turn/start') {
          continue;
        }
        final params = peer.requestParams[i]! as Map<String, Object?>;
        turnPermissions.add(params['permissions'] as String?);
      }

      expect(
        turnPermissions.length,
        3,
        reason: 'three turn/start calls expected',
      );
      expect(turnPermissions[0], 'team-safe');
      expect(turnPermissions[1], ':read-only');
      expect(
        turnPermissions[2],
        'team-safe',
        reason:
            'P-01: third turn (thread A again) must not reuse B\'s '
            ':read-only from provider-global snapshot',
      );
    });
  });

  group(
    'P-02: policy-only thread settings must update effective selection',
    () {
      test('approval/sandbox-only settings notification updates controller to '
          ':read-only without active profile', () async {
        final peer = _ReviewFakeJsonRpcPeer();
        final provider = CodexAppServerAgentProvider(
          config: AgentProviderConfig.defaultCodex,
          peer: peer,
        );
        addTearDown(provider.dispose);

        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {
            fail('settings writeback must not persist global default');
          },
        );
        addTearDown(controller.dispose);
        controller.bind(
          port: provider.permissionPolicy,
          persistedOptionId: ':workspace',
        );
        controller.bindThread('thread-policy');
        await controller.refreshOptions();
        expect(controller.selectedOptionId, ':workspace');

        final events = <AgentEvent>[];
        final subscription = provider.events.listen(events.add);
        addTearDown(subscription.cancel);
        await provider.initialize();

        // 仅有 approval/sandbox，没有 activePermissionProfile。
        peer.emitNotification('thread/settings/updated', <String, Object?>{
          'threadId': 'thread-policy',
          'threadSettings': <String, Object?>{
            'approvalPolicy': 'on-request',
            'sandboxPolicy': <String, Object?>{'type': 'readOnly'},
          },
        });
        await Future<void>.delayed(Duration.zero);

        final event = events
            .whereType<AgentThreadSettingsUpdatedEvent>()
            .single;
        expect(
          event.permissionSelection?.optionId,
          ':read-only',
          reason:
              'P-02: mapper must atomically decode policy-only settings to '
              'neutral :read-only selection',
        );

        // 生产 ViewModel 路径：中立 selection + 事件 thread + 默认不同步 port。
        await controller.applyThreadSettings(
          threadId: event.threadId,
          permissionSelection: event.permissionSelection,
        );

        expect(
          controller.selectedOptionId,
          ':read-only',
          reason:
              'P-02: policy-only settings must map to built-in :read-only '
              'and update the bound thread effective selection',
        );
        expect(
          controller.defaultOptionId,
          ':workspace',
          reason: 'settings writeback must not change provider default',
        );
      });

      test(
        'decodeThreadSettings derives :danger-full-access from policy-only map',
        () {
          // codec 侧应能原子解码；application 消费侧不得丢弃该结果。
          final snapshot = CodexPermissionPolicyCodec.decodeThreadSettings(
            <String, Object?>{
              'approvalPolicy': 'never',
              'sandboxPolicy': <String, Object?>{'type': 'danger-full-access'},
            },
          );
          expect(snapshot, isNotNull);
          expect(
            snapshot!.selectedOptionId,
            ':danger-full-access',
            reason:
                'P-02 helper: policy-only settings decode must yield a stable '
                'built-in optionId for controller consumption',
          );
        },
      );
    },
  );

  group('P-03: V2 optionId must win over stale V1 profile', () {
    test('conflict fixture option=:read-only + profile=team-safe resolves to '
        ':read-only', () {
      // 同时含 V2 optionId 与 stale V1 profile 的真实冲突 fixture。
      expect(
        AgentPermissionPreferenceMigration.resolveOptionId(
          kindName: 'codexAppServer',
          selectedPermissionOptionId: ':read-only',
          selectedPermissionProfileId: 'team-safe',
          selectedApprovalPolicy: 'on-request',
          selectedSandboxPolicy: 'workspaceWrite',
        ),
        ':read-only',
        reason:
            'P-03: V2 selectedPermissionOptionId is the only source of truth '
            'when present; stale V1 profile must not win',
      );

      final config = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedPermissionOptionId': ':read-only',
        'selectedPermissionProfileId': 'team-safe',
        'selectedApprovalPolicy': 'never',
        'selectedSandboxPolicy': 'dangerFullAccess',
        'enabled': true,
      });
      expect(config, isNotNull);
      expect(
        config!.selectedPermissionOptionId,
        ':read-only',
        reason:
            'P-03: AgentProviderConfig.tryDecode must prefer V2 optionId '
            'over stale V1 profile in the conflict fixture',
      );
      expect(config.resolvedPermissionOptionId, ':read-only');
    });
  });

  group('P-04: applyEffectiveSelection must commit apply result', () {
    test(
      'normalizedSelection and runtime scope from fake port are committed',
      () async {
        final port = _NormalizingFakePermissionPort(
          options: const <AgentPermissionOption>[
            AgentPermissionOption(id: 'ask', label: 'Ask'),
            AgentPermissionOption(id: 'auto', label: 'Auto'),
            AgentPermissionOption(id: 'default', label: 'Default (legacy)'),
          ],
          // 输入 default → 归一化为 ask；scope = runtime（与输入不同）。
          normalize: (selection) {
            final raw = selection.optionId.trim();
            final normalized = raw == 'default' ? 'ask' : raw;
            return AgentPermissionApplyResult(
              normalizedSelection: AgentPermissionSelection(
                optionId: normalized,
              ),
              scope: AgentPermissionApplyScope.runtime,
              warning: 'legacy default normalized to ask',
            );
          },
        );

        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        addTearDown(controller.dispose);
        controller.bind(port: port, persistedOptionId: 'auto');
        controller.bindThread('t1');
        await controller.applyEffectiveSelection(
          const AgentPermissionSelection(optionId: 'auto'),
          syncPort: false,
        );
        controller.bindThread('t2');
        await controller.applyEffectiveSelection(
          const AgentPermissionSelection(optionId: 'auto'),
          syncPort: false,
        );

        // 在 t1 上 apply 带归一化的结果。
        controller.bindThread('t1');
        await controller.applyEffectiveSelection(
          const AgentPermissionSelection(optionId: 'default'),
        );

        expect(
          controller.selectedOptionId,
          'ask',
          reason:
              'P-04: applyEffectiveSelection must commit '
              'result.normalizedSelection (default→ask), not the raw input',
        );
        expect(
          controller.lastApplyScope,
          AgentPermissionApplyScope.runtime,
          reason: 'P-04: runtime scope from apply result must be recorded',
        );
        expect(
          controller.lastApplyWarning,
          'legacy default normalized to ask',
          reason: 'P-04: warning from apply result must be retained',
        );

        // runtime scope 应同步所有已缓存 thread。
        controller.bindThread('t2');
        expect(
          controller.selectedOptionId,
          'ask',
          reason:
              'P-04: runtime scope must broadcast normalized selection to '
              'all bound threads',
        );
        expect(controller.defaultOptionId, 'ask');
      },
    );
  });

  group('P-05: transient catalog failure must preserve custom catalog', () {
    test(
      'successful custom catalog is retained after timeout on refresh',
      () async {
        var listCalls = 0;
        final adapter = CodexPermissionPolicyAdapter(
          ensureInitialized: () async {},
          sendRequest:
              (method, {Map<String, Object?> params = const {}}) async {
                expect(method, 'permissionProfile/list');
                listCalls += 1;
                if (listCalls == 1) {
                  return <String, Object?>{
                    'data': <Object?>[
                      <String, Object?>{
                        'id': 'team-safe',
                        'allowed': true,
                        'description': 'Team safe',
                      },
                      <String, Object?>{
                        'id': ':workspace',
                        'allowed': true,
                        'description': 'Workspace write',
                      },
                    ],
                  };
                }
                // 临时失败：超时，不得被当成 unsupported 降级为 built-ins。
                throw TimeoutException('permissionProfile/list timed out');
              },
          onSelectionApplied: (_) {},
          currentSnapshot: () => const CodexPermissionRuntimeSnapshot(),
        );

        final controller = AgentConversationPermissionSelectionController(
          persistOptionId: (_) async {},
        );
        addTearDown(controller.dispose);
        controller.bind(port: adapter, persistedOptionId: null);

        await controller.refreshOptions();
        expect(
          controller.options.map((o) => o.id),
          containsAll(<String>['team-safe', ':workspace']),
          reason: 'first load must commit custom catalog',
        );
        final customIds = controller.options.map((o) => o.id).toList();

        await controller.refreshOptions();
        expect(listCalls, 2);

        expect(
          controller.options.map((o) => o.id).toList(),
          customIds,
          reason:
              'P-05: transient timeout must not replace a previously loaded '
              'custom catalog with static built-ins',
        );
        expect(
          controller.options.map((o) => o.id),
          contains('team-safe'),
          reason: 'custom profile team-safe must remain visible after failure',
        );
      },
    );
  });
}

/// 将输入归一化为不同 optionId/scope 的 fake port（P-04）。
final class _NormalizingFakePermissionPort
    implements AgentPermissionPolicyPort {
  _NormalizingFakePermissionPort({
    required this.options,
    required this.normalize,
  });

  final List<AgentPermissionOption> options;
  final AgentPermissionApplyResult Function(AgentPermissionSelection selection)
  normalize;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    return AgentPermissionCatalog(
      options: options,
      defaultOptionId: options.isEmpty ? '' : options.first.id,
    );
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    return normalize(selection);
  }
}

/// 精简 JSON-RPC peer：只覆盖 P-01/P-02 需要的 method 与通知。
final class _ReviewFakeJsonRpcPeer implements JsonRpcPeer {
  final StreamController<JsonRpcNotification> _notifications =
      StreamController<JsonRpcNotification>.broadcast();
  final StreamController<JsonRpcRequest> _serverRequests =
      StreamController<JsonRpcRequest>.broadcast();
  final StreamController<String> _stderrLines =
      StreamController<String>.broadcast();
  final StreamController<JsonRpcProtocolException> _protocolErrors =
      StreamController<JsonRpcProtocolException>.broadcast();

  final List<String> requestMethods = <String>[];
  final List<Object?> requestParams = <Object?>[];
  int _threadStartCount = 0;
  int _turnStartCount = 0;
  bool _closed = false;

  @override
  Stream<JsonRpcNotification> get notifications => _notifications.stream;

  @override
  Stream<JsonRpcRequest> get serverRequests => _serverRequests.stream;

  @override
  Stream<String> get stderrLines => _stderrLines.stream;

  @override
  Stream<JsonRpcProtocolException> get protocolErrors => _protocolErrors.stream;

  @override
  Future<void> start() async {}

  @override
  Future<Object?> sendRequest(
    String method, {
    Object? params,
    Duration timeout = const Duration(seconds: 30),
  }) async {
    requestMethods.add(method);
    requestParams.add(params);
    return switch (method) {
      'initialize' => <String, Object?>{
        'codexHome': '/home/test/.codex',
        'platformFamily': 'unix',
        'platformOs': 'linux',
        'userAgent': 'codex_cli_rs/0.144.5',
      },
      'thread/start' => () {
        _threadStartCount += 1;
        return <String, Object?>{
          'thread': <String, Object?>{'id': 'thread-$_threadStartCount'},
        };
      }(),
      'turn/start' => () {
        _turnStartCount += 1;
        return <String, Object?>{
          'turn': <String, Object?>{'id': 'turn-$_turnStartCount'},
        };
      }(),
      'permissionProfile/list' => <String, Object?>{
        'data': <Object?>[
          <String, Object?>{
            'id': ':workspace',
            'allowed': true,
            'description': 'Workspace write',
          },
          <String, Object?>{
            'id': ':read-only',
            'allowed': true,
            'description': 'Read only',
          },
          <String, Object?>{
            'id': ':danger-full-access',
            'allowed': true,
            'description': 'Full access',
          },
          <String, Object?>{
            'id': 'team-safe',
            'allowed': true,
            'description': 'Team safe',
          },
        ],
      },
      _ => <String, Object?>{},
    };
  }

  @override
  void sendNotification(String method, {Object? params}) {}

  @override
  Future<void> sendResponse(
    Object id, {
    Object? result,
    JsonRpcError? error,
  }) async {}

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }
    _closed = true;
    await _notifications.close();
    await _serverRequests.close();
    await _stderrLines.close();
    await _protocolErrors.close();
  }

  void emitNotification(String method, Map<String, Object?> params) {
    _notifications.add(
      JsonRpcNotification(
        method: method,
        params: params,
        raw: <String, Object?>{'method': method, 'params': params},
      ),
    );
  }
}

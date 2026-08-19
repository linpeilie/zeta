import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:grok_acp_client/src/datasources/acp/grok_permission_policy_adapter.dart';
import 'package:grok_acp_client/src/mappers/grok_permission_mode_codec.dart';
import 'package:test/test.dart';

void main() {
  group('GrokPermissionPolicyAdapter', () {
    test('catalog exposes only Ask Auto Always approve', () async {
      final adapter = _buildAdapter(initialized: true);
      final catalog = await adapter.listPermissionOptions();
      expect(catalog.options.map((o) => o.id).toList(), <String>[
        'ask',
        'auto',
        'always-approve',
      ]);
      expect(catalog.defaultOptionId, 'ask');
      expect(catalog.options.map((o) => o.label).toList(), <String>[
        'Ask',
        'Auto',
        'Always approve',
      ]);
    });

    test('unknown option fail-closes to ask', () async {
      GrokPermissionMode? applied;
      final notifications = <({String method, Map<String, Object?> params})>[];
      final adapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => GrokPermissionMode.auto,
        onModeApplied: (mode) => applied = mode,
        notifyLive: (method, params) {
          notifications.add((method: method, params: params));
        },
      );

      final result = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: 'not-a-mode'),
      );
      expect(result.normalizedSelection.optionId, 'ask');
      expect(applied, GrokPermissionMode.ask);
      expect(result.scope, AgentPermissionApplyScope.runtime);
      expect(notifications, hasLength(1));
      expect(notifications.single.method, '_x.ai/yolo_mode_changed');
      expect(notifications.single.params['yolo_mode'], isFalse);
      expect(notifications.single.params['auto_mode'], isFalse);
    });

    test('new/load meta is consistent for all three modes', () {
      final adapter = _buildAdapter(initialized: false);
      expect(
        adapter.sessionMetaForMode(GrokPermissionMode.ask),
        <String, Object?>{'clientIdentifier': 'zeta'},
      );
      expect(
        adapter.sessionMetaForMode(GrokPermissionMode.auto),
        <String, Object?>{'autoMode': true, 'clientIdentifier': 'zeta'},
      );
      expect(
        adapter.sessionMetaForMode(GrokPermissionMode.alwaysApprove),
        <String, Object?>{'yoloMode': true, 'clientIdentifier': 'zeta'},
      );
    });

    test('live change uses single verified method when initialized', () async {
      final notifications = <String>[];
      var mode = GrokPermissionMode.ask;
      final adapter = GrokPermissionPolicyAdapter(
        isInitialized: () => true,
        isDisposed: () => false,
        currentMode: () => mode,
        onModeApplied: (next) => mode = next,
        notifyLive: (method, params) {
          notifications.add(method);
          expect(method, GrokPermissionModeCodec.yoloModeChangedMethod);
        },
      );

      final always = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: 'always-approve'),
      );
      expect(always.scope, AgentPermissionApplyScope.runtime);
      expect(mode, GrokPermissionMode.alwaysApprove);

      final ask = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: 'ask'),
      );
      expect(ask.scope, AgentPermissionApplyScope.runtime);
      expect(mode, GrokPermissionMode.ask);
      expect(notifications, <String>[
        '_x.ai/yolo_mode_changed',
        '_x.ai/yolo_mode_changed',
      ]);
      // 不双发 x.ai/ 前缀。
      expect(notifications, isNot(contains('x.ai/yolo_mode_changed')));
    });

    test(
      'uninitialized apply returns nextSession scope without live notify',
      () async {
        final notifications = <String>[];
        var mode = GrokPermissionMode.ask;
        final adapter = GrokPermissionPolicyAdapter(
          isInitialized: () => false,
          isDisposed: () => false,
          currentMode: () => mode,
          onModeApplied: (next) => mode = next,
          notifyLive: (method, params) {
            notifications.add(method);
          },
        );

        final result = await adapter.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'auto'),
        );
        expect(result.scope, AgentPermissionApplyScope.nextSession);
        expect(mode, GrokPermissionMode.auto);
        expect(notifications, isEmpty);
      },
    );

    test('default alias normalizes to ask', () async {
      final adapter = _buildAdapter(initialized: true);
      final result = await adapter.applyPermissionSelection(
        const AgentPermissionSelection(optionId: 'default'),
      );
      expect(result.normalizedSelection.optionId, 'ask');
    });
  });
}

GrokPermissionPolicyAdapter _buildAdapter({required bool initialized}) {
  var mode = GrokPermissionMode.ask;
  return GrokPermissionPolicyAdapter(
    isInitialized: () => initialized,
    isDisposed: () => false,
    currentMode: () => mode,
    onModeApplied: (next) => mode = next,
    notifyLive: (method, params) {},
  );
}

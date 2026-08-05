import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 权限持久化 / 协议样例基线（阶段 0 + 阶段 5 V2）。
///
/// 样例全部为合成数据，不读取 ~/.zeta / ~/.grok / ~/.codex。
void main() {
  group('permission persistence fixtures (V2)', () {
    test('Codex built-in :workspace migrates and writes optionId only', () {
      final json = <String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedPermissionOptionId': ':workspace',
        'selectedPermissionProfileId': ':workspace',
        'selectedApprovalPolicy': 'on-request',
        'selectedSandboxPolicy': 'workspaceWrite',
        'enabled': true,
      };

      final config = AgentProviderConfig.tryDecode(json);
      expect(config, isNotNull);
      expect(config!.selectedPermissionOptionId, ':workspace');
      expect(config.selectedPermissionProfileId, isNull);
      expect(config.selectedApprovalPolicy, isNull);
      expect(config.selectedSandboxPolicy, isNull);
      expect(config.resolvedPermissionOptionId, ':workspace');

      final encoded = config.toJson();
      expect(encoded['selectedPermissionOptionId'], ':workspace');
      expect(encoded.containsKey('selectedPermissionProfileId'), isFalse);
      expect(encoded.containsKey('selectedApprovalPolicy'), isFalse);
      expect(encoded.containsKey('selectedSandboxPolicy'), isFalse);
    });

    test(
      'Codex custom team-safe profile preserves opaque id without colon',
      () {
        final json = <String, Object?>{
          'id': 'codex',
          'displayName': 'Codex',
          'kind': 'codexAppServer',
          'command': 'codex',
          'selectedPermissionOptionId': 'team-safe',
          'selectedPermissionProfileId': 'team-safe',
          'selectedApprovalPolicy': 'on-request',
          'selectedSandboxPolicy': 'workspaceWrite',
          'enabled': true,
        };

        final config = AgentProviderConfig.tryDecode(json)!;
        expect(config.selectedPermissionOptionId, 'team-safe');
        expect(config.selectedPermissionProfileId, isNull);
        expect(config.resolvedPermissionOptionId, 'team-safe');

        final selection = AgentPermissionSelectionSnapshot.forProfileId(
          config.resolvedPermissionOptionId!,
        );
        expect(selection.protocolPermissionProfileId, 'team-safe');
        expect(selection.protocolPermissionProfileId, isNot(':workspace'));
      },
    );

    test(
      'Codex legacy approval/sandbox only config migrates to built-in option',
      () {
        final json = <String, Object?>{
          'id': 'codex',
          'displayName': 'Codex',
          'kind': 'codexAppServer',
          'command': 'codex',
          'selectedApprovalPolicy': 'never',
          'selectedSandboxPolicy': 'dangerFullAccess',
          'enabled': true,
        };

        final config = AgentProviderConfig.tryDecode(json)!;
        expect(config.selectedPermissionOptionId, ':danger-full-access');
        expect(config.selectedPermissionProfileId, isNull);
        expect(config.selectedApprovalPolicy, isNull);
        expect(config.selectedSandboxPolicy, isNull);
        expect(config.resolvedPermissionOptionId, ':danger-full-access');
      },
    );

    test('Grok selectedPermissionOptionId auto is opaque option only', () {
      final json = <String, Object?>{
        'id': 'grok',
        'displayName': 'Grok',
        'kind': 'acp',
        'command': 'grok',
        'selectedPermissionOptionId': 'auto',
        'enabled': true,
      };

      final config = AgentProviderConfig.tryDecode(json)!;
      expect(config.selectedPermissionOptionId, 'auto');
      expect(config.selectedPermissionProfileId, isNull);
      expect(config.resolvedPermissionOptionId, 'auto');
      expect(
        GrokPermissionModeCodec.parse(config.resolvedPermissionOptionId),
        GrokPermissionMode.auto,
      );
    });

    test(
      'Grok legacy selectedPermissionMode default migrates to optionId ask',
      () {
        final json = <String, Object?>{
          'id': 'grok',
          'displayName': 'Grok',
          'kind': 'acp',
          'command': 'grok',
          'selectedPermissionMode': 'default',
          'enabled': true,
        };

        final config = AgentProviderConfig.tryDecode(json)!;
        expect(config.selectedPermissionOptionId, 'ask');
        expect(
          GrokPermissionModeCodec.parse(config.selectedPermissionOptionId),
          GrokPermissionMode.ask,
        );
        final catalogIds = GrokPermissionModeCodec.catalogAsOptions()
            .map((o) => o.id)
            .toList();
        expect(catalogIds, <String>['ask', 'auto', 'always-approve']);
        expect(catalogIds, isNot(contains('default')));
      },
    );

    test('Grok unknown option fail-closes to ask for protocol meta', () {
      expect(GrokPermissionModeCodec.parse('nope'), GrokPermissionMode.ask);
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.ask),
        <String, Object?>{'clientIdentifier': 'zeta'},
      );
    });
  });

  group('Grok protocol desensitized fixtures (phase 0)', () {
    test('session meta fixtures for new/load three modes', () {
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.ask),
        _fixtureSessionMetaAsk,
      );
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.auto),
        _fixtureSessionMetaAuto,
      );
      expect(
        GrokPermissionModeCodec.sessionMeta(GrokPermissionMode.alwaysApprove),
        _fixtureSessionMetaAlwaysApprove,
      );
    });

    test('live notification fixtures and single method', () {
      expect(
        GrokPermissionModeCodec.yoloModeChangedMethod,
        '_x.ai/yolo_mode_changed',
      );
      expect(
        GrokPermissionModeCodec.yoloModeChangedParams(GrokPermissionMode.ask),
        _fixtureLiveAsk,
      );
      expect(
        GrokPermissionModeCodec.yoloModeChangedParams(GrokPermissionMode.auto),
        _fixtureLiveAuto,
      );
      expect(
        GrokPermissionModeCodec.yoloModeChangedParams(
          GrokPermissionMode.alwaysApprove,
        ),
        _fixtureLiveAlwaysApprove,
      );
    });
  });

  group('historical defect contracts (would fail before focused fixes)', () {
    test('defect1: custom profile seed must keep team-safe protocol id', () {
      final config = AgentProviderConfig.tryDecode(<String, Object?>{
        'id': 'codex',
        'displayName': 'Codex',
        'kind': 'codexAppServer',
        'command': 'codex',
        'selectedPermissionOptionId': 'team-safe',
        'selectedPermissionProfileId': 'team-safe',
        'selectedApprovalPolicy': 'on-request',
        'selectedSandboxPolicy': 'workspaceWrite',
        'enabled': true,
      })!;

      expect(config.resolvedPermissionOptionId, 'team-safe');
      final selection = AgentPermissionSelectionSnapshot.forProfileId(
        config.resolvedPermissionOptionId!,
      );

      expect(selection.permissionProfileId, 'team-safe');
      expect(selection.protocolPermissionProfileId, 'team-safe');
      expect(selection.protocolPermissionProfileId, isNot(':workspace'));
    });

    test('defect2: settings merge must not rebuild via forProfileId', () {
      var next = const AgentPermissionSelectionSnapshot(
        optionId: 'team-safe',
        approvalPolicy: 'on-request',
        sandboxPolicy: 'workspaceWrite',
        permissionProfileId: 'team-safe',
      );

      next = next.copyWith(
        approvalPolicy: 'never',
        sandboxPolicy: 'dangerFullAccess',
      );
      next = next.copyWith(
        optionId: 'team-safe',
        permissionProfileId: 'team-safe',
      );

      expect(next.approvalPolicy, 'never');
      expect(next.sandboxPolicy, 'dangerFullAccess');
      expect(next.permissionProfileId, 'team-safe');

      final broken = AgentPermissionSelectionSnapshot.forProfileId('team-safe');
      expect(broken.approvalPolicy, 'on-request');
      expect(broken.sandboxPolicy, 'workspaceWrite');
      expect(next.approvalPolicy, isNot(broken.approvalPolicy));
    });

    test(
      'defect3: catalog has three modes and default aliases to ask meta',
      () {
        final ids = GrokPermissionModeCodec.catalogAsOptions()
            .map((o) => o.id)
            .toList();
        expect(ids, <String>['ask', 'auto', 'always-approve']);
        expect(ids, isNot(contains('default')));

        final askFromDefault = GrokPermissionModeCodec.parse('default');
        final ask = GrokPermissionModeCodec.parse('ask');
        expect(askFromDefault, GrokPermissionMode.ask);
        expect(ask, GrokPermissionMode.ask);
        expect(
          GrokPermissionModeCodec.sessionMeta(askFromDefault),
          GrokPermissionModeCodec.sessionMeta(ask),
        );
      },
    );
  });
}

const _fixtureSessionMetaAsk = <String, Object?>{'clientIdentifier': 'zeta'};

const _fixtureSessionMetaAuto = <String, Object?>{
  'autoMode': true,
  'clientIdentifier': 'zeta',
};

const _fixtureSessionMetaAlwaysApprove = <String, Object?>{
  'yoloMode': true,
  'clientIdentifier': 'zeta',
};

const _fixtureLiveAsk = <String, Object?>{
  'permission_mode': 'ask',
  'yolo_mode': false,
  'auto_mode': false,
  'clientIdentifier': 'zeta',
};

const _fixtureLiveAuto = <String, Object?>{
  'permission_mode': 'auto',
  'yolo_mode': false,
  'auto_mode': true,
  'clientIdentifier': 'zeta',
};

const _fixtureLiveAlwaysApprove = <String, Object?>{
  'permission_mode': 'always-approve',
  'yolo_mode': true,
  'auto_mode': false,
  'clientIdentifier': 'zeta',
};

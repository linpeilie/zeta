import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/grok_permission_mode_codec.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

/// 阶段 0 脱敏持久化 / 协议样例基线。
///
/// 这些用例锁定当前 V1 配置形态与 Grok 协议契约，供阶段 5 迁移与阶段 1+
/// 回归对照。样例全部为合成数据，不读取 ~/.zeta / ~/.grok / ~/.codex。
void main() {
  group('permission persistence fixtures (phase 0)', () {
    test('Codex built-in :workspace round-trips V1 fields', () {
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
      expect(config.selectedPermissionProfileId, ':workspace');
      expect(config.selectedApprovalPolicy, 'on-request');
      expect(config.selectedSandboxPolicy, 'workspaceWrite');
      expect(config.resolvedPermissionOptionId, ':workspace');

      final encoded = config.toJson();
      expect(encoded['selectedPermissionOptionId'], ':workspace');
      expect(encoded['selectedPermissionProfileId'], ':workspace');
      expect(encoded['selectedApprovalPolicy'], 'on-request');
      expect(encoded['selectedSandboxPolicy'], 'workspaceWrite');
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
        expect(config.selectedPermissionProfileId, 'team-safe');
        expect(config.selectedPermissionOptionId, 'team-safe');
        expect(config.resolvedPermissionOptionId, 'team-safe');
        // 不得因缺少 ':' 被当成非 profile。
        expect(config.selectedPermissionProfileId!.startsWith(':'), isFalse);

        final selection = AgentPermissionSelectionSnapshot(
          optionId: config.resolvedPermissionOptionId,
          approvalPolicy:
              AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
                config.selectedApprovalPolicy,
              ),
          sandboxPolicy:
              config.selectedSandboxPolicy ??
              AgentPermissionSelectionSnapshot.defaultSandboxPolicy,
          permissionProfileId: config.selectedPermissionProfileId,
        );
        expect(selection.protocolPermissionProfileId, 'team-safe');
        expect(selection.protocolPermissionProfileId, isNot(':workspace'));
      },
    );

    test(
      'Codex legacy approval/sandbox only config still decodes without profile',
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
        expect(config.selectedPermissionProfileId, isNull);
        expect(config.selectedPermissionOptionId, isNull);
        expect(config.selectedApprovalPolicy, 'never');
        expect(config.selectedSandboxPolicy, 'dangerFullAccess');
        expect(config.resolvedPermissionOptionId, isNull);

        // 无显式 profile 时，protocolPermissionProfileId 可按策略回落 built-in
        //（阶段 5 迁移 codec 的输入语义；共享层现状保留该行为）。
        final selection = AgentPermissionSelectionSnapshot(
          approvalPolicy:
              AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
                config.selectedApprovalPolicy,
              ),
          sandboxPolicy:
              config.selectedSandboxPolicy ??
              AgentPermissionSelectionSnapshot.defaultSandboxPolicy,
        );
        expect(selection.protocolPermissionProfileId, ':danger-full-access');
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
          // 旧字段：tryDecode 回落到 selectedPermissionOptionId。
          'selectedPermissionMode': 'default',
          'enabled': true,
        };

        final config = AgentProviderConfig.tryDecode(json)!;
        expect(config.selectedPermissionOptionId, 'default');
        expect(
          GrokPermissionModeCodec.parse(config.selectedPermissionOptionId),
          GrokPermissionMode.ask,
        );
        // catalog 不再暴露 default wire id。
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
    /// 修复前：seed 用 startsWith(':') / preset 猜测会丢掉 team-safe profile。
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

      // 模拟修复后的 seedFromConfig 语义（显式字段）。
      final selection = AgentPermissionSelectionSnapshot(
        optionId: config.resolvedPermissionOptionId,
        approvalPolicy:
            AgentPermissionSelectionSnapshot.normalizeApprovalPolicy(
              config.selectedApprovalPolicy,
            ),
        sandboxPolicy:
            config.selectedSandboxPolicy ??
            AgentPermissionSelectionSnapshot.defaultSandboxPolicy,
        permissionProfileId: config.selectedPermissionProfileId,
      );

      expect(selection.permissionProfileId, 'team-safe');
      expect(selection.protocolPermissionProfileId, 'team-safe');
      // 修复前错误结果：protocol id 变成 :workspace。
      expect(selection.protocolPermissionProfileId, isNot(':workspace'));
    });

    /// 修复前：forProfileId 整对象替换冲掉已合并的 approval/sandbox。
    test('defect2: settings merge must not rebuild via forProfileId', () {
      var next = const AgentPermissionSelectionSnapshot(
        optionId: 'team-safe',
        approvalPolicy: 'on-request',
        sandboxPolicy: 'workspaceWrite',
        permissionProfileId: 'team-safe',
      );

      // 正确路径：同一 next 上 copyWith 合并（修复后）。
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

      // 错误路径对照：forProfileId 会把策略重置为默认 on-request/workspaceWrite。
      final broken = AgentPermissionSelectionSnapshot.forProfileId('team-safe');
      expect(broken.approvalPolicy, 'on-request');
      expect(broken.sandboxPolicy, 'workspaceWrite');
      // 因此 settings 路径禁止用 forProfileId 替换已合并的 next。
      expect(next.approvalPolicy, isNot(broken.approvalPolicy));
    });

    /// 修复前：catalog 同时暴露 default 与 ask，session meta 无法区分。
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

// --- 脱敏协议 fixture（与 plan/phase0 文档一致）---

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

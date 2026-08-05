import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/data/mappers/codex_permission_policy_codec.dart';

void main() {
  group('CodexPermissionPolicyCodec runtime snapshots', () {
    test('normalizeApprovalPolicy maps on-failure to on-request', () {
      expect(
        CodexPermissionPolicyCodec.normalizeApprovalPolicy('on-failure'),
        'on-request',
      );
      expect(
        CodexPermissionPolicyCodec.normalizeApprovalPolicy('never'),
        'never',
      );
    });

    test('built-in display labels are short product names', () {
      final workspace = CodexPermissionPolicyCodec.snapshotForOptionId(
        ':workspace',
      );
      expect(workspace.displayLabel, 'Workspace write');
      expect(workspace.displayLabel, isNot(contains('Ask first')));

      final readOnly = CodexPermissionPolicyCodec.snapshotForProfileId(
        ':read-only',
      );
      expect(readOnly.displayLabel, 'Read only');

      final fullAccess = CodexPermissionPolicyCodec.snapshotForProfileId(
        ':danger-full-access',
      );
      expect(fullAccess.displayLabel, 'Full access');

      final custom = CodexPermissionPolicyCodec.snapshotForProfileId(
        'team-safe',
      );
      expect(custom.permissionProfileId, 'team-safe');
      expect(custom.displayLabel, 'team-safe');
    });

    test('snapshotForProfileId maps built-ins and keeps custom ids', () {
      final readOnly = CodexPermissionPolicyCodec.snapshotForProfileId(
        ':read-only',
      );
      expect(readOnly.approvalPolicy, 'on-request');
      expect(readOnly.sandboxPolicy, 'readOnly');
      expect(readOnly.permissionProfileId, ':read-only');

      final custom = CodexPermissionPolicyCodec.snapshotForProfileId(
        'team-safe',
      );
      expect(custom.permissionProfileId, 'team-safe');
      expect(custom.optionId, 'team-safe');
    });

    test('snapshotForOptionId leaves non-built-in out of profile binding', () {
      final auto = CodexPermissionPolicyCodec.snapshotForOptionId('auto');
      expect(auto.optionId, 'auto');
      expect(auto.permissionProfileId, isNull);
    });

    test('encode prefers explicit profile over approval/sandbox', () {
      final snapshot = CodexPermissionPolicyCodec.snapshotForProfileId(
        'team-safe',
      ).copyWith(approvalPolicy: 'never', sandboxPolicy: 'dangerFullAccess');
      final thread = CodexPermissionPolicyCodec.encodeThreadPermissionFields(
        snapshot,
      );
      expect(thread['permissions'], 'team-safe');
      expect(thread.containsKey('sandbox'), isFalse);
    });
  });
}

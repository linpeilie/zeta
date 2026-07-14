import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';

void main() {
  group('AgentProviderCapabilities', () {
    test('keeps Codex thread lifecycle capabilities enabled', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.codexAppServer,
      );

      expect(capabilities.canRenameThread, isTrue);
      expect(capabilities.canArchiveThread, isTrue);
      expect(capabilities.canForkThread, isTrue);
      expect(capabilities.canRollbackThread, isTrue);
      expect(capabilities.canCompactThread, isTrue);
      expect(capabilities.supportsLocalImageInput, isTrue);
      expect(capabilities.supportsPermissionPolicySelection, isTrue);
    });

    test('reports only Grok operations that have real implementations', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.acp,
      );

      expect(capabilities.canCreateSession, isTrue);
      expect(capabilities.canListThreads, isTrue);
      expect(capabilities.canPrompt, isTrue);
      expect(capabilities.canCancelTurn, isTrue);
      expect(capabilities.canRenameThread, isFalse);
      expect(capabilities.canDeleteThread, isFalse);
      expect(capabilities.canForkThread, isFalse);
      expect(capabilities.canSteerTurn, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isTrue);
    });

    test('describes workspace-scoped bootstrap without eager preload', () {
      const policy = AgentProviderBootstrapPolicy.workspaceScoped;

      expect(policy.requiresWorkspace, isTrue);
      expect(policy.allowsEagerModelPreload, isFalse);
    });

    test('keeps Cursor conservative until ACP handshake', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.cursorAcp,
      );

      expect(capabilities.canCreateSession, isTrue);
      expect(capabilities.canPrompt, isTrue);
      expect(capabilities.canCancelTurn, isTrue);
      expect(capabilities.canListThreads, isFalse);
      expect(capabilities.canResumeSession, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isFalse);
      expect(capabilities.bootstrapPolicy.requiresWorkspace, isTrue);
    });
  });
}

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:test/test.dart';

void main() {
  group('AgentProviderCapabilities', () {
    test('enables mode selection only on an effective capability copy', () {
      const declared = AgentProviderCapabilities(canPrompt: true);

      final effective = declared.copyWith(supportsModeSelection: true);

      expect(declared.supportsModeSelection, isFalse);
      expect(effective.supportsModeSelection, isTrue);
    });

    test('describes workspace-scoped bootstrap without eager preload', () {
      const policy = AgentProviderBootstrapPolicy.workspaceScoped;

      expect(policy.requiresWorkspace, isTrue);
      expect(policy.allowsEagerModelPreload, isFalse);
    });

    test('unsupported closes every operation', () {
      const capabilities = AgentProviderCapabilities.unsupported;

      expect(capabilities.canCreateSession, isFalse);
      expect(capabilities.canPrompt, isFalse);
      expect(capabilities.canListThreads, isFalse);
      expect(capabilities.canForkThreadAtTurn, isFalse);
      expect(capabilities.supportsReasoningOptions, isFalse);
      expect(capabilities.bootstrapPolicy.allowsEagerModelPreload, isTrue);
    });
  });
}

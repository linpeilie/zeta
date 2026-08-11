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
      expect(capabilities.canForkThreadAtTurn, isFalse);
      expect(capabilities.canCompactThread, isTrue);
      expect(capabilities.supportsLocalImageInput, isTrue);
      expect(capabilities.supportsSkillInput, isTrue);
      expect(capabilities.supportsPlanApproval, isFalse);
      expect(capabilities.supportsModeSelection, isFalse);
    });

    test('enables mode selection only on an effective capability copy', () {
      const declared = AgentProviderCapabilities.codexAppServer;

      final effective = declared.copyWith(supportsModeSelection: true);

      expect(declared.supportsModeSelection, isFalse);
      expect(effective.supportsModeSelection, isTrue);
    });

    test('reports only Grok operations that have real implementations', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.acp,
      );

      expect(capabilities.canCreateSession, isTrue);
      expect(capabilities.canListThreads, isTrue);
      expect(capabilities.canPrompt, isTrue);
      expect(capabilities.canCancelTurn, isTrue);
      expect(capabilities.canRenameThread, isTrue);
      expect(capabilities.canDeleteThread, isTrue);
      expect(capabilities.canArchiveThread, isFalse);
      expect(capabilities.canForkThread, isFalse);
      expect(capabilities.canSteerTurn, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isTrue);
      expect(capabilities.supportsSkillInput, isTrue);
      expect(capabilities.supportsPermissionRequests, isTrue);
      expect(capabilities.supportsUserQuestions, isTrue);
      expect(capabilities.supportsPlanApproval, isTrue);
    });

    test('describes workspace-scoped bootstrap without eager preload', () {
      const policy = AgentProviderBootstrapPolicy.workspaceScoped;

      expect(policy.requiresWorkspace, isTrue);
      expect(policy.allowsEagerModelPreload, isFalse);
    });

    test('treats the retired Cursor kind as unsupported', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.cursorAcp,
      );

      expect(capabilities.canCreateSession, isFalse);
      expect(capabilities.canPrompt, isFalse);
      expect(capabilities.canCancelTurn, isFalse);
      expect(capabilities.canListThreads, isFalse);
      expect(capabilities.canRemoveThreadFromList, isFalse);
      expect(capabilities.canDeleteThread, isFalse);
      expect(capabilities.canResumeSession, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isFalse);
      expect(capabilities.bootstrapPolicy.allowsEagerModelPreload, isTrue);
    });

    test('exposes M5 model selection and compact for Claude Code', () {
      final capabilities = AgentProviderCapabilities.defaultsFor(
        AgentProviderKind.claudeCode,
      );

      expect(capabilities.canCreateSession, isTrue);
      expect(capabilities.canPrompt, isTrue);
      expect(capabilities.canCancelTurn, isTrue);
      expect(capabilities.supportsUsage, isTrue);
      expect(capabilities.canResumeSession, isTrue);
      expect(capabilities.canListThreads, isTrue);
      expect(capabilities.canReadHistory, isTrue);
      expect(capabilities.canDeleteThread, isFalse);
      expect(capabilities.canRemoveThreadFromList, isTrue);
      expect(capabilities.canSteerTurn, isFalse);
      expect(capabilities.canRenameThread, isFalse);
      expect(capabilities.canArchiveThread, isFalse);
      expect(capabilities.canUnarchiveThread, isFalse);
      expect(capabilities.canForkThread, isFalse);
      expect(capabilities.canForkThreadAtTurn, isFalse);
      expect(capabilities.canCompactThread, isTrue);
      expect(capabilities.supportsPermissionRequests, isTrue);
      expect(capabilities.supportsUserQuestions, isFalse);
      expect(capabilities.supportsPlanApproval, isTrue);
      expect(capabilities.supportsModelSelection, isTrue);
      expect(capabilities.supportsModeSelection, isFalse);
      expect(capabilities.supportsReasoningOptions, isFalse);
      expect(capabilities.supportsServiceTierSelection, isFalse);
      expect(capabilities.supportsSkillInput, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isFalse);
    });
  });
}

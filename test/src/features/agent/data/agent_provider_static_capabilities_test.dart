import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_providers/zeta_agent_providers.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('AgentProviderStaticCapabilities', () {
    test('keeps Codex thread lifecycle capabilities enabled', () {
      final capabilities = AgentProviderStaticCapabilities.forKind(
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

    test('reports only Grok operations that have real implementations', () {
      final capabilities = AgentProviderStaticCapabilities.forKind(
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

    test('exposes model, reasoning, and compact support for Claude Code', () {
      final capabilities = AgentProviderStaticCapabilities.forKind(
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
      expect(capabilities.supportsUserQuestions, isTrue);
      expect(capabilities.supportsPlanApproval, isTrue);
      expect(capabilities.supportsModelSelection, isTrue);
      expect(capabilities.supportsModeSelection, isFalse);
      expect(capabilities.supportsReasoningOptions, isTrue);
      expect(capabilities.supportsServiceTierSelection, isFalse);
      expect(capabilities.supportsSkillInput, isFalse);
      expect(capabilities.supportsLocalImageInput, isFalse);
      expect(capabilities.supportsResourceInput, isFalse);
    });
  });
}

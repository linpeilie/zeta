import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_intent.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_sections.dart';
import '../../../testing/conversation_test_scope.dart';
import '../../../testing/localized_widget_test_host.dart';
import 'harness/agent_pane_test_harness.dart';

void main() {
  testWidgets(
    'real Send buttons isolate two owners; promotion and closing A leave B pending',
    (tester) async {
      final providerA = AgentPaneModeFakeProvider(
        models: agentPaneModelConfigList,
      );
      final providerB = AgentPaneModeFakeProvider(
        models: agentPaneModelConfigList,
      );
      final a = createAgentPaneViewModel(providerA, draftEntryId: 'draft-a');
      final b = createAgentPaneViewModel(providerB, draftEntryId: 'draft-b');
      addTearDown(a.dispose);
      addTearDown(b.dispose);
      await a.initialization;
      await b.initialization;
      final executorA = _WaitingExecutor(), executorB = _WaitingExecutor();
      final ownerA = connectedConversationTestOwner(
        regions: a,
        commands: executorA,
      );
      final ownerB = connectedConversationTestOwner(
        regions: b,
        commands: executorB,
      );
      await pumpLocalizedWidget(
        tester,
        size: const Size(1600, 700),
        child: UncontrolledProviderScope(
          container: conversationTestScope.container,
          child: Row(
            children: [
              Expanded(
                child: AgentPane(key: const ValueKey('a'), controller: a),
              ),
              Expanded(
                child: AgentPane(key: const ValueKey('b'), controller: b),
              ),
            ],
          ),
        ),
      );
      await tester.pump();
      for (final (key, text) in [('a', '你好 A 😀'), ('b', 'hello B')]) {
        final pane = find.byKey(ValueKey(key));
        await tester.enterText(
          find.descendant(
            of: pane,
            matching: find.byKey(const ValueKey('agent-message-input')),
          ),
          text,
        );
        await tester.pump();
        await tester.tap(
          find.descendant(
            of: pane,
            matching: find.byKey(const ValueKey('agent-send-button')),
          ),
        );
        await tester.pump();
      }
      expect(executorA.texts, ['你好 A 😀']);
      expect(executorB.texts, ['hello B']);
      expect(ownerA.current.pendingOperations, hasLength(1));
      expect(ownerB.current.pendingOperations, hasLength(1));
      a.conversationBinding.promoteToThread('thread-a');
      b.conversationBinding.promoteToThread('thread-b');
      final bId = ownerB.current.pendingOperations.single;
      ownerA.closeForEntryRelease();
      await tester.pump();
      expect(ownerA.current.pendingOperations, isEmpty);
      expect(ownerB.current.pendingOperations, {bId});
      executorA.send.complete(
        const AgentCommandOutcome.failed(AgentCommandFailureKind.requestFailed),
      );
      executorB.send.complete(const AgentCommandOutcome.succeeded());
      await tester.pump();
      expect(ownerB.current.pendingOperations, isEmpty);
      expect(ownerB.current.lastFailure, isNull);
      expect(ownerA.current.lastFailure, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  for (final restarted in [false, true]) {
    testWidgets(
      restarted
          ? 'real send rejects a result from an old runtime epoch'
          : 'real send failure settles the ledger once and keeps cleared draft behavior',
      (tester) async {
        final provider = AgentPaneModeFakeProvider(
          models: agentPaneModelConfigList,
        );
        final runtime = createAgentPaneViewModel(provider);
        addTearDown(runtime.dispose);
        await runtime.loadModels();
        final executor = _WaitingExecutor();
        var epoch = 1;
        final owner = connectedConversationTestOwner(
          regions: runtime,
          commands: executor,
          scopeSnapshot: () => AgentConversationCommandScope(
            bindingKey: runtime.conversationBinding.key,
            runtimeId: 'runtime',
            connectionEpoch: epoch,
            listenerGeneration: 1,
          ),
        );
        await tester.pumpWidget(
          AgentPaneTestApp(
            viewModel: runtime,
            sliceStores: {runtime.conversationBinding.key: owner},
          ),
        );
        await tester.enterText(
          find.byKey(const ValueKey('agent-message-input')),
          'failure payload',
        );
        await tester.pump();
        await tester.tap(find.byKey(const ValueKey('agent-send-button')));
        await tester.pump();
        expect(owner.current.pendingOperations, hasLength(1));
        expect(executor.texts, ['failure payload']);
        if (restarted) epoch++;
        executor.send.complete(
          const AgentCommandOutcome.failed(
            AgentCommandFailureKind.requestFailed,
            diagnostic: 'private-error',
          ),
        );
        await tester.pump();
        expect(owner.current.pendingOperations, isEmpty);
        expect(
          owner.current.lastFailure?.kind,
          restarted
              ? AgentCommandFailureKind.staleTarget
              : AgentCommandFailureKind.requestFailed,
        );
        expect(find.text('failure payload'), findsNothing);
        expect(find.text('private-error'), findsNothing);
        expect(owner.diagnostics.effectCount, 1);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'skill picker and header archive enter the same real Actions owner',
    (tester) async {
      final provider = _SkillsProvider();
      final runtime = createAgentPaneViewModel(
        provider,
        initialThread: agentPaneThread(
          id: 'skills-thread',
          title: 'Skills thread',
        ),
      );
      addTearDown(runtime.dispose);
      await runtime.initialization;
      final owner = connectedConversationTestOwner(
        regions: runtime,
        commands: runtime,
      );
      await tester.pumpWidget(
        AgentPaneTestApp(
          viewModel: runtime,
          sliceStores: {runtime.conversationBinding.key: owner},
        ),
      );
      await pumpAgentPaneUi(tester);
      final before = owner.diagnostics.effectCount;
      await tester.tap(find.byKey(const ValueKey('agent-more-actions-button')));
      await pumpAgentPaneUi(tester);
      await tester.tap(find.byKey(const ValueKey('agent-insert-skill-button')));
      await pumpAgentPaneUi(tester);
      expect(
        find.byKey(const ValueKey('agent-skill-picker-overlay')),
        findsOneWidget,
      );
      expect(owner.diagnostics.effectCount, before + 1);
      expect(owner.current.pendingOperations, isEmpty);
      await tester.tap(find.text('Fixture Skill'));
      await pumpAgentPaneUi(tester);
      expect(
        find.byKey(const ValueKey('agent-skill-picker-overlay')),
        findsNothing,
      );
      expect(find.text('Fixture Skill'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('agent-header-more')));
      await pumpAgentPaneUi(tester);
      await tester.tap(find.byKey(const ValueKey('agent-header-menu-archive')));
      await pumpAgentPaneUi(tester);
      expect(provider.archivedThreads, ['skills-thread']);
      expect(owner.diagnostics.effectCount, before + 2);
      expect(owner.current.pendingOperations, isEmpty);
      expect(owner.current.lastFailure, isNull);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'permission and question cards use separate admission and preserve Skip',
    (tester) async {
      final provider = AgentPaneModeFakeProvider(
        models: agentPaneModelConfigList,
      );
      final runtime = createAgentPaneViewModel(provider);
      addTearDown(runtime.dispose);
      await runtime.loadModels();
      final executor = _WaitingExecutor();
      final owner = connectedConversationTestOwner(
        regions: runtime,
        commands: executor,
      );
      owner.refreshRegions(
        AgentConversationRegionsRefreshed(
          pendingInteractions: AgentPendingInteractionState(
            permissions: const [
              AgentPermissionRequest(
                id: 'same',
                title: 'Permission',
                kind: AgentPermissionKind.commandExecution,
              ),
            ],
            questions: const [
              AgentQuestionRequest(
                id: 'same',
                title: 'Question',
                questions: [],
              ),
            ],
            planApprovals: const [],
            planExecutionHandoff: null,
            isReadOnly: false,
            autoReviewsByTurnId: const {},
            latestDeniedAutoReview: null,
          ),
        ),
      );
      await pumpLocalizedWidget(
        tester,
        child: UncontrolledProviderScope(
          container: conversationTestScope.container,
          child: AgentPendingInteractionSection(
            controller: runtime,
            actions: owner,
            pagePadding: EdgeInsets.zero,
            panelHeight: 1500,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final approve = find.byKey(
        const ValueKey('agent-permission-approve-same'),
      );
      await tester.ensureVisible(approve);
      await tester.tap(approve);
      await tester.tap(approve);
      final skip = find.byKey(const ValueKey('agent-question-close-same'));
      await tester.ensureVisible(skip);
      await tester.tap(skip);
      await tester.pump();
      expect(executor.permissions, 1);
      expect(executor.questions, [{}]);
      expect(owner.current.pendingOperations, hasLength(2));
      executor.approval.complete(const AgentCommandOutcome.succeeded());
      await tester.pump();
      expect(owner.current.pendingOperations, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );
}

class _WaitingExecutor implements AgentConversationCommandPort {
  final send = Completer<AgentCommandOutcome>();
  final approval = Completer<AgentCommandOutcome>();
  final texts = <String>[];
  int permissions = 0;
  final questions = <Map<String, List<String>>>[];
  @override
  Future<AgentCommandOutcome> sendMessage(
    String text, {
    List<String> localImagePaths = const [],
    List<({String name, String path})> mentions = const [],
    List<AgentSkillRef> skills = const [],
    AgentPermissionRequestSnapshot? permissionSnapshotOverride,
  }) {
    texts.add(text);
    return send.future;
  }

  @override
  Future<AgentCommandOutcome> respondToPermission(
    AgentPermissionRequest request, {
    required bool approved,
    bool cancelTurn = false,
    AgentCommandApprovalDecisionKind? commandDecision,
    List<String> execpolicyAmendment = const [],
  }) {
    permissions++;
    return approval.future;
  }

  @override
  Future<AgentCommandOutcome> respondToQuestion(
    AgentQuestionRequest request, {
    Map<String, List<String>> answers = const {},
  }) {
    questions.add(answers);
    return approval.future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnsupportedError('Unexpected UI command');
}

class _SkillsProvider extends AgentPaneModeFakeProvider
    implements AgentSkillsPort {
  _SkillsProvider() : super(models: agentPaneModelConfigList);
  @override
  AgentProviderCapabilities get capabilities =>
      super.capabilities.copyWith(supportsSkillInput: true);
  @override
  Stream<void> get skillsChanged => const Stream.empty();
  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const [],
    bool forceReload = false,
  }) async => AgentSkillsCatalog(
    entries: [
      AgentSkillsCatalogEntry(
        cwd: '/repo',
        skills: const [
          AgentSkillMetadata(
            name: 'fixture',
            displayName: 'Fixture Skill',
            path: '/repo/SKILL.md',
            description: 'Fixture skill',
            enabled: true,
          ),
        ],
      ),
    ],
  );
}

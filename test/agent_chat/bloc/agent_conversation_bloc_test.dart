import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:desktop_platform_repository/desktop_platform_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/agent_chat/agent_chat.dart';

class _MockAgentProviderRepository extends Mock
    implements AgentProviderRepository {}

class _MockAgentConversationRepository extends Mock
    implements AgentConversationRepository {}

class _MockConversationHandle extends Mock implements ConversationHandle {}

class _MockRuntimePort extends Mock implements AgentRuntimePort {}

class _MockConversationPort extends Mock implements AgentConversationPort {}

class _MockThreadNamingPort extends Mock implements AgentThreadNamingPort {}

class _MockDeniedActionPort extends Mock
    implements AgentDeniedActionOverridePort {}

class _MockThreadBranchingPort extends Mock
    implements AgentThreadBranchingPort {}

class _MockThreadArchivalPort extends Mock implements AgentThreadArchivalPort {}

class _MockThreadCompactionPort extends Mock
    implements AgentThreadCompactionPort {}

class _MockDesktopPlatformRepository extends Mock
    implements DesktopPlatformRepository {}

class _MockThreadDeletionPort extends Mock implements AgentThreadDeletionPort {}

class _MockLocalThreadListPort extends Mock
    implements AgentLocalThreadListPort {}

class _MockThreadSubscriptionPort extends Mock
    implements AgentThreadSubscriptionPort {}

class _MockUsageQuotaPort extends Mock implements AgentUsageQuotaProvider {}

void main() {
  const key = ConversationKey.thread(
    providerId: 'codex',
    threadId: 'thread-1',
  );
  const context = AgentContext(projectPath: '/repo');
  final permission = AgentPermissionRequest(
    id: 'perm-1',
    title: 'Run command',
    kind: AgentPermissionKind.commandExecution,
  );
  final question = AgentQuestionRequest(
    id: 'q-1',
    title: 'Choose',
    questions: const <AgentUserInputQaPair>[],
  );
  final plan = AgentPlanApprovalRequest(
    id: 'plan-1',
    title: 'Plan',
    markdown: 'do work',
    sessionId: 'session-1',
    turnId: 'turn-1',
    continuation: AgentPlanApprovalContinuation.localExecutionHandoff,
  );
  final snapshot = ConversationSnapshot(
    key: key,
    phase: ConversationPhase.ready,
    generation: 1,
    revision: 1,
    turns: <ConversationTurnSnapshot>[
      ConversationTurnSnapshot(
        id: 'turn-1',
        entries: const <ConversationTimelineEntry>[
          ConversationMessageEntry(
            id: 'msg-1',
            turnId: 'turn-1',
            role: AgentMessageRole.user,
            text: 'hello',
          ),
        ],
      ),
    ],
    pendingPermissions: <AgentPermissionRequest>[permission],
    pendingQuestions: <AgentQuestionRequest>[question],
    pendingPlanApprovals: <AgentPlanApprovalRequest>[plan],
    autoReviewsByTurnId: const <String, AgentAutoApprovalReviewEvent>{},
    threadName: 'First',
  );

  group(AgentConversationBloc, () {
    late AgentProviderRepository providers;
    late AgentConversationRepository conversations;
    late DesktopPlatformRepository desktop;
    late ConversationHandle handle;
    late AgentRuntimePort runtime;
    late AgentProviderBundle bundle;
    late StreamController<ConversationSnapshot> snapshotStream;
    late StreamController<ProviderConfigSnapshot> configStream;

    setUpAll(() {
      registerFallbackValue(key);
      registerFallbackValue(context);
      registerFallbackValue(const TurnRequest());
      registerFallbackValue(const SteerRequest());
      registerFallbackValue(
        AgentPermissionDecision(requestId: 'perm-1', approved: true),
      );
      registerFallbackValue(AgentQuestionResponse(requestId: 'q-1'));
      registerFallbackValue(
        const AgentPlanApprovalDecision(
          requestId: 'plan-1',
          kind: AgentPlanApprovalDecisionKind.accepted,
        ),
      );
      registerFallbackValue(const AgentModelSelection());
      registerFallbackValue(
        const AgentPermissionSelection(optionId: 'default'),
      );
      registerFallbackValue(
        const AgentDeniedActionOverrideRequest(
          threadId: 'thread-1',
          requestId: 'perm-1',
        ),
      );
    });

    setUp(() {
      providers = _MockAgentProviderRepository();
      conversations = _MockAgentConversationRepository();
      desktop = _MockDesktopPlatformRepository();
      handle = _MockConversationHandle();
      runtime = _MockRuntimePort();
      bundle = AgentProviderBundle(
        runtime: runtime,
        conversation: _MockConversationPort(),
        threadNaming: _MockThreadNamingPort(),
        threadArchival: _MockThreadArchivalPort(),
        threadCompaction: _MockThreadCompactionPort(),
        threadBranching: _MockThreadBranchingPort(),
        threadDeletion: _MockThreadDeletionPort(),
        localThreadList: _MockLocalThreadListPort(),
        threadSubscription: _MockThreadSubscriptionPort(),
        deniedActionOverride: _MockDeniedActionPort(),
        usageQuota: _MockUsageQuotaPort(),
      );
      when(() => runtime.config).thenReturn(AgentProviderConfig.defaultCodex);
      when(() => runtime.capabilities).thenReturn(
        const AgentProviderCapabilities(
          canPrompt: true,
          canCancelTurn: true,
          canSteerTurn: true,
          canRenameThread: true,
          canArchiveThread: true,
          canForkThread: true,
          canCompactThread: true,
          supportsModelSelection: true,
        ),
      );
      when(() => runtime.updateModelSelection(any())).thenReturn(null);
      registerFallbackValue(bundle);
      when(() => providers.bundleFor(any())).thenReturn(bundle);
      when(() => providers.configChanges).thenAnswer(
        (_) => const Stream<ProviderConfigSnapshot>.empty(),
      );
      when(
        () => conversations.openConversation(
          bundle: any(named: 'bundle'),
          key: any(named: 'key'),
          context: any(named: 'context'),
        ),
      ).thenAnswer((_) async => handle);
      when(() => conversations.snapshots(any())).thenAnswer(
        (_) => const Stream<ConversationSnapshot>.empty(),
      );
      when(() => conversations.snapshotOf(any())).thenReturn(snapshot);
      when(() => handle.release()).thenAnswer((_) async {});
      when(
        () => conversations.closeConversation(any()),
      ).thenAnswer((_) async {});
      when(
        () => conversations.submit(
          key: any(named: 'key'),
          request: any(named: 'request'),
        ),
      ).thenAnswer((_) async => AgentTurn(id: 't1', sessionId: 's1'));
      when(() => conversations.cancel(any())).thenAnswer((_) async {});
      when(
        () => conversations.steer(
          key: any(named: 'key'),
          request: any(named: 'request'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => conversations.respondToPermission(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => conversations.respondToQuestion(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => conversations.respondToPlanApproval(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => providers.persistDefaultModel(any(), any()),
      ).thenAnswer((_) async {});
      when(
        () => providers.applyPermissionSelection(any(), any()),
      ).thenAnswer(
        (_) async => const AgentPermissionApplyResult(
          normalizedSelection: AgentPermissionSelection(optionId: 'default'),
          scope: AgentPermissionApplyScope.currentTurn,
        ),
      );
      when(() => providers.conversationModes(any())).thenAnswer(
        (_) async => AgentConversationModeCatalog(
          presets: const <AgentConversationModePreset>[],
        ),
      );
      when(() => providers.modelCatalog(any())).thenAnswer(
        (_) async => AgentModelList(models: const <AgentModelInfo>[]),
      );
      when(() => providers.permissionOptions(any())).thenAnswer(
        (_) async => AgentPermissionCatalog(
          options: const <AgentPermissionOption>[],
          defaultOptionId: 'default',
        ),
      );
      when(
        () => providers.skills(any(), cwds: any(named: 'cwds')),
      ).thenAnswer((_) async => AgentSkillsCatalog.empty);
      when(
        () => bundle.threadBranching!.forkThread(
          threadId: any(named: 'threadId'),
          context: any(named: 'context'),
        ),
      ).thenAnswer(
        (_) async => AgentSession(id: 's1', providerId: 'codex'),
      );
      when(
        () => bundle.threadArchival!.archiveThread(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.threadCompaction!.compactThread(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.deniedActionOverride!.approveDeniedAction(any()),
      ).thenAnswer((_) async {});
      when(
        () => desktop.pickFiles(
          acceptedTypes: any(named: 'acceptedTypes'),
        ),
      ).thenAnswer((_) async => const <String>[]);
      when(() => desktop.readText()).thenAnswer((_) async => '');
      when(
        () => bundle.threadDeletion!.deleteThread(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.localThreadList!.removeThreadFromList(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.threadSubscription!.unsubscribeThread(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.threadArchival!.unarchiveThread(any()),
      ).thenAnswer((_) async {});
      when(
        () => bundle.usageQuota!.readUsageQuota(),
      ).thenAnswer((_) async => null);
    });

    AgentConversationBloc build() {
      return AgentConversationBloc(
        agentProviderRepository: providers,
        agentConversationRepository: conversations,
        desktopPlatformRepository: desktop,
      );
    }

    AgentConversationState ready() {
      return AgentConversationState(
        key: key,
        status: AgentConversationStatus.ready,
        pending: AgentPendingInteractionState(
          permissions: <AgentPermissionRequest>[permission],
          questions: <AgentQuestionRequest>[question],
          planApprovals: <AgentPlanApprovalRequest>[plan],
        ),
        composer: const AgentComposerState(canSubmitMessage: true),
        expansion: const AgentExpansionState(toolCallIds: <String>{'msg-1'}),
        history: const AgentConversationHistoryState(visibleLimit: 1),
      );
    }

    blocTest<AgentConversationBloc, AgentConversationState>(
      'resolves the bundle then opens the conversation',
      build: build,
      act: (bloc) {
        bloc.add(const AgentConversationOpened(key: key, context: context));
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        verifyInOrder(<void Function()>[
          () => providers.bundleFor('codex'),
          () => conversations.openConversation(
            bundle: bundle,
            key: key,
            context: context,
          ),
        ]);
        expect(bloc.state.status, AgentConversationStatus.ready);
        expect(bloc.state.header.title, 'First');
        expect(bloc.state.history.visibleTurns, isNotEmpty);
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'drops snapshots from a previous generation',
      build: build,
      act: (bloc) {
        bloc.add(
          AgentConversationSnapshotUpdated(
            snapshot: snapshot,
            generation: 99,
          ),
        );
      },
      expect: () => const <AgentConversationState>[],
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'submits a message through the conversation repository',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc.add(const AgentMessageSubmitted(message: 'hello'));
      },
      verify: (_) {
        verify(
          () => conversations.submit(
            key: key,
            request: any(named: 'request'),
          ),
        ).called(1);
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'responding to permission never preauthorizes other semantics',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc.add(
          AgentPermissionResponded(
            AgentPermissionDecision(requestId: 'perm-1', approved: true),
          ),
        );
      },
      verify: (_) {
        verify(
          () => conversations.respondToPermission(any(), any()),
        ).called(1);
        verifyNever(() => conversations.respondToQuestion(any(), any()));
        verifyNever(() => conversations.respondToPlanApproval(any(), any()));
        verifyNever(
          () => conversations.submit(
            key: any(named: 'key'),
            request: any(named: 'request'),
          ),
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'responding to a question never preauthorizes other semantics',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc.add(
          AgentQuestionResponded(AgentQuestionResponse(requestId: 'q-1')),
        );
      },
      verify: (_) {
        verify(() => conversations.respondToQuestion(any(), any())).called(1);
        verifyNever(() => conversations.respondToPermission(any(), any()));
        verifyNever(() => conversations.respondToPlanApproval(any(), any()));
        verifyNever(
          () => conversations.submit(
            key: any(named: 'key'),
            request: any(named: 'request'),
          ),
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'approving a plan never preauthorizes other semantics',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc.add(
          const AgentPlanApprovalResponded(
            AgentPlanApprovalDecision(
              requestId: 'plan-1',
              kind: AgentPlanApprovalDecisionKind.accepted,
            ),
          ),
        );
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        verify(
          () => conversations.respondToPlanApproval(any(), any()),
        ).called(1);
        verifyNever(() => conversations.respondToPermission(any(), any()));
        verifyNever(() => conversations.respondToQuestion(any(), any()));
        verifyNever(
          () => conversations.submit(
            key: any(named: 'key'),
            request: any(named: 'request'),
          ),
        );
        expect(bloc.state.pending.planExecutionHandoff, isNotNull);
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'starting plan execution never preauthorizes other semantics',
      build: build,
      seed: () => ready().copyWith(
        pending: const AgentPendingInteractionState(
          planExecutionHandoff: AgentPlanExecutionRequest(
            id: 'handoff-1',
            sessionId: 'session-1',
            turnId: 'turn-1',
            title: 'Plan',
            markdown: 'do work',
          ),
        ),
      ),
      act: (bloc) {
        bloc.add(const AgentPlanExecutionStarted());
      },
      verify: (_) {
        verify(
          () => conversations.submit(
            key: key,
            request: any(named: 'request'),
          ),
        ).called(1);
        verifyNever(() => conversations.respondToPermission(any(), any()));
        verifyNever(() => conversations.respondToQuestion(any(), any()));
        verifyNever(() => conversations.respondToPlanApproval(any(), any()));
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'toggles expansion and garbage-collects stale ids',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc
          ..add(const AgentToolCallToggled('msg-1'))
          ..add(const AgentPlanMessageToggled('plan-msg'))
          ..add(const AgentActivePlanToggled('turn-1'))
          ..add(const AgentCommandGroupToggled('cmd-1'))
          ..add(const AgentFileEditItemToggled('file-1'))
          ..add(const AgentContextPanelToggled())
          ..add(
            AgentConversationSnapshotUpdated(
              snapshot: snapshot,
              generation: 0,
            ),
          );
        bloc.add(
          AgentConversationSnapshotUpdated(
            snapshot: snapshot,
            generation: bloc.state.generation,
          ),
        );
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(bloc.state.expansion.isToolCallExpanded('msg-1'), isFalse);
        expect(
          bloc.state.expansion.isPlanMessageExpanded('plan-msg'),
          isFalse,
        );
        expect(bloc.state.composer.contextPanelVisible, isTrue);
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'renames through the bundle naming port',
      build: () {
        when(
          () => bundle.threadNaming!.renameThread(
            threadId: any(named: 'threadId'),
            name: any(named: 'name'),
          ),
        ).thenAnswer((_) async {});
        return build();
      },
      seed: ready,
      act: (bloc) async {
        bloc.add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AgentThreadRenamed('New'));
      },
      wait: const Duration(milliseconds: 20),
      verify: (_) {
        verify(
          () => bundle.threadNaming!.renameThread(
            threadId: 'thread-1',
            name: 'New',
          ),
        ).called(1);
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'fails closed when a write capability is missing',
      build: () {
        when(() => runtime.capabilities).thenReturn(
          const AgentProviderCapabilities(canPrompt: true),
        );
        bundle = AgentProviderBundle(
          runtime: runtime,
          conversation: _MockConversationPort(),
        );
        when(() => providers.bundleFor(any())).thenReturn(bundle);
        return build();
      },
      act: (bloc) async {
        bloc.add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AgentThreadArchived());
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(
          bloc.state.failure?.code,
          AgentConversationFailureCode.operationUnsupported,
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'releases subscriptions and the conversation key on close',
      build: build,
      act: (bloc) async {
        bloc.add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 10));
        await bloc.close();
      },
      verify: (_) {
        verify(() => handle.release()).called(greaterThanOrEqualTo(1));
        verify(
          () => conversations.closeConversation(any()),
        ).called(greaterThanOrEqualTo(1));
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'cancels, steers, and dismisses plan execution locally',
      build: build,
      seed: () => ready().copyWith(
        pending: const AgentPendingInteractionState(
          planExecutionHandoff: AgentPlanExecutionRequest(
            id: 'handoff-1',
            sessionId: 'session-1',
            turnId: 'turn-1',
            title: 'Plan',
            markdown: 'do work',
          ),
        ),
      ),
      act: (bloc) {
        bloc
          ..add(const AgentTurnCancelled())
          ..add(const AgentTurnSteered(message: 'steer'))
          ..add(const AgentPlanExecutionDismissed())
          ..add(const AgentPlanExecutionRevised())
          ..add(const AgentHistoryWindowChanged(2))
          ..add(const AgentFastToggled(enabled: true))
          ..add(const AgentModelConfigTransientCleared())
          ..add(
            const AgentConversationModeSelected(AgentConversationModeId.plan),
          );
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        verify(() => conversations.cancel(key)).called(1);
        verify(
          () => conversations.steer(
            key: key,
            request: any(named: 'request'),
          ),
        ).called(1);
        expect(bloc.state.pending.planExecutionHandoff, isNull);
        expect(bloc.state.header.isPlanMode, isTrue);
      },
    );

    test('event equality uses value props', () {
      expect(const AgentConversationClosed().props, isEmpty);
      expect(
        const AgentConversationOpened(key: key, context: context).props,
        <Object?>[key, context],
      );
      expect(const AgentMessageSubmitted(message: 'a').props, <Object?>[
        'a',
        null,
        null,
      ]);
      expect(
        const AgentThreadRenamed('n').props,
        <Object?>['n'],
      );
      expect(const AgentFastToggled(enabled: true).props, <Object?>[true]);
      expect(const AgentHistoryWindowChanged(3).props, <Object?>[3]);
      expect(
        const AgentProviderSwitched(key: key, context: context).props,
        <Object?>[key, context],
      );
      expect(const AgentContextUpdated(context).props, <Object?>[context]);
      expect(
        AgentConversationSnapshotUpdated(
          snapshot: snapshot,
          generation: 1,
        ).props,
        <Object?>[snapshot, 1],
      );
      expect(const AgentTurnCancelled().props, isEmpty);
      expect(const AgentTurnSteered(message: 's').props, <Object?>['s', null]);
      expect(const AgentLastUserMessageEdited('e').props, <Object?>['e']);
      expect(const AgentThreadForked().props, isEmpty);
      expect(const AgentThreadArchived().props, isEmpty);
      expect(const AgentThreadCompacted().props, isEmpty);
      expect(
        AgentPermissionResponded(
          AgentPermissionDecision(requestId: 'p', approved: true),
        ).props,
        isNotEmpty,
      );
      expect(
        AgentQuestionResponded(AgentQuestionResponse(requestId: 'q')).props,
        isNotEmpty,
      );
      expect(
        const AgentPlanApprovalResponded(
          AgentPlanApprovalDecision(
            requestId: 'plan',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        ).props,
        isNotEmpty,
      );
      expect(
        const AgentPlanExecutionStarted(message: 'm').props,
        <Object?>['m'],
      );
      expect(const AgentPlanExecutionRevised().props, isEmpty);
      expect(const AgentPlanExecutionDismissed().props, isEmpty);
      expect(
        const AgentDeniedActionApproved(
          AgentDeniedActionOverrideRequest(
            threadId: 'thread-1',
            requestId: 'perm-1',
          ),
        ).props,
        isNotEmpty,
      );
      expect(const AgentModelSelected('gpt').props, <Object?>['gpt']);
      expect(
        const AgentReasoningEffortSelected('high').props,
        <Object?>['high'],
      );
      expect(const AgentServiceTierSelected('flex').props, <Object?>['flex']);
      expect(const AgentModelConflictResolved().props, isEmpty);
      expect(const AgentModelConfigSaveRetried().props, isEmpty);
      expect(const AgentModelConfigTransientCleared().props, isEmpty);
      expect(const AgentPermissionOptionSelected('id').props, <Object?>['id']);
      expect(const AgentPermissionPersistenceRetried().props, isEmpty);
      expect(
        const AgentConversationModeSelected(AgentConversationModeId.plan).props,
        isNotEmpty,
      );
      expect(const AgentConversationModesRetried().props, isEmpty);
      expect(const AgentSessionConfigOptionSelected('o').props, <Object?>['o']);
      expect(
        const AgentPlanExecutionPermissionSelected('o').props,
        <Object?>['o'],
      );
      expect(const AgentModelsRequested().props, isEmpty);
      expect(const AgentSkillsCatalogRequested().props, isEmpty);
      expect(const AgentSettingsRequested().props, isEmpty);
      expect(const AgentToolCallToggled('a').props, <Object?>['a']);
      expect(const AgentPlanMessageToggled('a').props, <Object?>['a']);
      expect(const AgentActivePlanToggled('a').props, <Object?>['a']);
      expect(const AgentCommandGroupToggled('a').props, <Object?>['a']);
      expect(const AgentFileEditItemToggled('a').props, <Object?>['a']);
      expect(
        const AgentContextPanelToggled(visible: true).props,
        <Object?>[true],
      );
      expect(const AgentThreadUnarchived().props, isEmpty);
      expect(const AgentThreadDeleted().props, isEmpty);
      expect(const AgentThreadRemovedFromList().props, isEmpty);
      expect(const AgentThreadUnsubscribed().props, isEmpty);
      expect(const AgentImagesAttachRequested().props, isEmpty);
      expect(const AgentFilesMentionRequested().props, isEmpty);
      expect(const AgentClipboardPasteRequested().props, isEmpty);
      expect(const AgentQuotaRequested().props, isEmpty);
    });

    blocTest<AgentConversationBloc, AgentConversationState>(
      'covers remaining lifecycle, catalogs, and selection events',
      build: build,
      act: (bloc) async {
        bloc.add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc
          ..add(const AgentProviderSwitched(key: key, context: context))
          ..add(const AgentContextUpdated(context))
          ..add(const AgentConversationClosed())
          ..add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc
          ..add(const AgentThreadForked())
          ..add(const AgentThreadCompacted())
          ..add(const AgentThreadUnarchived())
          ..add(const AgentThreadDeleted())
          ..add(const AgentThreadRemovedFromList())
          ..add(const AgentThreadUnsubscribed())
          ..add(const AgentImagesAttachRequested())
          ..add(const AgentFilesMentionRequested())
          ..add(const AgentClipboardPasteRequested())
          ..add(const AgentQuotaRequested())
          ..add(const AgentLastUserMessageEdited('retry'))
          ..add(
            const AgentDeniedActionApproved(
              AgentDeniedActionOverrideRequest(
                threadId: 'thread-1',
                requestId: 'perm-1',
              ),
            ),
          )
          ..add(const AgentModelSelected('gpt'))
          ..add(const AgentReasoningEffortSelected('high'))
          ..add(const AgentServiceTierSelected('flex'))
          ..add(const AgentModelConflictResolved())
          ..add(const AgentModelConfigSaveRetried())
          ..add(const AgentPermissionOptionSelected('default'))
          ..add(const AgentPermissionPersistenceRetried())
          ..add(const AgentConversationModesRetried())
          ..add(const AgentSessionConfigOptionSelected('opt'))
          ..add(const AgentPlanExecutionPermissionSelected('default'))
          ..add(const AgentModelsRequested())
          ..add(const AgentSkillsCatalogRequested())
          ..add(const AgentSettingsRequested())
          ..add(const AgentContextPanelToggled(visible: false));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.key, key);
        verify(() => providers.modelCatalog(any())).called(greaterThan(0));
        verify(() => providers.skills(any(), cwds: any(named: 'cwds'))).called(
          greaterThan(0),
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'applies live snapshots, catalogs, and remaining write paths',
      build: () {
        snapshotStream = StreamController<ConversationSnapshot>.broadcast();
        configStream = StreamController<ProviderConfigSnapshot>.broadcast();
        when(() => conversations.snapshots(any())).thenAnswer(
          (_) => snapshotStream.stream,
        );
        when(() => providers.configChanges).thenAnswer(
          (_) => configStream.stream,
        );
        when(() => providers.skills(any(), cwds: any(named: 'cwds'))).thenThrow(
          Exception('skills'),
        );
        when(
          () => providers.persistDefaultModel(any(), any()),
        ).thenThrow(Exception('save'));
        addTearDown(snapshotStream.close);
        addTearDown(configStream.close);
        return build();
      },
      act: (bloc) async {
        bloc.add(const AgentConversationOpened(key: key, context: context));
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final live = ConversationSnapshot(
          key: key,
          phase: ConversationPhase.ready,
          generation: 1,
          revision: 3,
          turns: <ConversationTurnSnapshot>[
            ConversationTurnSnapshot(
              id: 'turn-1',
              entries: const <ConversationTimelineEntry>[],
              startedAt: DateTime.utc(2026, 8, 20),
            ),
            ConversationTurnSnapshot(
              id: 'turn-2',
              entries: const <ConversationTimelineEntry>[],
            ),
            ConversationTurnSnapshot(
              id: 'turn-3',
              entries: const <ConversationTimelineEntry>[],
            ),
          ],
          pendingPermissions: const <AgentPermissionRequest>[],
          pendingQuestions: const <AgentQuestionRequest>[],
          pendingPlanApprovals: <AgentPlanApprovalRequest>[plan],
          autoReviewsByTurnId: <String, AgentAutoApprovalReviewEvent>{
            'turn-1': AgentAutoApprovalReviewEvent(
              threadId: 'thread-1',
              turnId: 'turn-1',
              reviewId: 'r1',
              status: 'denied',
            ),
          },
          activeTurn: AgentTurn(id: 'turn-1', sessionId: 's1'),
          waitingOnApproval: true,
          waitingOnUserInput: true,
        );
        snapshotStream.add(live);
        configStream.add(ProviderConfigSnapshot.empty);
        when(() => conversations.snapshotOf(any())).thenReturn(live);
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc
          ..add(const AgentHistoryWindowChanged(1))
          ..add(const AgentThreadArchived())
          ..add(const AgentSkillsCatalogRequested())
          ..add(
            const AgentConversationModeSelected(AgentConversationModeId.plan),
          )
          ..add(const AgentModelSelected('gpt'))
          ..add(const AgentMessageSubmitted(message: 'go'))
          ..add(
            const AgentPlanApprovalResponded(
              AgentPlanApprovalDecision(
                requestId: 'plan-1',
                kind: AgentPlanApprovalDecisionKind.accepted,
              ),
            ),
          );
        await Future<void>.delayed(const Duration(milliseconds: 10));
        bloc.add(const AgentPlanExecutionPermissionSelected('default'));
      },
      wait: const Duration(milliseconds: 40),
      verify: (bloc) {
        expect(bloc.state.pending.latestDeniedAutoReview, isNotNull);
        expect(
          bloc.state.pending.planExecutionHandoff?.executionPermission,
          isNotNull,
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'emits failure when opening the conversation throws',
      build: () {
        when(
          () => conversations.openConversation(
            bundle: any(named: 'bundle'),
            key: any(named: 'key'),
            context: any(named: 'context'),
          ),
        ).thenThrow(
          const AgentConversationRepositoryException(
            failure: AgentConversationFailure(
              AgentConversationFailureCode.historyReadFailed,
            ),
          ),
        );
        return build();
      },
      act: (bloc) {
        bloc.add(const AgentConversationOpened(key: key, context: context));
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(
          bloc.state.failure?.code,
          AgentConversationFailureCode.historyReadFailed,
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'skips context reload until the conversation is ready',
      build: build,
      act: (bloc) {
        bloc.add(const AgentContextUpdated(context));
      },
      expect: () => const <AgentConversationState>[],
    );

    test('copyWith clears optional conversation fields', () {
      const failure = AgentConversationFailure(
        AgentConversationFailureCode.noActiveTurn,
      );
      const state = AgentConversationState(key: key, failure: failure);
      final cleared = state.copyWith(clearFailure: true);
      expect(cleared.failure, isNull);
      expect(
        const AgentExpansionState().isToolCallExpanded('x'),
        isFalse,
      );
      expect(const AgentPendingInteractionState().isEmpty, isTrue);
      expect(const AgentPendingInteractionState().blocksComposer, isFalse);
      const expanded = AgentExpansionState(
        planMessageIds: <String>{'p'},
        activePlanTurnIds: <String>{'t'},
        commandGroupIds: <String>{'c'},
        fileEditItemIds: <String>{'f'},
      );
      expect(expanded.isPlanMessageExpanded('p'), isTrue);
      expect(expanded.isActivePlanExpanded('t'), isTrue);
      expect(expanded.isCommandGroupExpanded('c'), isTrue);
      expect(expanded.isFileEditItemExpanded('f'), isTrue);
      const loading = AgentConversationHistoryState(
        threadOpenPhase: AgentThreadOpenPhase.loadingHistory,
      );
      expect(loading.isLoading, isTrue);
      final withStandby = loading.copyWith(
        standbyTurn: const AgentConversationTurnGroup(id: 's'),
        visibleTurns: const <AgentConversationTurnGroup>[
          AgentConversationTurnGroup(id: 'v'),
        ],
        threadOpenPhase: AgentThreadOpenPhase.idle,
        providerId: 'codex',
        providerKind: AgentProviderKind.acp,
        providerName: 'Codex',
        visibleLimit: 2,
      );
      expect(withStandby.standbyTurn?.id, 's');
      expect(withStandby.copyWith(clearStandby: true).standbyTurn, isNull);
    });

    blocTest<AgentConversationBloc, AgentConversationState>(
      'fails closed when quota is requested without a usage port',
      build: build,
      seed: ready,
      act: (bloc) {
        bloc.add(const AgentQuotaRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(
          bloc.state.failure?.code,
          AgentConversationFailureCode.operationUnsupported,
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'fails closed when an unsupported platform capability is invoked',
      build: () {
        when(
          () => desktop.pickFiles(
            acceptedTypes: any(named: 'acceptedTypes'),
          ),
        ).thenThrow(
          const DesktopPlatformException(
            operation: DesktopPlatformOperation.pickFiles,
            cause: 'missing',
          ),
        );
        return build();
      },
      seed: ready,
      act: (bloc) {
        bloc.add(const AgentImagesAttachRequested());
      },
      wait: const Duration(milliseconds: 10),
      verify: (bloc) {
        expect(
          bloc.state.failure?.code,
          AgentConversationFailureCode.providerOperationFailed,
        );
      },
    );

    blocTest<AgentConversationBloc, AgentConversationState>(
      'keeps timeline order across an event storm of snapshots',
      build: build,
      seed: ready,
      act: (bloc) {
        for (var index = 0; index < 40; index++) {
          bloc.add(
            AgentConversationSnapshotUpdated(
              snapshot: ConversationSnapshot(
                key: key,
                phase: ConversationPhase.ready,
                generation: 1,
                revision: index + 1,
                turns: <ConversationTurnSnapshot>[
                  ConversationTurnSnapshot(
                    id: 'turn-$index',
                    entries: const <ConversationTimelineEntry>[],
                  ),
                ],
                pendingPermissions: const <AgentPermissionRequest>[],
                pendingQuestions: const <AgentQuestionRequest>[],
                pendingPlanApprovals: const <AgentPlanApprovalRequest>[],
                autoReviewsByTurnId:
                    const <String, AgentAutoApprovalReviewEvent>{},
              ),
              generation: 0,
            ),
          );
        }
      },
      wait: const Duration(milliseconds: 20),
      verify: (bloc) {
        expect(bloc.state.history.visibleTurns, hasLength(1));
        expect(bloc.state.history.visibleTurns.single.id, 'turn-39');
      },
    );
  });
}

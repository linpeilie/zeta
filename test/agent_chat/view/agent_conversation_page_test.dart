import 'dart:async';

import 'package:agent_conversation_repository/agent_conversation_repository.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:agent_provider_repository/agent_provider_repository.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:zeta/agent_chat/agent_chat.dart';
import 'package:zeta/l10n/l10n.dart';

import '../../helpers/helpers.dart';

class _MockAgentConversationBloc
    extends MockBloc<AgentConversationEvent, AgentConversationState>
    implements AgentConversationBloc {}

class _MockAgentProviderRepository extends Mock
    implements AgentProviderRepository {}

class _MockAgentConversationRepository extends Mock
    implements AgentConversationRepository {}

class _MockConversationHandle extends Mock implements ConversationHandle {}

class _MockRuntimePort extends Mock implements AgentRuntimePort {}

class _MockConversationPort extends Mock implements AgentConversationPort {}

void main() {
  const key = ConversationKey.thread(
    providerId: 'codex',
    threadId: 'thread-1',
  );

  group(AgentConversationPage, () {
    late AgentProviderRepository providers;
    late AgentConversationRepository conversations;
    late ConversationHandle handle;
    late AgentRuntimePort runtime;

    setUp(() {
      providers = _MockAgentProviderRepository();
      conversations = _MockAgentConversationRepository();
      handle = _MockConversationHandle();
      runtime = _MockRuntimePort();
      final bundle = AgentProviderBundle(
        runtime: runtime,
        conversation: _MockConversationPort(),
      );
      registerFallbackValue(bundle);
      registerFallbackValue(key);
      registerFallbackValue(const AgentContext());
      when(() => runtime.config).thenReturn(AgentProviderConfig.defaultCodex);
      when(
        () => runtime.capabilities,
      ).thenReturn(AgentProviderCapabilities.unsupported);
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
      when(() => conversations.snapshotOf(any())).thenReturn(null);
      when(() => handle.release()).thenAnswer((_) async {});
      when(
        () => conversations.closeConversation(any()),
      ).thenAnswer((_) async {});
    });

    testWidgets('opens a thread-backed conversation', (tester) async {
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<AgentProviderRepository>.value(
              value: providers,
            ),
            RepositoryProvider<AgentConversationRepository>.value(
              value: conversations,
            ),
          ],
          child: const AgentConversationPage(
            providerId: 'codex',
            threadId: 'thread-1',
          ),
        ),
      );
      await tester.pump();
      expect(find.byType(AgentConversationView), findsOneWidget);
    });

    testWidgets('renders $AgentConversationView', (tester) async {
      await tester.pumpApp(
        MultiRepositoryProvider(
          providers: <RepositoryProvider<dynamic>>[
            RepositoryProvider<AgentProviderRepository>.value(
              value: providers,
            ),
            RepositoryProvider<AgentConversationRepository>.value(
              value: conversations,
            ),
          ],
          child: const AgentConversationPage(providerId: 'codex'),
        ),
      );
      await tester.pump();
      expect(find.byType(AgentConversationView), findsOneWidget);
    });
  });

  group(AgentConversationView, () {
    late AgentConversationBloc bloc;

    setUp(() {
      bloc = _MockAgentConversationBloc();
      registerFallbackValue(const AgentConversationClosed());
      when(() => bloc.state).thenReturn(
        const AgentConversationState(
          status: AgentConversationStatus.ready,
          composer: AgentComposerState(canSubmitMessage: true),
        ),
      );
    });

    testWidgets('submits a message from the composer', (tester) async {
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text(l10n.agentSend));
      await tester.pump();
      verify(
        () => bloc.add(const AgentMessageSubmitted(message: '')),
      ).called(1);
    });

    testWidgets('renders pending permission and history rows', (tester) async {
      when(() => bloc.state).thenReturn(
        AgentConversationState(
          status: AgentConversationStatus.ready,
          header: const AgentHeaderState(title: 'First'),
          history: const AgentConversationHistoryState(
            visibleTurns: <AgentConversationTurnGroup>[
              AgentConversationTurnGroup(id: 'turn-1'),
            ],
          ),
          pending: AgentPendingInteractionState(
            permissions: <AgentPermissionRequest>[
              AgentPermissionRequest(
                id: 'perm-1',
                title: 'Run command',
                kind: AgentPermissionKind.commandExecution,
              ),
            ],
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      expect(find.text('First'), findsOneWidget);
      expect(find.text('turn-1'), findsOneWidget);
      await tester.tap(find.text('Run command'));
      await tester.pump();
      verify(
        () => bloc.add(any(that: isA<AgentPermissionResponded>())),
      ).called(1);
    });

    testWidgets('requests question, plan, cancel, and plan execution', (
      tester,
    ) async {
      when(() => bloc.state).thenReturn(
        AgentConversationState(
          status: AgentConversationStatus.ready,
          composer: const AgentComposerState(canCancelTurn: true),
          pending: AgentPendingInteractionState(
            questions: <AgentQuestionRequest>[
              AgentQuestionRequest(
                id: 'q-1',
                title: 'Choose',
                questions: const <AgentUserInputQaPair>[],
              ),
            ],
            planApprovals: <AgentPlanApprovalRequest>[
              AgentPlanApprovalRequest(
                id: 'plan-1',
                title: 'Plan',
                markdown: 'do',
              ),
            ],
            planExecutionHandoff: const AgentPlanExecutionRequest(
              id: 'handoff-1',
              sessionId: 's1',
              turnId: 't1',
              title: 'Plan',
              markdown: 'do',
            ),
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      await tester.tap(find.text('Choose'));
      await tester.tap(find.text('Plan'));
      await tester.tap(find.text(l10n.agentSubmit));
      await tester.tap(find.text(l10n.agentCancelTurn));
      await tester.pump();
      verify(
        () => bloc.add(any(that: isA<AgentQuestionResponded>())),
      ).called(1);
      verify(
        () => bloc.add(any(that: isA<AgentPlanApprovalResponded>())),
      ).called(1);
      verify(() => bloc.add(const AgentPlanExecutionStarted())).called(1);
      verify(() => bloc.add(const AgentTurnCancelled())).called(1);
    });

    testWidgets('renders a conversation failure message', (tester) async {
      when(() => bloc.state).thenReturn(
        const AgentConversationState(
          status: AgentConversationStatus.failure,
          failure: AgentConversationFailure(
            AgentConversationFailureCode.providerOperationFailed,
          ),
        ),
      );
      await tester.pumpApp(
        BlocProvider.value(value: bloc, child: const AgentConversationView()),
      );
      final l10n = lookupAppLocalizations(const Locale('en'));
      expect(
        find.text(
          FailureMessages(l10n).agentConversationFailure(
            AgentConversationFailureCode.providerOperationFailed,
          ),
        ),
        findsOneWidget,
      );
    });
  });
}

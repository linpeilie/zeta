import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/agent_command_outcome.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_actions.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_payload.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_result.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_command_scope.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_effect.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_state.dart';
import '../../../../testing/conversation_test_scope.dart';
import '../../presentation/agent_conversation_ui_state_fixtures.dart';

void main() {
  test(
    'Actions facade returns the actual owner; unknown and captured closed handles reject',
    () async {
      final h = _Harness();
      final actions = conversationTestScope.container.read(
        agentConversationActionsProvider(h.scope.bindingKey),
      );
      expect(actions, same(h.owner));
      final unknown = conversationTestScope.container.read(
        agentConversationActionsProvider(
          const AgentConversationBindingKey.draft(
            providerId: 'other',
            entryId: 'missing',
          ),
        ),
      );
      expect(
        await unknown.sendMessage('x'),
        _failed(AgentCommandFailureKind.staleTarget),
      );
      h.owner.closeForEntryRelease();
      expect(
        await actions.sendMessage('late'),
        _failed(AgentCommandFailureKind.staleTarget),
      );
      expect(
        (await actions.forkCurrentThread()).outcome,
        _failed(AgentCommandFailureKind.staleTarget),
      );
      expect(h.executor.calls, isEmpty);
    },
  );

  test(
    'send freezes every payload field before dispatch, with Unicode and original permission source',
    () async {
      final h = _Harness();
      final gate = Completer<AgentCommandOutcome>();
      h.executor.responses[#sendMessage] = (_) => gate.future;
      final paths = ['first.png'];
      final mentions = [(name: '目录😀', path: '/repo/目录')];
      final skills = [const AgentSkillRef(name: 'skill', path: '/skills/a')];
      const permission = AgentPermissionRequestSnapshot.resolved(
        selection: AgentPermissionSelection(optionId: 'chosen'),
        source: AgentPermissionRequestSource.threadEffective,
      );
      final future = h.owner.sendMessage(
        '中文😀\nnext',
        localImagePaths: paths,
        mentions: mentions,
        skills: skills,
        permissionSnapshotOverride: permission,
      );
      paths.add('late.png');
      mentions.clear();
      skills.clear();
      final call = h.executor.calls.single;
      expect(call.positionalArguments, ['中文😀\nnext']);
      expect(call.namedArguments[#localImagePaths], ['first.png']);
      expect(call.namedArguments[#mentions], [
        (name: '目录😀', path: '/repo/目录'),
      ]);
      expect(
        (call.namedArguments[#skills] as List).single,
        isA<AgentSkillRef>(),
      );
      expect(
        call.namedArguments[#permissionSnapshotOverride],
        same(permission),
      );
      expect(
        () => (call.namedArguments[#localImagePaths] as List).clear(),
        throwsUnsupportedError,
      );
      final id = h.owner.current.pendingOperations.single;
      expect(id.scope, AgentConversationOperationScopes.send);
      gate.complete(const AgentCommandOutcome.succeeded());
      expect(await future, isA<AgentCommandSucceeded>());
      expect(h.owner.current.pendingOperations, isEmpty);
      h.owner.settle(
        id,
        const AgentConversationCommandResult.regular(
          AgentCommandOutcome.failed(AgentCommandFailureKind.requestFailed),
        ),
      );
      expect(h.owner.current.lastFailure, isNull);
      expect(h.owner.diagnostics.staleResultCount, 1);
    },
  );

  test(
    'same-scope A and B settle independently; cancel bypasses their waits',
    () async {
      final h = _Harness();
      final a = Completer<AgentCommandOutcome>(),
          b = Completer<AgentCommandOutcome>();
      h.executor.responses[#sendMessage] = (i) =>
          i.positionalArguments.single == 'a' ? a.future : b.future;
      final fa = h.owner.sendMessage('a'), fb = h.owner.sendMessage('b');
      expect(h.owner.current.pendingOperations, hasLength(2));
      final bid = h.owner.current.pendingOperations.last;
      expect(await h.owner.cancelActiveTurn(), isA<AgentCommandSucceeded>());
      a.complete(
        const AgentCommandOutcome.failed(
          AgentCommandFailureKind.requestFailed,
          diagnostic: 'private text',
        ),
      );
      final result = await fa;
      expect(result, _failed(AgentCommandFailureKind.requestFailed));
      expect((result as AgentCommandFailed).diagnostic, isNull);
      expect(h.owner.current.pendingOperations, {bid});
      b.complete(const AgentCommandOutcome.succeeded());
      expect(await fb, isA<AgentCommandSucceeded>());
      expect(h.owner.current.pendingOperations, isEmpty);
    },
  );

  test(
    'two same-provider drafts promote independently, old epoch cannot commit to either',
    () async {
      final a = _Harness(draft: 'a'), b = _Harness(draft: 'b');
      final ga = Completer<AgentCommandOutcome>(),
          gb = Completer<AgentCommandOutcome>();
      a.executor.responses[#sendMessage] = (_) => ga.future;
      b.executor.responses[#sendMessage] = (_) => gb.future;
      final fa = a.owner.sendMessage('a'), fb = b.owner.sendMessage('b');
      a.scope = _threadScope('thread-a', 1);
      b.scope = _threadScope('thread-b', 1);
      ga.complete(const AgentCommandOutcome.succeeded());
      expect(await fa, isA<AgentCommandSucceeded>());
      expect(b.owner.current.pendingOperations, hasLength(1));
      gb.complete(const AgentCommandOutcome.succeeded());
      expect(await fb, isA<AgentCommandSucceeded>());
      final late = Completer<AgentCommandOutcome>();
      a.executor.responses[#sendMessage] = (_) => late.future;
      final stale = a.owner.sendMessage('old epoch');
      a.scope = _threadScope('thread-a', 2);
      late.complete(const AgentCommandOutcome.succeeded());
      expect(await stale, _failed(AgentCommandFailureKind.staleTarget));
      expect(b.owner.current.lastFailure, isNull);
    },
  );

  test(
    'close immediately settles queued and running requests; late fork cannot revive owner',
    () async {
      final h = _Harness();
      final permission = Completer<AgentCommandOutcome>();
      final fork = Completer<AgentForkCommandOutcome>();
      h.executor.responses[#selectPermissionOption] = (_) => permission.future;
      h.executor.responses[#forkCurrentThread] = (_) => fork.future;
      final first = h.owner.selectPermissionOption(_option);
      final queued = h.owner.retryPermissionPreferencePersistence();
      final branched = h.owner.forkCurrentThread();
      h.owner.closeForEntryRelease();
      expect(await first, _failed(AgentCommandFailureKind.staleTarget));
      expect(await queued, _failed(AgentCommandFailureKind.staleTarget));
      expect(
        (await branched).outcome,
        _failed(AgentCommandFailureKind.staleTarget),
      );
      permission.complete(const AgentCommandOutcome.succeeded());
      fork.complete(AgentForkCommandOutcome.completed(_session));
      await _flush();
      expect(h.executor.calls.map((i) => i.memberName), [
        #selectPermissionOption,
        #forkCurrentThread,
      ]);
      expect(h.owner.current.pendingOperations, isEmpty);
      expect(
        h.owner.current.projectionStatus,
        AgentConversationProjectionStatus.closed,
      );
    },
  );

  test(
    'permission preference queue freezes original scope; no head-of-line blocking for approvals',
    () async {
      final h = _Harness()..scope = _threadScope('thread', 1);
      final gate = Completer<AgentCommandOutcome>();
      h.executor.responses[#selectPermissionOption] = (_) => gate.future;
      final first = h.owner.selectPermissionOption(_option);
      final retry = h.owner.retryPermissionPreferencePersistence();
      expect(
        await h.owner.respondToQuestion(_question),
        isA<AgentCommandSucceeded>(),
      );
      expect(await h.owner.cancelActiveTurn(), isA<AgentCommandSucceeded>());
      h.scope = _threadScope('thread', 2);
      gate.complete(const AgentCommandOutcome.succeeded());
      expect(await first, _failed(AgentCommandFailureKind.staleTarget));
      expect(await retry, _failed(AgentCommandFailureKind.staleTarget));
      expect(
        h.executor.calls.where(
          (i) => i.memberName == #retryPermissionPreferencePersistence,
        ),
        isEmpty,
      );
    },
  );

  test(
    'four approval admission tables isolate equal request IDs and release after settlement',
    () async {
      final h = _Harness();
      final gate = Completer<AgentCommandOutcome>();
      for (final name in [
        #respondToPermission,
        #respondToQuestion,
        #respondToPlanApproval,
        #startPlanExecution,
      ]) {
        h.executor.responses[name] = (_) => gate.future;
      }
      final calls = <Future<AgentCommandOutcome> Function()>[
        () => h.owner.respondToPermission(_permission, approved: true),
        () => h.owner.respondToQuestion(_question),
        () => h.owner.respondToPlanApproval(
          _approval,
          AgentPlanApprovalDecisionKind.accepted,
        ),
        () => h.owner.startPlanExecution(_execution),
      ];
      final pending = [for (final call in calls) call()];
      expect(h.owner.current.pendingOperations, hasLength(4));
      for (final call in calls) {
        expect(await call(), _ignored(AgentCommandIgnoreReason.alreadyPending));
      }
      expect(h.executor.calls, hasLength(4));
      expect(h.executor.calls[1].namedArguments[#answers], isEmpty);
      gate.complete(const AgentCommandOutcome.succeeded());
      await Future.wait(pending);
      for (final call in calls) {
        expect(await call(), isA<AgentCommandSucceeded>());
      }
      expect(h.executor.calls, hasLength(8));
    },
  );

  test(
    'answers, amendment and nested request lists are frozen; null revision is a distinct command',
    () async {
      final h = _Harness();
      final answers = <String, List<String>>{
        'q': ['a'],
      };
      final choices = ['first'];
      final request = AgentQuestionRequest(
        id: 'q',
        title: 'q',
        questions: [
          AgentUserInputQaPair(
            questionId: 'q',
            question: 'q',
            options: choices,
          ),
        ],
      );
      await h.owner.respondToQuestion(request, answers: answers);
      answers['q']!.add('late');
      choices.clear();
      final call = h.executor.calls.last;
      expect(call.namedArguments[#answers], {
        'q': ['a'],
      });
      expect(
        (call.positionalArguments.single as AgentQuestionRequest)
            .questions
            .single
            .options,
        ['first'],
      );
      final amendment = ['one'];
      await h.owner.respondToPermission(
        _permission,
        approved: true,
        cancelTurn: true,
        commandDecision:
            AgentCommandApprovalDecisionKind.acceptWithExecpolicyAmendment,
        execpolicyAmendment: amendment,
      );
      amendment.clear();
      expect(h.executor.calls.last.namedArguments[#execpolicyAmendment], [
        'one',
      ]);
      expect(h.executor.calls.last.namedArguments[#cancelTurn], isTrue);
      await h.owner.revisePlanExecution(_execution);
      expect(h.executor.calls.last.memberName, #revisePlanExecution);
      expect(h.executor.calls.last.namedArguments[#revisionMessage], isNull);
      expect(
        h.executor.calls.where((i) => i.memberName == #startPlanExecution),
        isEmpty,
      );
    },
  );

  test('synchronous effects execute and settle on the current stack', () async {
    final h = _Harness();
    var observedPending = false;
    h.executor.responses[#toggleToolCall] = (_) {
      observedPending = h.owner.current.pendingOperations.length == 1;
      return const AgentCommandOutcome.succeeded();
    };
    final future = h.owner.toggleToolCall('tool');
    expect(observedPending, isTrue);
    expect(h.executor.calls.single.memberName, #toggleToolCall);
    expect(h.owner.current.pendingOperations, isEmpty);
    expect(await future, isA<AgentCommandSucceeded>());
  });

  test(
    'throwing runner and executor never strand a waiter or expose diagnostics',
    () async {
      final h = _Harness();
      h.executor.responses[#loadModels] = (_) =>
          throw UnsupportedError('private');
      expect(
        await h.owner.loadModels(),
        _failed(AgentCommandFailureKind.unsupported),
      );
      h.executor.responses[#loadModels] = (_) => throw StateError('private');
      expect(
        await h.owner.loadModels(),
        _failed(AgentCommandFailureKind.requestFailed),
      );
      final owner = conversationTestOwner(
        initialState: h.owner.current,
        effectRunner: _ThrowingRunner(),
        scopeSnapshot: () => h.scope,
      );
      expect(
        await owner.sendMessage('x'),
        _failed(AgentCommandFailureKind.requestFailed),
      );
      expect(owner.current.pendingOperations, isEmpty);
      expect(
        await h.owner.selectSessionConfigOption('config', []),
        _failed(AgentCommandFailureKind.requestFailed),
      );
    },
  );

  test(
    'scope failures before and after execution settle without leaking a waiter',
    () async {
      for (final failAt in [2, 3]) {
        final h = _Harness();
        var reads = 0;
        final owner = connectedConversationTestOwner(
          regions: h,
          commands: h.executor,
          scopeSnapshot: () {
            if (++reads == failAt) throw StateError('private scope failure');
            return h.scope;
          },
        );
        reads = 0; // Dependency registration also reads the initial alias.
        final result = await owner.forkCurrentThread();
        expect(result.outcome, _failed(AgentCommandFailureKind.requestFailed));
        expect(result.createdSession, failAt == 3 ? same(_session) : isNull);
        expect(owner.current.pendingOperations, isEmpty);
        expect(h.executor.calls, hasLength(failAt == 2 ? 0 : 1));
      }
    },
  );

  test(
    'fork preserves created product on activation failure or epoch change; no empty success',
    () async {
      final h = _Harness()..scope = _threadScope('source', 1);
      h.executor.responses[#forkCurrentThread] = (_) async =>
          AgentForkCommandOutcome.failed(
            AgentCommandFailureKind.requestFailed,
            createdSession: _session,
          );
      final failed = await h.owner.forkCurrentThread();
      expect(failed.createdSession, same(_session));
      expect(failed.activated, isFalse);
      final gate = Completer<AgentForkCommandOutcome>();
      h.executor.responses[#forkCurrentThread] = (_) => gate.future;
      final pending = h.owner.forkCurrentThread();
      h.scope = _threadScope('source', 2);
      gate.complete(AgentForkCommandOutcome.completed(_session));
      final stale = await pending;
      expect(stale.outcome, _failed(AgentCommandFailureKind.staleTarget));
      expect(stale.createdSession, same(_session));
      expect(stale.activated, isFalse);
      expect(
        AgentForkCommandOutcome.fromRegularFailure(
          const AgentCommandOutcome.succeeded(),
        ).outcome,
        _failed(AgentCommandFailureKind.requestFailed),
      );
    },
  );

  test(
    'complete Actions surface maps to distinct executor methods and fixed scopes',
    () async {
      final h = _Harness();
      final calls = <Future<AgentCommandOutcome> Function()>[
        () => h.owner.editLastUserMessageAndRetry('edit'),
        h.owner.retryOpenThread,
        h.owner.approveGuardianDeniedAction,
        () => h.owner.renameCurrentThread('name'),
        h.owner.archiveCurrentThread,
        h.owner.compactCurrentThread,
        () => h.owner.togglePlanMessage('message'),
        () => h.owner.toggleActivePlan('turn'),
        () => h.owner.toggleCommandGroup('group'),
        () => h.owner.toggleFileEditItem('file'),
        () => h.owner.loadModels(forceRefresh: true),
        h.owner.ensureSkillsCatalog,
        h.owner.retryConversationModes,
        () => h.owner.selectConversationMode(AgentConversationModeId.plan),
        () => h.owner.selectModel('model'),
        () => h.owner.selectReasoningEffort(null),
        () => h.owner.selectFastEnabled(true),
        h.owner.resolveModelCompatibilityConflict,
        h.owner.retryModelConfigurationSave,
        h.owner.clearModelConfigurationTransientState,
        () => h.owner.selectSessionConfigOption('config', true),
        () => h.owner.switchActiveProvider('other'),
        () => h.owner.selectPlanExecutionPermissionOption(_execution, _option),
        () => h.owner.dismissPlanExecution(_execution),
      ];
      for (final call in calls) {
        expect(await call(), isA<AgentCommandSucceeded>());
      }
      expect(
        h.executor.calls.map((i) => i.memberName).toSet(),
        hasLength(calls.length),
      );
      expect(h.owner.diagnostics.effectCount, calls.length);
      expect(h.owner.current.pendingOperations, isEmpty);
    },
  );
}

Matcher _failed(AgentCommandFailureKind kind) =>
    isA<AgentCommandFailed>().having((v) => v.kind, 'kind', kind);
Matcher _ignored(AgentCommandIgnoreReason reason) =>
    isA<AgentCommandIgnored>().having((v) => v.reason, 'reason', reason);
Future<void> _flush() => Future<void>.delayed(Duration.zero);
const _option = AgentPermissionOption(id: 'ask', label: 'Ask');
const _session = AgentSession(id: 'created', providerId: 'provider');
const _permission = AgentPermissionRequest(
  id: 'same',
  title: 'permission',
  kind: AgentPermissionKind.commandExecution,
);
const _question = AgentQuestionRequest(
  id: 'same',
  title: 'question',
  questions: [],
);
const _approval = AgentPlanApprovalRequest(
  id: 'same',
  title: 'plan',
  markdown: 'plan',
);
const _execution = AgentPlanExecutionRequest(
  id: 'same',
  sessionId: 'thread',
  turnId: 'turn',
  title: 'execution',
  markdown: 'plan',
);
AgentConversationCommandScope _threadScope(String id, int epoch) =>
    AgentConversationCommandScope(
      bindingKey: AgentConversationBindingKey.thread(
        providerId: 'provider',
        threadId: id,
      ),
      runtimeId: 'runtime',
      connectionEpoch: epoch,
      listenerGeneration: epoch,
      threadId: id,
    );

class _Harness implements AgentConversationRegionSource {
  _Harness({String draft = 'draft'}) {
    scope = AgentConversationCommandScope(
      bindingKey: AgentConversationBindingKey.draft(
        providerId: 'provider',
        entryId: draft,
      ),
    );
    owner = connectedConversationTestOwner(
      regions: this,
      commands: executor,
      scopeSnapshot: () => scope,
    );
  }
  final executor = _Executor();
  late final AgentConversationSliceNotifier owner;
  late AgentConversationCommandScope scope;
  @override
  get headerState => agentHeaderStateFixture();
  @override
  get composerState => agentComposerStateFixture();
  @override
  get pendingInteractionState => agentPendingInteractionStateFixture();
  @override
  get expansionState => agentExpansionStateFixture();
  @override
  get historyState => agentConversationHistoryStateFixture();
  @override
  AgentConversationCommandScope currentCommandScope() => scope;
  @override
  void addUiUpdateListener(void Function(AgentUiUpdateRequest) listener) {}
  @override
  void removeUiUpdateListener(void Function(AgentUiUpdateRequest) listener) {}
}

class _Executor implements AgentConversationCommandPort {
  final calls = <Invocation>[];
  final responses = <Symbol, dynamic Function(Invocation)>{};
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation);
    if (responses[invocation.memberName] case final respond?) {
      return respond(invocation);
    }
    if (const {
      #toggleToolCall,
      #togglePlanMessage,
      #toggleActivePlan,
      #toggleCommandGroup,
      #toggleFileEditItem,
      #dismissPlanExecution,
      #selectPlanExecutionPermissionOption,
      #selectConversationMode,
      #clearModelConfigurationTransientState,
    }.contains(invocation.memberName)) {
      return const AgentCommandOutcome.succeeded();
    }
    if (invocation.memberName == #forkCurrentThread) {
      return Future<AgentForkCommandOutcome>.value(
        AgentForkCommandOutcome.completed(_session),
      );
    }
    return Future<AgentCommandOutcome>.value(
      const AgentCommandOutcome.succeeded(),
    );
  }
}

class _ThrowingRunner implements AgentConversationSliceEffectRunner {
  @override
  void run(AgentConversationSliceEffect effect) =>
      throw StateError('runner failure');
  @override
  void close() {}
}

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';

void main() {
  group('AgentProviderBundle', () {
    test(
      'adapts conversation, thread, interaction, and optional ports',
      () async {
        final provider = _BundleFakeProvider(
          runtimeInfo: const AgentRuntimeInfo(
            runtimeId: 'runtime-1',
            connectionEpoch: 2,
            protocolName: 'codex',
            protocolVersion: '0.144.1',
            compatibilityStatus: AgentRuntimeCompatibilityStatus.supported,
          ),
          runtimeScope: const AgentRuntimeScope(
            runtimeId: 'runtime-1',
            connectionEpoch: 2,
          ),
          availableModels: const AgentModelList(
            models: <AgentModelInfo>[
              AgentModelInfo(
                id: 'model-1',
                model: 'model-1',
                displayName: 'Model 1',
              ),
            ],
          ),
        );

        final bundle = provider.bundle;
        final turnConfiguration = AgentTurnConfiguration(
          conversationMode: AgentConversationModeSelection(
            modeId: AgentConversationModeId.plan,
            effectiveModelId: 'model-1',
            effectiveReasoningEffort: 'high',
          ),
          permissionSnapshot: const AgentPermissionRequestSnapshot.resolved(
            selection: AgentPermissionSelection(optionId: 'turn-safe'),
            source: AgentPermissionRequestSource.threadEffective,
          ),
        );
        const startPermission = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: 'start-safe'),
          source: AgentPermissionRequestSource.catalogDefault,
        );
        const resumePermission = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: 'resume-safe'),
          source: AgentPermissionRequestSource.providerDefault,
        );
        const forkPermission = AgentPermissionRequestSnapshot.resolved(
          selection: AgentPermissionSelection(optionId: 'fork-safe'),
          source: AgentPermissionRequestSource.threadEffective,
        );

        expect(bundle.provider, same(provider));
        expect(bundle.runtime.config, same(provider.config));
        expect(bundle.runtime.capabilities, same(provider.capabilities));
        expect(bundle.runtime.runtimeInfo?.runtimeId, 'runtime-1');
        expect(
          bundle.runtime.lifecycleState,
          AgentProviderLifecycleState.ready,
        );
        expect(bundle.runtime.runtimeScope, provider.runtimeScope);
        expect(bundle.conversation, isNotNull);
        expect(bundle.threadCatalog, isNotNull);
        expect(bundle.threadMutations, isNotNull);
        expect(bundle.threadBranching, isNotNull);
        expect(bundle.turnSteering, isNotNull);
        expect(bundle.interactions, isNotNull);
        expect(bundle.modelCatalog, isNotNull);
        expect(bundle.conversationModes, isNotNull);
        expect(bundle.skills, isNotNull);
        expect(bundle.localThreadList, isNotNull);
        expect(bundle.sessionConfiguration, isNotNull);
        expect(bundle.planApproval, isNotNull);

        final started = await bundle.conversation.startSession(
          context: const AgentContext(projectPath: '/workspace'),
          permissionSnapshot: startPermission,
        );
        final resumed = await bundle.conversation.resumeSession(
          'thread-2',
          context: const AgentContext(projectPath: '/workspace'),
          permissionSnapshot: resumePermission,
        );
        final turn = await bundle.conversation.sendMessage(
          session: started,
          context: const AgentContext(projectPath: '/workspace'),
          inputs: const <AgentUserInput>[AgentUserInput.text('hello')],
          configuration: turnConfiguration,
        );
        await bundle.conversation.cancelTurn(turn);
        final page = await bundle.threadCatalog!.listThreads(
          query: const AgentThreadListQuery(
            projectPath: '/workspace',
            limit: 10,
          ),
        );
        final history = await bundle.threadCatalog!.readThreadHistory(
          threadId: 'thread-1',
          sessionPath: '/workspace/.session',
          projectPath: '/workspace',
        );
        await bundle.threadCatalog!.unsubscribeThread('thread-1');
        await bundle.threadMutations!.renameThread(
          threadId: 'thread-1',
          name: 'Renamed thread',
        );
        await bundle.threadMutations!.archiveThread('thread-1');
        await bundle.threadMutations!.unarchiveThread('thread-1');
        await bundle.threadMutations!.deleteThread('thread-1');
        await bundle.threadMutations!.compactThread('thread-1');
        final forked = await bundle.threadBranching!.forkThread(
          threadId: 'thread-1',
          context: const AgentContext(projectPath: '/workspace'),
          boundary: const AgentForkThroughTurn('turn-7'),
          permissionSnapshot: forkPermission,
        );
        await bundle.turnSteering!.steerTurn(
          session: started,
          expectedTurnId: 'turn-1',
          context: const AgentContext(projectPath: '/workspace'),
          inputs: const <AgentUserInput>[AgentUserInput.text('continue')],
        );
        await bundle.interactions!.respondToPermission(
          const AgentPermissionDecision(
            requestId: 'permission-1',
            approved: true,
          ),
        );
        await bundle.interactions!.respondToQuestion(
          const AgentQuestionResponse(
            requestId: 'question-1',
            answers: <String, List<String>>{
              'scope': <String>['source'],
            },
          ),
        );
        await bundle.interactions!.approveGuardianDeniedAction(
          threadId: 'thread-1',
          event: 'guardian-event',
        );
        final models = await bundle.modelCatalog!.listModels();
        final conversationModes = await bundle.conversationModes!
            .listConversationModes();
        final skills = await bundle.skills!.listSkills(
          cwds: const <String>['/workspace'],
        );
        await bundle.localThreadList!.removeThreadFromList('thread-1');
        await bundle.sessionConfiguration!.setSessionConfigOption(
          sessionId: 'thread-1',
          configId: 'mode',
          value: 'think',
        );
        await bundle.planApproval!.respondToPlanApproval(
          const AgentPlanApprovalDecision(
            requestId: 'plan-1',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        );

        expect(started.id, 'thread-1');
        expect(resumed.id, 'thread-2');
        expect(page.threads, isEmpty);
        expect(history.threadId, 'thread-1');
        expect(forked.id, 'fork-thread-1');
        expect(models.models, hasLength(1));
        expect(provider.startedContexts, hasLength(1));
        expect(provider.startedContexts.single.projectPath, '/workspace');
        expect(provider.startPermissionSnapshots.single, startPermission);
        expect(provider.resumedSessions, <String>['thread-2']);
        expect(provider.resumePermissionSnapshots.single, resumePermission);
        expect(provider.sentMessages, <String>['hello']);
        expect(provider.sentConfigurations.single, same(turnConfiguration));
        expect(provider.cancelledTurns, <String>['turn-1']);
        expect(provider.listQueries, hasLength(1));
        expect(provider.listQueries.single.projectPath, '/workspace');
        expect(provider.readThreads, <String>['thread-1']);
        expect(provider.unsubscribedThreads, <String>['thread-1']);
        expect(provider.renamedThreads, <({String threadId, String name})>[
          (threadId: 'thread-1', name: 'Renamed thread'),
        ]);
        expect(provider.archivedThreads, <String>['thread-1']);
        expect(provider.unarchivedThreads, <String>['thread-1']);
        expect(provider.deletedThreads, <String>['thread-1']);
        expect(provider.compactedThreads, <String>['thread-1']);
        expect(provider.forkedThreads, <String>['thread-1']);
        expect(provider.forkBoundaries, hasLength(1));
        expect(provider.forkBoundaries.single, isA<AgentForkThroughTurn>());
        expect(provider.forkPermissionSnapshots.single, forkPermission);
        expect(
          (provider.forkBoundaries.single as AgentForkThroughTurn).turnId,
          'turn-7',
        );
        expect(provider.steeredMessages, <String>['continue']);
        expect(provider.permissionDecisions, hasLength(1));
        expect(provider.permissionDecisions.single.requestId, 'permission-1');
        expect(provider.permissionDecisions.single.approved, isTrue);
        expect(provider.questionResponses, const <AgentQuestionResponse>[
          AgentQuestionResponse(
            requestId: 'question-1',
            answers: <String, List<String>>{
              'scope': <String>['source'],
            },
          ),
        ]);
        expect(provider.guardianApprovals, <String>['thread-1:guardian-event']);
        expect(provider.modelListCalls, 1);
        expect(conversationModes.presets, hasLength(2));
        expect(
          conversationModes.presets.map((preset) => preset.id),
          <AgentConversationModeId>[
            AgentConversationModeId.defaultMode,
            AgentConversationModeId.plan,
          ],
        );
        expect(provider.conversationModeListCalls, 1);
        expect(bundle.capabilities.supportsModeSelection, isFalse);
        expect(skills.allSkills, hasLength(1));
        expect(skills.allSkills.single.name, 'skill-creator');
        expect(provider.skillsListCalls, 1);
        expect(provider.removedThreads, <String>['thread-1']);
        expect(
          provider.sessionConfigWrites,
          <({String sessionId, String configId, Object value})>[
            (sessionId: 'thread-1', configId: 'mode', value: 'think'),
          ],
        );
        expect(provider.planDecisions, const <AgentPlanApprovalDecision>[
          AgentPlanApprovalDecision(
            requestId: 'plan-1',
            kind: AgentPlanApprovalDecisionKind.accepted,
          ),
        ]);
      },
    );

    test('omits unsupported capability domains from the bundle surface', () {
      final bundle = _MinimalBundleFakeProvider(
        capabilities: AgentProviderCapabilities.unsupported,
      ).bundle;

      expect(bundle.conversation, isNotNull);
      expect(bundle.threadCatalog, isNull);
      expect(bundle.threadMutations, isNull);
      expect(bundle.threadBranching, isNull);
      expect(bundle.turnSteering, isNull);
      expect(bundle.interactions, isNull);
      expect(bundle.modelCatalog, isNull);
      expect(bundle.conversationModes, isNull);
      expect(bundle.skills, isNull);
      expect(bundle.localThreadList, isNull);
      expect(bundle.sessionConfiguration, isNull);
      expect(bundle.planApproval, isNull);
      expect(bundle.permissionPolicy, isNull);
      expect(bundle.runtime.runtimeInfo, isNull);
      expect(
        bundle.runtime.lifecycleState,
        AgentProviderLifecycleState.stopped,
      );
      expect(bundle.runtime.runtimeScope, isNull);
    });

    test(
      'exposes permissionPolicy port when policy selection is supported',
      () async {
        final provider = _PermissionBundleFakeProvider(
          permissionOptions: const <AgentPermissionOption>[
            AgentPermissionOption(
              id: 'default-option',
              label: 'Default permission',
              description: 'Default permission',
              allowed: true,
            ),
            AgentPermissionOption(
              id: 'team-safe',
              label: 'Team safe',
              description: 'Team safe',
              allowed: true,
            ),
          ],
        );
        final bundle = provider.bundle;

        expect(bundle.permissionPolicy, isNotNull);
        final catalog = await bundle.permissionPolicy!.listPermissionOptions();
        expect(catalog.defaultOptionId, 'default-option');
        expect(catalog.options.map((o) => o.id).toList(), <String>[
          'default-option',
          'team-safe',
        ]);
        expect(catalog.options.first.label, 'Default permission');

        final result = await bundle.permissionPolicy!.applyPermissionSelection(
          const AgentPermissionSelection(optionId: 'team-safe'),
        );
        expect(result.normalizedSelection.optionId, 'team-safe');
        expect(result.scope, AgentPermissionApplyScope.runtime);
        expect(provider.lastAppliedPermissionOptionId, 'team-safe');
        expect(provider.permissionApplyCount, 1);
      },
    );

    test(
      'permissionPolicy is null when provider does not implement policy port',
      () {
        final bundle = _MinimalBundleFakeProvider().bundle;
        expect(bundle.permissionPolicy, isNull);
      },
    );

    test('keeps concurrent turn configurations isolated by call', () async {
      final provider = _MinimalBundleFakeProvider();
      final bundle = provider.bundle;
      final planConfiguration = AgentTurnConfiguration(
        conversationMode: AgentConversationModeSelection(
          modeId: AgentConversationModeId.plan,
          effectiveModelId: 'model-plan',
          effectiveReasoningEffort: 'high',
        ),
      );
      final defaultConfiguration = AgentTurnConfiguration(
        conversationMode: AgentConversationModeSelection(
          modeId: AgentConversationModeId.defaultMode,
          effectiveModelId: 'model-default',
        ),
      );

      await Future.wait(<Future<AgentTurn>>[
        bundle.conversation.sendMessage(
          session: const AgentSession(
            id: 'thread-plan',
            providerId: defaultAgentProviderId,
          ),
          context: const AgentContext(projectPath: '/workspace/plan'),
          message: 'plan',
          configuration: planConfiguration,
        ),
        bundle.conversation.sendMessage(
          session: const AgentSession(
            id: 'thread-default',
            providerId: defaultAgentProviderId,
          ),
          context: const AgentContext(projectPath: '/workspace/default'),
          message: 'answer',
          configuration: defaultConfiguration,
        ),
      ]);

      expect(provider.sentConfigurations[0], same(planConfiguration));
      expect(provider.sentConfigurations[1], same(defaultConfiguration));
    });

    test('maps active provider capability domains to ports', () {
      final codex = _MinimalBundleFakeProvider(
        capabilities: AgentProviderCapabilities.codexAppServer,
      ).bundle;
      final grok = _MinimalBundleFakeProvider(
        config: AgentProviderConfig.defaultGrok,
        capabilities: AgentProviderCapabilities.grokAcp,
      ).bundle;
      final cursor = _MinimalBundleFakeProvider(
        config: const AgentProviderConfig(
          id: cursorAgentProviderId,
          displayName: 'Cursor',
          kind: AgentProviderKind.cursorAcp,
          command: 'cursor-agent',
        ),
        capabilities: AgentProviderCapabilities.unsupported,
      ).bundle;
      expect(codex.threadCatalog, isNotNull);
      expect(codex.threadMutations, isNotNull);
      expect(codex.threadBranching, isNotNull);
      expect(codex.turnSteering, isNotNull);
      expect(codex.interactions, isNotNull);
      expect(codex.modelCatalog, isNotNull);
      expect(codex.conversationModes, isNull);
      // Minimal fake 未实现 AgentSkillsCatalogProvider，即使 capability 打开也无端口。
      expect(codex.skills, isNull);

      expect(grok.threadCatalog, isNotNull);
      expect(grok.threadMutations, isNotNull);
      expect(grok.threadBranching, isNull);
      expect(grok.turnSteering, isNull);
      expect(grok.interactions, isNotNull);
      expect(grok.modelCatalog, isNotNull);
      expect(grok.conversationModes, isNull);
      expect(grok.skills, isNull);

      expect(cursor.conversationModes, isNull);
      expect(cursor.skills, isNull);
    });
  });
}

class _MinimalBundleFakeProvider implements AgentProvider {
  _MinimalBundleFakeProvider({
    this.config = AgentProviderConfig.defaultCodex,
    this.capabilities = AgentProviderCapabilities.codexAppServer,
    this.availableModels = const AgentModelList(models: <AgentModelInfo>[]),
    this.permissionOptions = const <AgentPermissionOption>[],
  });

  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<AgentContext> startedContexts = <AgentContext>[];
  final List<AgentPermissionRequestSnapshot> startPermissionSnapshots =
      <AgentPermissionRequestSnapshot>[];
  final List<String> resumedSessions = <String>[];
  final List<AgentPermissionRequestSnapshot> resumePermissionSnapshots =
      <AgentPermissionRequestSnapshot>[];
  final List<String> sentMessages = <String>[];
  final List<AgentTurnConfiguration> sentConfigurations =
      <AgentTurnConfiguration>[];
  final List<String> steeredMessages = <String>[];
  final List<String> cancelledTurns = <String>[];
  final List<AgentThreadListQuery> listQueries = <AgentThreadListQuery>[];
  final List<String> readThreads = <String>[];
  final List<String> unsubscribedThreads = <String>[];
  final List<({String threadId, String name})> renamedThreads =
      <({String threadId, String name})>[];
  final List<String> archivedThreads = <String>[];
  final List<String> unarchivedThreads = <String>[];
  final List<String> deletedThreads = <String>[];
  final List<String> compactedThreads = <String>[];
  final List<String> forkedThreads = <String>[];
  final List<AgentForkBoundary> forkBoundaries = <AgentForkBoundary>[];
  final List<AgentPermissionRequestSnapshot> forkPermissionSnapshots =
      <AgentPermissionRequestSnapshot>[];
  final List<AgentPermissionDecision> permissionDecisions =
      <AgentPermissionDecision>[];
  final List<String> guardianApprovals = <String>[];
  int modelListCalls = 0;
  int permissionApplyCount = 0;
  String? lastAppliedPermissionOptionId;

  @override
  final AgentProviderConfig config;

  @override
  final AgentProviderCapabilities capabilities;

  final AgentModelList availableModels;
  final List<AgentPermissionOption> permissionOptions;

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
    AgentPermissionSelection? permissionSelection,
  }) async {
    startedContexts.add(context);
    startPermissionSnapshots.add(permissionSnapshot);
    return const AgentSession(
      id: 'thread-1',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
    AgentPermissionSelection? permissionSelection,
  }) async {
    resumedSessions.add(sessionId);
    resumePermissionSnapshots.add(permissionSnapshot);
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    listQueries.add(query);
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
  }) async {
    modelListCalls += 1;
    return availableModels;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  @override
  Future<void> approveGuardianDeniedAction({
    required String threadId,
    required Object event,
  }) async {
    guardianApprovals.add('$threadId:$event');
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    readThreads.add(threadId);
    return AgentThreadHistorySnapshot(
      threadId: threadId,
      turns: const <AgentHistoryTurn>[],
    );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {
    unsubscribedThreads.add(threadId);
  }

  @override
  Future<void> renameThread({
    required String threadId,
    required String name,
  }) async {
    renamedThreads.add((threadId: threadId, name: name));
  }

  @override
  Future<void> archiveThread(String threadId) async {
    archivedThreads.add(threadId);
  }

  @override
  Future<void> unarchiveThread(String threadId) async {
    unarchivedThreads.add(threadId);
  }

  @override
  Future<void> deleteThread(String threadId) async {
    deletedThreads.add(threadId);
  }

  @override
  Future<AgentSession> forkThread({
    required String threadId,
    required AgentContext context,
    AgentForkBoundary boundary = const AgentForkCurrentHead(),
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
    AgentPermissionSelection? permissionSelection,
  }) async {
    forkedThreads.add(threadId);
    forkBoundaries.add(boundary);
    forkPermissionSnapshots.add(permissionSnapshot);
    return AgentSession(
      id: 'fork-$threadId',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<void> compactThread(String threadId) async {
    compactedThreads.add(threadId);
  }

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    sentConfigurations.add(configuration);
    sentMessages.add(
      (inputs ?? <AgentUserInput>[AgentUserInput.text(message ?? '')])
          .whereType<AgentTextUserInput>()
          .map((item) => item.text)
          .join('\n'),
    );
    return AgentTurn(id: 'turn-1', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {
    steeredMessages.add(
      (inputs ?? <AgentUserInput>[AgentUserInput.text(message ?? '')])
          .whereType<AgentTextUserInput>()
          .map((item) => item.text)
          .join('\n'),
    );
  }

  @override
  Future<void> cancelTurn(AgentTurn turn) async {
    cancelledTurns.add(turn.id);
  }

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    permissionDecisions.add(decision);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

class _BundleFakeProvider extends _MinimalBundleFakeProvider
    implements
        AgentLocalThreadListProvider,
        AgentSessionConfigProvider,
        AgentPlanApprovalProvider,
        AgentConversationModeCatalogProvider,
        AgentSkillsCatalogProvider,
        AgentRuntimeInfoProvider,
        AgentRuntimeLifecycleProvider,
        AgentRuntimeScopeProvider,
        AgentQuestionResponseProvider {
  _BundleFakeProvider({
    this.runtimeInfo,
    this.runtimeScope,
    super.availableModels,
  });

  final List<String> removedThreads = <String>[];
  final List<({String sessionId, String configId, Object value})>
  sessionConfigWrites = <({String sessionId, String configId, Object value})>[];
  final List<AgentPlanApprovalDecision> planDecisions =
      <AgentPlanApprovalDecision>[];
  final List<AgentQuestionResponse> questionResponses =
      <AgentQuestionResponse>[];
  int conversationModeListCalls = 0;
  int skillsListCalls = 0;
  final StreamController<void> _skillsChanged =
      StreamController<void>.broadcast();

  @override
  final AgentRuntimeInfo? runtimeInfo;

  @override
  final AgentRuntimeScope? runtimeScope;

  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.ready;

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
    conversationModeListCalls += 1;
    return AgentConversationModeCatalog(
      presets: const <AgentConversationModePreset>[
        AgentConversationModePreset(
          id: AgentConversationModeId.defaultMode,
          displayName: 'Default',
        ),
        AgentConversationModePreset(
          id: AgentConversationModeId.plan,
          displayName: 'Plan',
          suggestedReasoningEffort: 'medium',
        ),
      ],
    );
  }

  @override
  Stream<void> get skillsChanged => _skillsChanged.stream;

  @override
  Future<AgentSkillsCatalog> listSkills({
    List<String> cwds = const <String>[],
    bool forceReload = false,
  }) async {
    skillsListCalls += 1;
    return AgentSkillsCatalog(
      entries: [
        AgentSkillsCatalogEntry(
          cwd: cwds.isEmpty ? '/workspace' : cwds.first,
          skills: const [
            AgentSkillMetadata(
              name: 'skill-creator',
              path: '/skills/skill-creator/SKILL.md',
              description: 'Create skills',
              enabled: true,
            ),
          ],
        ),
      ],
    );
  }

  @override
  Future<void> removeThreadFromList(String threadId) async {
    removedThreads.add(threadId);
  }

  @override
  List<AgentSessionConfigOption> sessionConfigOptions(String sessionId) {
    return const <AgentSessionConfigOption>[];
  }

  @override
  Future<void> setSessionConfigOption({
    required String sessionId,
    required String configId,
    required Object value,
  }) async {
    sessionConfigWrites.add((
      sessionId: sessionId,
      configId: configId,
      value: value,
    ));
  }

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    planDecisions.add(decision);
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) async {
    questionResponses.add(response);
  }

  @override
  Future<void> dispose() async {
    await _skillsChanged.close();
    await super.dispose();
  }
}

class _PermissionBundleFakeProvider extends _MinimalBundleFakeProvider
    implements AgentPermissionPolicyProvider {
  _PermissionBundleFakeProvider({
    super.permissionOptions = const <AgentPermissionOption>[],
  }) : super(capabilities: AgentProviderCapabilities.codexAppServer);

  @override
  AgentPermissionPolicyPort get permissionPolicy =>
      _BundleFakePermissionPort(this);
}

final class _BundleFakePermissionPort implements AgentPermissionPolicyPort {
  _BundleFakePermissionPort(this._host);
  final _MinimalBundleFakeProvider _host;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    final options = _host.permissionOptions;
    return AgentPermissionCatalog(
      options: options,
      defaultOptionId: options.isNotEmpty ? options.first.id : '',
    );
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    _host.lastAppliedPermissionOptionId = selection.optionId;
    _host.permissionApplyCount += 1;
    return AgentPermissionApplyResult(
      normalizedSelection: selection,
      scope: AgentPermissionApplyScope.runtime,
    );
  }
}

// Shared harness for AgentPane widget tests.
// 避免 AgentPane 集成测试重复搭建 FakeProvider / Theme / pump 工具。
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;
import 'package:zeta/src/features/agent/application/agent_conversation_mode_controller.dart';
import 'package:zeta/src/features/agent/application/agent_provider_runtime_registry.dart';
import 'package:zeta/src/features/agent/data/agent_provider_config_store.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/domain/agent_provider_bundle.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_pane.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/features/agent/application/agent_provider_settings_controller.dart';

import '../../../../testing/agent_provider_stub_base.dart';
import '../../../../testing/legacy_bundle_factory_mixin.dart';
import '../../../../testing/agent_conversation_binding_test_harness.dart';

class AgentPaneTestApp extends StatelessWidget {
  const AgentPaneTestApp({
    super.key,
    required this.viewModel,
    this.agentPaneKey,
    this.uiFontFamily,
    this.codeFontFamily = 'CodeFont',
    this.themeMode = ThemeMode.dark,
    this.disableAnimations = false,
    this.messageSendShortcut = MessageSendShortcut.enter,
    this.platform,
  });

  final AgentConversationViewModel viewModel;

  /// 挂到 [AgentPane] 上，供 `AgentPane.debugAddDraftImages` 等测试钩子使用。
  final GlobalKey? agentPaneKey;
  final String? uiFontFamily;
  final String codeFontFamily;
  final ThemeMode themeMode;
  final bool disableAnimations;
  final MessageSendShortcut messageSendShortcut;
  final TargetPlatform? platform;

  @override
  Widget build(BuildContext context) {
    final lightIdeTheme = buildIdeThemeData(
      brightness: Brightness.light,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    );
    final darkIdeTheme = buildIdeThemeData(
      brightness: Brightness.dark,
      uiFontFamily: uiFontFamily,
      codeFontFamily: codeFontFamily,
    );
    final activeIdeTheme = themeMode == ThemeMode.light
        ? lightIdeTheme
        : darkIdeTheme;
    return IdeThemeScope(
      themeMode: themeMode,
      lightTheme: lightIdeTheme,
      darkTheme: darkIdeTheme,
      child: sf.ShadcnApp(
        theme: buildShadcnTheme(lightIdeTheme),
        darkTheme: buildShadcnTheme(darkIdeTheme),
        materialTheme: buildMaterialTheme(
          activeIdeTheme,
        ).copyWith(platform: platform),
        themeMode: resolveShadcnThemeMode(themeMode),
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: sf.Scaffold(
              child: AgentPane(
                key: agentPaneKey,
                viewModel: viewModel,
                messageSendShortcut: messageSendShortcut,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Composer 权限下拉默认测试数据（模拟 port catalog）。
const List<AgentPermissionOption> agentPaneDefaultPermissionOptions =
    <AgentPermissionOption>[
      AgentPermissionOption(
        id: ':read-only',
        label: 'Read only',
        description: 'Read only',
        allowed: true,
      ),
      AgentPermissionOption(
        id: ':workspace',
        label: 'Workspace write',
        description: 'Workspace write',
        allowed: true,
      ),
      AgentPermissionOption(
        id: ':danger-full-access',
        label: 'Full access',
        allowed: true,
      ),
      AgentPermissionOption(
        id: ':team-safe',
        label: 'Team safe',
        description: 'Team safe',
        allowed: false,
      ),
    ];

const AgentModelList agentPaneModelConfigList = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'gpt-5.5',
      model: 'gpt-5.5',
      displayName: 'GPT-5.5',
      isDefault: true,
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'medium'),
        AgentModelReasoningEffort(effort: 'high'),
        AgentModelReasoningEffort(effort: 'xhigh'),
      ],
      defaultReasoningEffort: 'medium',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-5.4-mini',
      model: 'gpt-5.4-mini',
      displayName: 'GPT-5.4-Mini',
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'low'),
        AgentModelReasoningEffort(effort: 'high'),
        AgentModelReasoningEffort(effort: 'xhigh'),
      ],
      defaultReasoningEffort: 'low',
      serviceTiers: <AgentModelServiceTier>[
        AgentModelServiceTier(id: 'priority', name: 'Fast'),
      ],
    ),
    AgentModelInfo(
      id: 'gpt-legacy',
      model: 'gpt-legacy',
      displayName: 'GPT-Legacy',
      enabled: false,
      unavailableReason: '当前账号没有访问权限',
    ),
  ],
);

const AgentModelList agentPaneSingleReasoningModelList = AgentModelList(
  models: <AgentModelInfo>[
    AgentModelInfo(
      id: 'solo-reasoning',
      model: 'solo-reasoning',
      displayName: 'Solo Reasoning',
      isDefault: true,
      supportedReasoningEfforts: <AgentModelReasoningEffort>[
        AgentModelReasoningEffort(effort: 'balanced', description: '平衡'),
      ],
      defaultReasoningEffort: 'balanced',
    ),
  ],
);

AgentConversationViewModel createAgentPaneViewModel(
  AgentPaneFakeProvider provider, {
  AgentThreadSummary? initialThread,
  AgentConversationModeController? conversationModeController,
  List<WorkspaceNode> Function()? workspaceFilesProvider,
  Listenable? workspaceFilesListenable,
  bool Function()? workspaceFilesIndexReady,
}) {
  return createAgentPaneViewModelWithStore(
    provider,
    MemoryAgentProviderConfigStore(),
    initialThread: initialThread,
    conversationModeController: conversationModeController,
    workspaceFilesProvider: workspaceFilesProvider,
    workspaceFilesListenable: workspaceFilesListenable,
    workspaceFilesIndexReady: workspaceFilesIndexReady,
  );
}

AgentConversationViewModel createAgentPaneViewModelWithStore(
  AgentPaneFakeProvider provider,
  AgentProviderConfigStore configStore, {
  AgentThreadSummary? initialThread,
  AgentConversationModeController? conversationModeController,
  List<WorkspaceNode> Function()? workspaceFilesProvider,
  Listenable? workspaceFilesListenable,
  bool Function()? workspaceFilesIndexReady,
}) {
  final registry = AgentProviderRuntimeRegistry(
    providerFactory: AgentPaneFakeProviderFactory(provider),
  );
  addTearDown(registry.close);
  final controller = AgentProviderSettingsController(
    runtimeRegistry: registry,
    configStore: configStore,
  );
  addTearDown(controller.dispose);
  final bindingHarness = AgentConversationBindingTestHarness(
    registry: registry,
    settings: controller,
  );
  addTearDown(bindingHarness.close);
  final bindingLease = initialThread == null
      ? bindingHarness.acquireDraft(provider.config)
      : bindingHarness.acquireThread(
          config: provider.config,
          threadId: initialThread.id,
        );
  final viewModel = AgentConversationViewModel(
    providerController: controller,
    conversationBinding: bindingLease.binding,
    globalRuntime: bindingHarness.globalRuntime,
    conversationModeController: conversationModeController,
    workspaceFilesProvider: workspaceFilesProvider,
    workspaceFilesListenable: workspaceFilesListenable,
    workspaceFilesIndexReady: workspaceFilesIndexReady,
    initialProjectPath: initialThread?.projectPath ?? '/repo',
    initialThread: initialThread,
  );
  return viewModel;
}

class ToggleFailAgentProviderConfigStore implements AgentProviderConfigStore {
  ToggleFailAgentProviderConfigStore(this.settings);

  AgentProviderSettings settings;
  bool failSaves = true;

  @override
  Future<AgentProviderSettings> load() async => settings;

  @override
  Future<void> save(AgentProviderSettings next) async {
    if (failSaves) {
      throw const FileSystemException('simulated model config save failure');
    }
    settings = next;
  }
}

class RecordingAgentProviderConfigStore extends MemoryAgentProviderConfigStore {
  RecordingAgentProviderConfigStore();

  int saveCount = 0;

  @override
  Future<void> save(AgentProviderSettings settings) async {
    saveCount += 1;
    await super.save(settings);
  }
}

AgentThreadSummary agentPaneThread({
  required String id,
  required String title,
}) {
  return AgentThreadSummary(
    id: id,
    providerId: defaultAgentProviderId,
    projectPath: '/repo',
    title: title,
    sessionPath: '/repo/$id.jsonl',
    preview: title,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(2),
    status: AgentThreadRuntimeStatus.idle,
  );
}

String agentPaneFileEditGroupId(String turnId, String toolCallId) {
  return 'file-edit-group-$turnId-tool-$toolCallId';
}

String agentPaneFileEditItemId(String toolCallId, String changeId) {
  return 'file-edit-tool-$toolCallId-$changeId';
}

String agentPaneLargeUnifiedDiff() {
  return [
    '@@ -0,0 +1,32 @@',
    ...List<String>.generate(32, (index) => '+line ${index + 1}'),
  ].join('\n');
}

String? fontFamilyForRenderedText(
  WidgetTester tester,
  Finder finder,
  String textFragment,
) {
  final widget = tester.widget(finder);
  if (widget is Text) {
    return widget.style?.fontFamily;
  }
  if (widget is RichText) {
    return fontFamilyForInlineSpan(widget.text, textFragment);
  }
  return null;
}

String? fontFamilyForInlineSpan(
  InlineSpan span,
  String textFragment, [
  TextStyle? inheritedStyle,
]) {
  if (span is TextSpan) {
    final effectiveStyle = inheritedStyle?.merge(span.style) ?? span.style;
    if ((span.text ?? '').contains(textFragment)) {
      return effectiveStyle?.fontFamily;
    }
    for (final child in span.children ?? const <InlineSpan>[]) {
      final fontFamily = fontFamilyForInlineSpan(
        child,
        textFragment,
        effectiveStyle,
      );
      if (fontFamily != null) {
        return fontFamily;
      }
    }
  }
  if (span is WidgetSpan) {
    return inheritedStyle?.fontFamily;
  }
  return null;
}

MarkdownWidget markdownWidgetUnder(WidgetTester tester, Finder ancestor) {
  final finder = find.descendant(
    of: ancestor,
    matching: find.byType(MarkdownWidget),
  );
  expect(finder, findsOneWidget);
  return tester.widget<MarkdownWidget>(finder);
}

void expectMarkdownWidgetDefaults(MarkdownWidget widget) {
  expect(widget.useColumn, isTrue);
  expect(widget.selectable, isTrue);
  expect(widget.padding, EdgeInsets.zero);
  expect(widget.enableCopyFullDocumentShortcut, isFalse);
  expect(widget.showCopyAllInContextMenu, isFalse);
  // 对话 Markdown 通过空 contextMenuBuilder 完全抑制右键菜单。
  expect(widget.contextMenuBuilder, isNotNull);
}

class AgentPaneFakeProviderFactory with LegacyBundleFactoryMixin {
  AgentPaneFakeProviderFactory(this.provider);

  final AgentPaneFakeProvider provider;

  @override
  Object create(AgentProviderConfig config) => provider;
}

class AgentPaneFakeProvider
    with AgentProviderThreadLifecycleStub
    implements
        AgentRuntimePort,
        AgentConversationPort,
        AgentThreadCatalogPort,
        AgentThreadSubscriptionPort,
        AgentThreadNamingPort,
        AgentThreadArchivalPort,
        AgentThreadDeletionPort,
        AgentThreadCompactionPort,
        AgentThreadBranchingPort,
        AgentTurnSteeringPort,
        AgentPermissionResponsePort,
        AgentQuestionResponsePort,
        AgentModelCatalogPort,
        AgentSessionConfigurationPort,
        AgentPlanApprovalPort,
        TestPermissionPolicyHost {
  AgentPaneFakeProvider({
    Map<String, AgentThreadHistorySnapshot> historySnapshotsByThread =
        const <String, AgentThreadHistorySnapshot>{},
    this.models = const AgentModelList(models: <AgentModelInfo>[]),
    this.modelListError,
    this.canSteerTurn = true,
    this.canCompactThread = true,
    this.historyLoadGate,
    this.permissionOptions = agentPaneDefaultPermissionOptions,
  }) : _historySnapshotsByThread = Map<String, AgentThreadHistorySnapshot>.from(
         historySnapshotsByThread,
       ) {
    _permissionPolicy = _AgentPanePermissionPolicyPort(this);
  }

  final Map<String, AgentThreadHistorySnapshot> _historySnapshotsByThread;
  final AgentModelList models;
  final Object? modelListError;
  final bool canSteerTurn;
  final bool canCompactThread;

  /// 权限 port catalog 测试数据。
  final List<AgentPermissionOption> permissionOptions;
  late final AgentPermissionPolicyPort _permissionPolicy;

  /// 非空时 [readThreadHistory] 会先 await 该 Future，便于测试加载态 UI。
  final Future<void>? historyLoadGate;
  final StreamController<AgentEvent> _events =
      StreamController<AgentEvent>.broadcast();
  final List<AgentPermissionDecision> permissionDecisions =
      <AgentPermissionDecision>[];
  final List<AgentQuestionResponse> questionResponses =
      <AgentQuestionResponse>[];
  final List<(String, String, Object)> sessionConfigSelections =
      <(String, String, Object)>[];
  final List<AgentPlanApprovalDecision> planDecisions =
      <AgentPlanApprovalDecision>[];
  final List<String> sentMessages = <String>[];
  final List<AgentTurnConfiguration> turnConfigurations =
      <AgentTurnConfiguration>[];

  /// 最近一次经 port 应用的权限 optionId。
  String? lastAppliedPermissionOptionId;

  /// 权限 port apply 次数。
  int permissionApplyCount = 0;

  /// 权限目录读取次数。
  int permissionCatalogListCount = 0;

  /// 每次 sendMessage 递增，避免复用 turn id 导致 history/live 双挂。
  int _nextTurnSequence = 0;

  void emitEvent(AgentEvent event) {
    _events.add(event);
  }

  @override
  AgentProviderConfig get config =>
      AgentProviderConfig.defaultCodex.withPermissionPreference(':workspace');

  @override
  AgentProviderCapabilities get capabilities =>
      AgentProviderCapabilities.codexAppServer.copyWith(
        canForkThreadAtTurn: true,
        canSteerTurn: canSteerTurn,
        canCompactThread: canCompactThread,
      );

  @override
  Stream<AgentEvent> get events => _events.stream;

  @override
  AgentRuntimeInfo? get runtimeInfo => null;

  @override
  AgentProviderLifecycleState get lifecycleState =>
      AgentProviderLifecycleState.stopped;

  @override
  AgentRuntimeScope? get runtimeScope => null;

  @override
  Future<void> initialize() async {}

  @override
  Future<AgentSession> startSession({
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return const AgentSession(
      id: 'session-1',
      providerId: defaultAgentProviderId,
    );
  }

  @override
  Future<AgentSession> resumeSession(
    String sessionId, {
    required AgentContext context,
    AgentPermissionRequestSnapshot permissionSnapshot =
        const AgentPermissionRequestSnapshot.providerFallback(),
  }) async {
    return AgentSession(id: sessionId, providerId: defaultAgentProviderId);
  }

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    return const AgentThreadPage(
      threads: <AgentThreadSummary>[],
      nextCursor: null,
    );
  }

  @override
  Future<AgentModelList> listModels({
    int limit = 20,
    bool includeHidden = false,
    bool forceRefresh = false,
  }) async {
    final error = modelListError;
    if (error != null) {
      throw error;
    }
    return models;
  }

  @override
  void updateModelSelection(AgentModelSelection selection) {}

  /// 最近一次权限选择（Codex/Grok Composer 同步断言用）。

  @override
  AgentPermissionPolicyPort get permissionPolicy => _permissionPolicy;

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) async {
    final gate = historyLoadGate;
    if (gate != null) {
      await gate;
    }
    return _historySnapshotsByThread[threadId] ??
        AgentThreadHistorySnapshot(
          threadId: threadId,
          turns: const <AgentHistoryTurn>[],
        );
  }

  @override
  Future<void> unsubscribeThread(String threadId) async {}

  @override
  Future<AgentTurn> sendMessage({
    required AgentSession session,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
    AgentTurnConfiguration configuration = const AgentTurnConfiguration(),
  }) async {
    turnConfigurations.add(configuration);
    final sentText =
        message ??
        inputs
            ?.whereType<AgentTextUserInput>()
            .map((input) => input.text)
            .join();
    if (sentText != null) {
      sentMessages.add(sentText);
    }
    _nextTurnSequence += 1;
    return AgentTurn(id: 'turn-$_nextTurnSequence', sessionId: session.id);
  }

  @override
  Future<void> steerTurn({
    required AgentSession session,
    required String expectedTurnId,
    required AgentContext context,
    String? message,
    List<AgentUserInput>? inputs,
    String? clientUserMessageId,
  }) async {}

  @override
  Future<void> cancelTurn(AgentTurn turn) async {}

  @override
  Future<void> respondToPermission(AgentPermissionDecision decision) async {
    permissionDecisions.add(decision);
  }

  @override
  Future<void> respondToQuestion(AgentQuestionResponse response) async {
    questionResponses.add(response);
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
    sessionConfigSelections.add((sessionId, configId, value));
  }

  @override
  Future<void> respondToPlanApproval(AgentPlanApprovalDecision decision) async {
    planDecisions.add(decision);
  }

  @override
  Future<void> dispose() async {
    await _events.close();
  }
}

final class _AgentPanePermissionPolicyPort
    implements AgentPermissionPolicyPort {
  _AgentPanePermissionPolicyPort(this._host);

  final AgentPaneFakeProvider _host;

  @override
  Future<AgentPermissionCatalog> listPermissionOptions() async {
    _host.permissionCatalogListCount += 1;
    final options = _host.permissionOptions;
    final defaultId = options.any((option) => option.id == ':workspace')
        ? ':workspace'
        : (options.isNotEmpty ? options.first.id : '');
    return AgentPermissionCatalog(options: options, defaultOptionId: defaultId);
  }

  @override
  Future<AgentPermissionApplyResult> applyPermissionSelection(
    AgentPermissionSelection selection,
  ) async {
    final optionId = selection.optionId.trim();
    _host.lastAppliedPermissionOptionId = optionId;
    _host.permissionApplyCount += 1;
    return AgentPermissionApplyResult(
      normalizedSelection: AgentPermissionSelection(optionId: optionId),
      scope: AgentPermissionApplyScope.currentSession,
    );
  }
}

class AgentPaneModeFakeProvider extends AgentPaneFakeProvider
    implements AgentConversationModeCatalogPort {
  AgentPaneModeFakeProvider({
    super.models = const AgentModelList(models: <AgentModelInfo>[]),
    super.permissionOptions,
  });

  @override
  AgentProviderCapabilities get capabilities =>
      super.capabilities.copyWith(supportsModeSelection: true);

  @override
  Future<AgentConversationModeCatalog> listConversationModes() async {
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
}

/// AgentPane 含有输入光标、浮层和 footer 测量等持续 frame 源，`pumpAndSettle()`
/// 容易永久等待；测试统一用有限帧推进到稳定视觉状态。
Future<void> pumpAgentPaneUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(IdeMotion.durationSlow);
  await tester.pump();
}

/// 运行中 turn 的 spinner 不会 settle，只推进流式内容渲染所需的有限帧。
Future<void> pumpLiveAgentUi(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

/// 条件等待默认约 2s，避免 CI 抖动导致 finder 过早超时。
const Duration agentPaneWaitStep = Duration(milliseconds: 20);
const int agentPaneWaitMaxAttempts = 100;

Future<void> pumpUntilCondition(
  WidgetTester tester,
  bool Function() condition, {
  Duration step = agentPaneWaitStep,
  int maxAttempts = agentPaneWaitMaxAttempts,
  String failureMessage = 'Condition did not become ready',
}) async {
  // 先 pump 再检查：保证 emitEvent / 异步 Future 至少推进一帧，
  // 避免「目标已存在」时零 pump 导致后续事件从未被消化。
  for (var attempt = 0; attempt < maxAttempts; attempt += 1) {
    await tester.pump(step);
    if (condition()) {
      return;
    }
  }
  throw TestFailure(failureMessage);
}

Future<void> pumpUntilFinder(
  WidgetTester tester,
  Finder finder, {
  Duration step = agentPaneWaitStep,
  int maxAttempts = agentPaneWaitMaxAttempts,
}) async {
  await pumpUntilCondition(
    tester,
    () => finder.evaluate().isNotEmpty,
    step: step,
    maxAttempts: maxAttempts,
    failureMessage: 'Widget did not become ready: $finder',
  );
}

Future<void> pumpUntilFinderAbsent(
  WidgetTester tester,
  Finder finder, {
  Duration step = agentPaneWaitStep,
  int maxAttempts = agentPaneWaitMaxAttempts,
}) async {
  await pumpUntilCondition(
    tester,
    () => finder.evaluate().isEmpty,
    step: step,
    maxAttempts: maxAttempts,
    failureMessage: 'Widget did not close: $finder',
  );
}

Future<void> pumpUntilMessageSent(
  WidgetTester tester,
  AgentPaneFakeProvider provider, {
  Duration step = const Duration(milliseconds: 10),
  int maxAttempts = agentPaneWaitMaxAttempts,
}) async {
  await pumpUntilCondition(
    tester,
    () => provider.sentMessages.isNotEmpty,
    step: step,
    maxAttempts: maxAttempts,
    failureMessage:
        'Message was not sent within timeout; sentMessages=${provider.sentMessages}',
  );
}

/// 打开会动画出现的浮层：tap 后按 finder 条件等待，避免固定 300ms 竞态。
Future<void> tapAndWaitForFinder(
  WidgetTester tester,
  Finder tapTarget,
  Finder expected, {
  Duration step = agentPaneWaitStep,
  int maxAttempts = agentPaneWaitMaxAttempts,
}) async {
  await tester.tap(tapTarget);
  await pumpUntilFinder(tester, expected, step: step, maxAttempts: maxAttempts);
}

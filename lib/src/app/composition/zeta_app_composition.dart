import 'workbench_session_providers.dart';
import 'package:zeta/src/app/agent_management_slice/workspace_agent_runtime_fact_source.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_slice_notifier.dart';
import 'package:zeta/src/app/composition/agent_session_resource_providers.dart';
import 'package:zeta/src/app/project_threads_slice/project_threads_slice_composition.dart';
import 'package:zeta/src/features/project_threads/application/project_threads_slice/project_threads_slice_notifier.dart';
import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/app/agent_management_slice/agent_management_slice_composition.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_notifier.dart';
import 'dart:async';

import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:zeta_ui/zeta_ui.dart';

import 'package:zeta/src/app/composition/agent_resource_shutdown.dart';
import 'package:zeta/src/app/composition/zeta_state_snapshot.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_slice_overrides.dart';
import 'package:zeta/src/app/ide_session_slice/ide_session_slice_overrides.dart';
import 'package:zeta/src/app/localization/zeta_display_language_source.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalog_providers.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/app/observability/zeta_observability.dart';
import 'package:zeta/src/app/plugins/zeta_plugin_providers.dart';
import 'package:zeta/src/app/provider_settings_slice/provider_settings_slice_overrides.dart';
import 'package:zeta/src/app/settings_slice/settings_slice_overrides.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_slice_overrides.dart';
import 'package:zeta/src/app/window/zeta_shutdown_hook.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/app/workspace_slice/workspace_overrides.dart';
import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_store.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_notifier.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_notifier.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_store.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_store.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// Zeta 的组合根。
///
/// 这是 Riverpod 的标准形状：**容器由组合根创建，Widget 只消费**。生产入口和测试
/// 各自建一份 [ZetaAppComposition]，注入口径只有一个——[create] 的 `overrides`。
///
/// 组合根不再接收依赖参数。以前那 15 个可选参数现在各自是一个 provider，有安全
/// 默认值的把兜底写在 provider 的 body 里（生产实现）；调用方要换实现就覆盖那个
/// provider。这条规矩有个硬约束撑着：Riverpod 对同一容器内的重复 override 直接
/// 断言失败，所以**组合根内部装过的 provider，调用方就再也覆盖不掉**——凡是调用
/// 方可能想换的东西，这里一律不装。
///
/// 内部仍然装的只有三类，都是调用方不该碰的：
///
/// 1. 正式容器复用的已解析可观测性实例；
/// 2. 显示语言冻结之后才存在的文本目录（值还没有，写不进 provider body）；
/// 3. 切片的冻结依赖与 Runner factory，状态由 application Notifier 持有。
///
/// 生命周期：**谁创建谁 [dispose]**。生产入口交给进程退出与窗口关闭 hook，测试用
/// `addTearDown`。
final class ZetaAppComposition implements ZetaShutdownHook {
  ZetaAppComposition._({required List<Override> extra}) {
    observability = _readObservability(extra);
    container = ProviderContainer(
      observers: observability.providerObservers,
      overrides: _composeOverrides(extra),
    );
    // 语言冻结前先用兜底语言，避免第一帧的 loading 底色带一个无关的 locale。
    _frozenDisplayLocale = ZetaLocalization.localeFor(
      container.read(settingsFallbackLanguageProvider),
    );
    _windowHost = container.read(zetaWindowHostProvider);
    _windowHost.addShutdownHook(this);
    try {
      _start();
    } catch (_) {
      dispose();
      rethrow;
    }
  }

  /// 建出组合根并立即开始装配。
  ///
  /// [overrides] 是唯一的注入口。**存储不在这里装**：`ZetaStorageBindings` 生成
  /// 的那批 override 由调用方自己展开（生产用 `.file(paths)`，测试用
  /// `.memory()`），组合根装了的话调用方就再也换不掉。
  ///
  /// ```dart
  /// ZetaAppComposition.create(
  ///   overrides: <Override>[
  ///     ...ZetaStorageBindings.file(paths).providerOverrides,
  ///     initialAppearanceSettingsProvider.overrideWithValue(appearance),
  ///   ],
  /// );
  /// ```
  factory ZetaAppComposition.create({
    List<Override> overrides = const <Override>[],
  }) {
    return ZetaAppComposition._(extra: overrides);
  }

  /// 组合根持有的 Riverpod 容器。
  late final ProviderContainer container;

  /// 正式容器与 Provider observer 共用的可观测性实例。
  late final ZetaObservability observability;

  late final ZetaWindowHost _windowHost;

  ZetaTextCatalogs? _textCatalogs;
  var _generalSettingsReady = false;
  var _localeRuntimeReady = false;
  var _disposed = false;
  late Locale _frozenDisplayLocale;
  final Completer<void> _ready = Completer<void>();

  /// 有文字的 UI 是否可以挂载（显示语言已冻结，或本次不需要等待）。
  bool get isReady => _generalSettingsReady;

  /// [isReady] 变 true 时完成。
  Future<void> get ready => _ready.future;

  Locale get frozenDisplayLocale => _frozenDisplayLocale;

  /// 设计系统自有文案。
  ///
  /// 不走 provider：`ShadcnApp` 在显示语言冻结之前就要读一次（等常规设置的那一
  /// 帧也在它里面），provider 会把那次读到的值缓存住。未冻结时回退英文，与冻结
  /// 之前的 UI 只有 loading 底色这一个事实相符。
  ZetaUiTextCatalog get zetaUiTextCatalog =>
      _textCatalogs?.zetaUi ?? const FallbackZetaUiTextCatalog();

  /// 按需读取当前逻辑状态树；生产 Widget 不得订阅或在 build 中调用。
  ZetaStateSnapshot takeStateSnapshot() {
    return ZetaStateSnapshot(
      shell: _takeShellStateSnapshot(),
      ideSession: container.read(ideSessionSliceProvider),
      usageStatistics: container.read(usageStatisticsSliceProvider),
      agentUsagePanel: container.read(agentUsagePanelSliceProvider),
      desktopAttention: ZetaDesktopAttentionStateSnapshot.fromState(
        container.read(desktopAttentionSliceProvider),
      ),
      appearanceSettings: container.read(appearanceSettingsProvider),
      generalSettings: container.read(generalSettingsSliceProvider),
      providerSettings: container.read(agentProviderSettingsSliceProvider),
    );
  }

  /// 诊断与恢复测试使用的无正文 Shell 投影。
  ///
  /// 这里刻意同步读取各唯一 owner，既不缓存也不注册 listener；生产 Widget 仍只
  /// watch 各自的 feature selector。
  ZetaShellStateSnapshot _takeShellStateSnapshot() {
    final shell = container.read(workbenchSessionProvider).shell;
    final threadStates = container.read(projectThreadsSliceProvider);
    final projectThreads = <String, ZetaProjectThreadsStateSnapshot>{
      for (final entry in threadStates.statesByProject.entries)
        entry.key: ZetaProjectThreadsStateSnapshot.fromState(
          entry.key,
          entry.value,
        ),
    };
    final entries = shell.agentWorkspaceEntries;
    final selectedEntryId = shell.selectedAgentWorkspaceEntryId;
    final conversations = <String, ZetaConversationStateSnapshot>{};
    for (final entry in entries) {
      final slice = container.read(
        agentConversationSliceOwnerProvider(entry.ownerKey),
      );
      final pendingInteractions = slice.pendingInteractions;
      conversations[entry.entryId] = ZetaConversationStateSnapshot(
        entryId: entry.entryId,
        projectPath: entry.projectPath,
        providerId: entry.providerId,
        threadId: entry.threadId,
        isDraft: entry.isDraft,
        isSelected: entry.entryId == selectedEntryId,
        sliceAvailable: true,
        threadOpenPhase: slice.header.threadOpenPhase,
        runtimeStatus: entry.threadSnapshot.runtimeStatus,
        isTurnRunning: slice.header.isTurnRunning,
        isReadOnly: slice.header.isReadOnly,
        visibleTurnCount: slice.history.visibleTurns.length,
        pendingInteractionCount:
            pendingInteractions.permissions.length +
            pendingInteractions.questions.length +
            pendingInteractions.planApprovals.length +
            (pendingInteractions.planExecutionHandoff == null ? 0 : 1),
        pendingOperationCount: slice.pendingOperations.length,
      );
    }
    return ZetaShellStateSnapshot(
      workspace: shell.workspaceState,
      projectThreadsByProjectPath: projectThreads,
      orderedConversationEntryIds: <String>[
        for (final entry in entries) entry.entryId,
      ],
      conversationsByEntryId: conversations,
      selectedConversationEntryId: selectedEntryId,
      projectHomeActive: shell.isProjectHomeActive,
      agentManagement: ZetaAgentManagementStateSnapshot.fromState(
        container.read(agentManagementSliceProvider),
      ),
    );
  }

  /// 按依赖反序关闭本实例拥有的 Agent 资源。
  ///
  /// 顺序是硬要求：**runtime registry 先、plugin catalog 后**。插件贡献出的工厂是
  /// runtime 的上游依赖，先关插件会让仍在退出中的 runtime 失去依赖；窗口关闭
  /// （[run]）与 [dispose] 共用这一个入口，避免两条路径顺序不一致。
  ///
  /// 只关**已经建出来的**：覆盖了 bundle 工厂的用例根本不会建插件目录，
  /// [ProviderContainer.exists] 就是这个"建没建过"的判据。两个 `close()` 本身可
  /// 重复调用，因此本方法幂等。
  WorkbenchSession? _workbench;
  WorkspaceAgentRuntimeFactSource? _runtimeFacts;
  AgentManagementInputSubscription? _managementRuntimeIngress;
  ProviderSubscription<AgentManagementInputSubscription>?
  _managementRuntimeSubscription;
  AgentManagementSliceNotifier? _managementOwner;
  ProjectThreadsSliceNotifier? _projectThreadsOwner;
  AgentManagementInputSubscription? _managementSettingsIngress;
  Future<void>? _shutdownFuture;
  Future<void>? _closeFuture;

  Future<void> shutdownOwnedAgentResources() {
    final existing = _shutdownFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _shutdownFuture = completion.future;
    unawaited(
      _shutdownOwnedAgentResources().then(
        completion.complete,
        onError: completion.completeError,
      ),
    );
    return completion.future;
  }

  Future<void> _shutdownOwnedAgentResources() async {
    // Native shutdown may run before asynchronous locale resolution finishes.
    _disposed = true;
    final closeManager = _closerFor(
      agentConversationBindingManagerProvider,
      (manager) => manager.close,
    );
    final closeRegistry = _closerFor(
      agentProviderRuntimeRegistryProvider,
      (registry) => registry.close,
    );
    final closePlugins = _closerFor(
      zetaPluginCatalogProvider,
      (catalog) => catalog.close,
    );
    final management = _managementOwner;
    final workbench = _workbench;
    workbench?.shell.stopAcceptingCommands();
    // Logical callers finish immediately; physical I/O still owns borrowed resources.
    management?.stopAcceptingCommandsAndSettleWaiters();
    _projectThreadsOwner?.stopAcceptingCommandsAndSettleWaiters();
    if (workbench != null) await workbench.shell.saveNow();
    await Future.wait<void>([
      if (management != null) management.drainExecutions(),
      if (_projectThreadsOwner case final threads?) threads.drainExecutions(),
    ], eagerError: false);
    _managementSettingsIngress?.close();
    _managementRuntimeIngress?.close();
    _managementRuntimeSubscription?.close();
    _runtimeFacts?.close();
    if (workbench != null) {
      await workbench.lifetimes.closeAllEntries();
      await workbench.events.close();
    }
    await closeManager?.call();
    await shutdownAgentResourcesInOrder(
      closeRuntimeRegistry: closeRegistry,
      closePluginCatalog: closePlugins,
    );
  }

  @override
  Future<void> run() => shutdownOwnedAgentResources();

  Future<void> close() {
    final existing = _closeFuture;
    if (existing != null) return existing;
    final completion = Completer<void>();
    _closeFuture = completion.future;
    unawaited(
      _close().then(completion.complete, onError: completion.completeError),
    );
    return completion.future;
  }

  Future<void> _close() async {
    _disposed = true;
    _windowHost.removeShutdownHook(this);
    await shutdownOwnedAgentResources();
    container.dispose();
  }

  /// Synchronous Flutter disposal starts the same close; completion requires await close().
  void dispose() {
    unawaited(close());
  }

  void _start() {
    final displayLanguage = container.read(zetaDisplayLanguageSourceProvider);
    // 无论显示语言等不等它，常规设置都要在启动时就开始读。
    final loadGeneralSettings = container
        .read(generalSettingsSliceProvider.notifier)
        .initialLoad;
    final eagerLanguage = displayLanguage.eagerLanguage;
    if (eagerLanguage != null) {
      installLocaleDependentRuntime(eagerLanguage);
      _markReady();
      unawaited(loadGeneralSettings);
      return;
    }
    unawaited(
      displayLanguage.resolve().then((language) {
        if (_disposed || _generalSettingsReady) {
          return;
        }
        installLocaleDependentRuntime(language);
        _markReady();
      }),
    );
  }

  void _markReady() {
    if (_generalSettingsReady) {
      return;
    }
    _generalSettingsReady = true;
    if (!_ready.isCompleted) {
      _ready.complete();
    }
  }

  /// 冻结显示语言并装配依赖它的运行时。
  ///
  /// 文本目录一装进容器，插件目录、Provider 配置 codec、桌面通知服务这条链就都能
  /// 解析了——它们全部经 provider 依赖到 [zetaTextCatalogsProvider]，在此之前读会
  /// fail-closed 抛错，而不是拿一份 fallback 文案把对象建出来。
  ///
  /// 幂等：只有第一次调用真正装配。
  void installLocaleDependentRuntime(AppLanguage language) {
    if (_disposed) return;
    if (!_localeRuntimeReady) {
      _frozenDisplayLocale = ZetaLocalization.localeFor(language);
      _textCatalogs = ZetaTextCatalogs(
        lookupAppLocalizations(_frozenDisplayLocale),
      );
    }
    // Provider Settings 是 app-session Notifier；在文本目录就绪后显式建出，
    // 保持旧组合在使用统计和 Shell 之前已安装的启动顺序。
    final providerSettings = container.read(
      agentProviderSettingsSliceProvider.notifier,
    );
    // 首次 intent 必须在 Widget 挂载前发出。IdeHome.initState 中同步修改
    // Notifier 会触发 Riverpod 的 build-phase 写保护；Shell 随后调用时只会复用
    // 同一个 in-flight Future，不再产生第二次 effect。
    unawaited(providerSettings.loadSettings());
    // Usage Statistics 同样是 app-session Notifier。此处只显式建出 owner，
    // 查询仍按页面/侧栏命令惰性启动。
    container.read(usageStatisticsSliceProvider.notifier);
    container.read(agentUsagePanelSliceProvider.notifier);
    container.read(projectThreadsSliceProvider);
    _projectThreadsOwner = container.read(projectThreadsSliceProvider.notifier);
    container.read(agentManagementSliceProvider);
    final management = container.read(agentManagementSliceProvider.notifier);
    _managementOwner = management;
    final ingress = container.read(agentManagementSettingsIngressProvider);
    _managementSettingsIngress = ingress;
    ingress.start();
    unawaited(
      management.initialize().onError((error, trace) {
        if (!management.isClosed) {
          try {
            zetaLoggerFor(
              'zeta.agent.management',
            ).e('Agent management initialization failed');
          } catch (_) {}
        }
      }),
    );
    if (!_localeRuntimeReady) {
      final workbench = container.read(workbenchSessionProvider);
      _workbench = workbench;
      final facts = container.read(workspaceAgentRuntimeFactSourceProvider);
      _runtimeFacts = facts;
      facts.start();
      final runtimeSubscription = container.listen(
        agentManagementRuntimeIngressProvider(facts),
        (_, _) {},
      );
      _managementRuntimeSubscription = runtimeSubscription;
      final runtimeIngress = runtimeSubscription.read();
      _managementRuntimeIngress = runtimeIngress;
      runtimeIngress.start();
      workbench.shell.start();
    }
    _localeRuntimeReady = true;
  }

  /// 取出某个资源的关闭动作；没建出来就返回 null。
  Future<void> Function()? _closerFor<T>(
    Provider<T> provider,
    Future<void> Function() Function(T value) close,
  ) => container.exists(provider) ? close(container.read(provider)) : null;

  /// 组合根内部装的 override。
  ///
  /// **只装调用方不该碰的那三类**（见类文档）。依赖延迟到 `overrideWith` 的闭包
  /// 里读，因此语言冻结后才建出来的切片 owner 不会引起重新装配；尚未组合就被读
  /// 到时会 fail-closed 抛错。[extra] 排在最后。
  List<Override> _composeOverrides(List<Override> extra) {
    return <Override>[
      zetaResolvedObservabilityProvider.overrideWithValue(observability),
      zetaTextCatalogsProvider.overrideWith(
        (ref) =>
            _textCatalogs ??
            (throw StateError(
              'Text catalogs were read before the composition root froze the '
              'display language',
            )),
      ),
      ...desktopAttentionSliceOverrides(),
      ...ideSessionSliceOverrides(),
      ...providerSettingsSliceOverrides(),
      ...agentManagementSliceOverrides(),
      ...projectThreadsSliceOverrides(),
      ...settingsSliceOverrides(),
      ...usageStatisticsSliceOverrides(),
      ...workspaceOverrides(),
      ...conversationWorkspaceOverrides(),
      ...extra,
    ];
  }

  /// 在真正的容器建出来之前读一次可观测性组合。
  ///
  /// `ProviderContainer` 的 observers 只能在构造时传入，而装哪个采集实现要由
  /// [overrides] 决定——先开一个临时容器把它读出来再扔掉。解析出的同一实例随后
  /// 通过 [zetaResolvedObservabilityProvider] 装进正式容器，保证观察器与业务指标
  /// 共用一份 collector；调用方使用 `overrideWith` 也只会执行一次工厂。
  static ZetaObservability _readObservability(List<Override> overrides) {
    final probe = ProviderContainer(overrides: overrides);
    try {
      return probe.read(zetaObservabilityProvider);
    } finally {
      probe.dispose();
    }
  }
}

import 'package:meta/meta.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/application/provider_settings_slice/agent_provider_settings_slice_state.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_state.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/ide_session/application/ide_session_slice/ide_session_slice_state.dart';
import 'package:zeta/src/features/project_threads/domain/project_thread_list_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/agent_usage_panel_slice/agent_usage_panel_slice_state.dart';
import 'package:zeta/src/features/usage_statistics/application/usage_statistics_slice/usage_statistics_slice_state.dart';
import 'package:zeta/src/features/workspace/application/workspace_slice/workspace_slice_state.dart';

/// Zeta 进程内逻辑状态树的按需只读快照。
///
/// 该对象只供诊断、恢复测试与开发工具读取：它没有 listener/provider，也不得序列化、
/// 写日志或被生产 Widget 订阅。各 feature state 均沿用唯一 owner 发布的不可变值，
/// Conversation 与 Agent Management 则使用白名单摘要，避免把时间线、配置或日志正文
/// 复制进根投影。
@immutable
final class ZetaStateSnapshot {
  const ZetaStateSnapshot({
    required this.shell,
    required this.ideSession,
    required this.usageStatistics,
    required this.agentUsagePanel,
    required this.desktopAttention,
    required this.appearanceSettings,
    required this.generalSettings,
    required this.providerSettings,
  });

  final ZetaShellStateSnapshot shell;
  final IdeSessionSliceState ideSession;
  final UsageStatisticsSliceState usageStatistics;
  final AgentUsagePanelSliceState agentUsagePanel;
  final ZetaDesktopAttentionStateSnapshot desktopAttention;

  final AppearanceSettingsSliceState appearanceSettings;
  final GeneralSettingsSliceState generalSettings;
  final AgentProviderSettingsSliceState providerSettings;
}

/// Desktop Attention 的无路径、无正文根投影。
@immutable
final class ZetaDesktopAttentionStateSnapshot {
  const ZetaDesktopAttentionStateSnapshot({
    required this.initialized,
    required this.unreadCount,
    required this.windowFocused,
    required this.agentCanvasVisible,
    required this.visibleProviderId,
    required this.visibleThreadId,
  });

  factory ZetaDesktopAttentionStateSnapshot.fromState(
    DesktopAttentionSliceState state,
  ) {
    return ZetaDesktopAttentionStateSnapshot(
      initialized: state.initialized,
      unreadCount: state.unreadCount,
      windowFocused: state.visibility.windowFocused,
      agentCanvasVisible: state.visibility.agentCanvasVisible,
      visibleProviderId: state.visibility.providerId,
      visibleThreadId: state.visibility.threadId,
    );
  }

  final bool initialized;
  final int unreadCount;
  final bool windowFocused;
  final bool agentCanvasVisible;
  final String? visibleProviderId;
  final String? visibleThreadId;
}

/// Shell 组合边界可见的只读逻辑关系。
@immutable
final class ZetaShellStateSnapshot {
  ZetaShellStateSnapshot({
    required this.workspace,
    required Map<String, ZetaProjectThreadsStateSnapshot>
    projectThreadsByProjectPath,
    required List<String> orderedConversationEntryIds,
    required Map<String, ZetaConversationStateSnapshot> conversationsByEntryId,
    required this.selectedConversationEntryId,
    required this.projectHomeActive,
    required this.agentManagement,
  }) : projectThreadsByProjectPath = Map.unmodifiable(
         projectThreadsByProjectPath,
       ),
       orderedConversationEntryIds = List.unmodifiable(
         orderedConversationEntryIds,
       ),
       conversationsByEntryId = Map.unmodifiable(conversationsByEntryId);

  final WorkspaceSliceState workspace;
  final Map<String, ZetaProjectThreadsStateSnapshot>
  projectThreadsByProjectPath;
  final List<String> orderedConversationEntryIds;
  final Map<String, ZetaConversationStateSnapshot> conversationsByEntryId;
  final String? selectedConversationEntryId;
  final bool projectHomeActive;
  final ZetaAgentManagementStateSnapshot agentManagement;
}

/// Project Threads 的无正文根投影。
@immutable
final class ZetaProjectThreadsStateSnapshot {
  ZetaProjectThreadsStateSnapshot.fromState(
    this.projectPath,
    ProjectThreadListState state,
  ) : orderedThreadIds = List.unmodifiable(
        state.threads.map((thread) => thread.id),
      ),
      runningThreadIds = Set.unmodifiable(state.runningThreadIds),
      completedThreadIds = Set.unmodifiable(state.completedThreadIds),
      selectedThreadId = state.selectedThreadId,
      isExpanded = state.isExpanded,
      hasLoaded = state.hasLoaded,
      isLoadingInitial = state.isLoadingInitial,
      isLoadingMore = state.isLoadingMore,
      hasMore = state.hasMore,
      hasError = state.errorMessage != null,
      archived = state.archived;

  final String projectPath;
  final List<String> orderedThreadIds;
  final Set<String> runningThreadIds;
  final Set<String> completedThreadIds;
  final String? selectedThreadId;
  final bool isExpanded;
  final bool hasLoaded;
  final bool isLoadingInitial;
  final bool isLoadingMore;
  final bool hasMore;
  final bool hasError;
  final bool archived;
}

/// 单个 Conversation 的身份、阶段与计数投影，不包含标题、消息或工具正文。
@immutable
final class ZetaConversationStateSnapshot {
  const ZetaConversationStateSnapshot({
    required this.entryId,
    required this.projectPath,
    required this.providerId,
    required this.threadId,
    required this.isDraft,
    required this.isSelected,
    required this.sliceAvailable,
    required this.threadOpenPhase,
    required this.runtimeStatus,
    required this.isTurnRunning,
    required this.isReadOnly,
    required this.visibleTurnCount,
    required this.pendingInteractionCount,
    required this.pendingOperationCount,
  });

  final String entryId;
  final String projectPath;
  final String providerId;
  final String? threadId;
  final bool isDraft;
  final bool isSelected;
  final bool sliceAvailable;
  final AgentThreadOpenPhase threadOpenPhase;
  final AgentThreadRuntimeStatus? runtimeStatus;
  final bool isTurnRunning;
  final bool isReadOnly;
  final int visibleTurnCount;
  final int pendingInteractionCount;
  final int pendingOperationCount;
}

/// Agent Management 的安全摘要；配置正文、路径、日志与错误原文均被排除。
@immutable
final class ZetaAgentManagementStateSnapshot {
  ZetaAgentManagementStateSnapshot.fromState(AgentManagementSliceState state)
    : orderedAgentIds = List.unmodifiable(state.orderedAgentIds),
      agentsById = Map.unmodifiable(<String, ZetaManagedAgentStateSnapshot>{
        for (final id in state.orderedAgentIds)
          if (state.agentsById[id] case final ManagedAgent agent)
            id: ZetaManagedAgentStateSnapshot.fromAgent(agent),
      }),
      selectedAgentId = state.selectedAgentId,
      initialized = state.initialized,
      pendingOperationCount = state.pendingOperations.length,
      hasFailure = state.failure != null;

  final List<String> orderedAgentIds;
  final Map<String, ZetaManagedAgentStateSnapshot> agentsById;
  final String selectedAgentId;
  final bool initialized;
  final int pendingOperationCount;
  final bool hasFailure;
}

/// 单个已支持 Agent 的非敏感运行摘要。
@immutable
final class ZetaManagedAgentStateSnapshot {
  const ZetaManagedAgentStateSnapshot({
    required this.enabled,
    required this.installationState,
    required this.accountState,
    required this.runtimeState,
    required this.versionState,
    required this.needsAttention,
  });

  factory ZetaManagedAgentStateSnapshot.fromAgent(ManagedAgent agent) {
    return ZetaManagedAgentStateSnapshot(
      enabled: agent.enabled,
      installationState: agent.installationState,
      accountState: agent.accountState,
      runtimeState: agent.runtimeState,
      versionState: agent.versionState,
      needsAttention: agent.needsAttention,
    );
  }

  final bool enabled;
  final AgentInstallationState installationState;
  final AgentAccountState accountState;
  final AgentRuntimeState runtimeState;
  final AgentVersionState versionState;
  final bool needsAttention;
}

typedef ZetaShellStateSnapshotReader = ZetaShellStateSnapshot Function();

/// MainApp 与唯一 Workbench 组合边界之间的无监听按需读取桥。
///
/// relay 不缓存快照；每次 [read] 都从当前 feature owner 取一个一致的同步投影。
final class ZetaShellStateSnapshotRelay {
  ZetaShellStateSnapshotReader? _reader;

  bool get isBound => _reader != null;

  void bind(ZetaShellStateSnapshotReader reader) {
    final current = _reader;
    if (current != null && current != reader) {
      throw StateError('A shell state snapshot reader is already bound');
    }
    _reader = reader;
  }

  void unbind(ZetaShellStateSnapshotReader reader) {
    if (_reader == reader) {
      _reader = null;
    }
  }

  ZetaShellStateSnapshot read() {
    final reader = _reader;
    if (reader == null) {
      throw StateError('The shell state snapshot reader is not bound');
    }
    return reader();
  }
}

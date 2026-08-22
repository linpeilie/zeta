import 'package:zeta_agent_core/src/domain/agent_tool_models.dart';
import 'package:zeta_agent_core/src/domain/agent_turn_activity_models.dart';

/// Zeta 自有 Agent 界面文案目录。
///
/// 只接收中立 enum/facts 与必要原文参数，返回当前进程语言的字符串。
/// 不暴露 ARB key、Flutter `Locale`、`BuildContext` 或 Provider raw payload。
abstract interface class AgentUiTextCatalog {
  /// 共享时间线在 reasoning 流尚未给出标题时使用的思考卡 fallback。
  String get thinkingToolTitle;

  /// 中立工具类型的短标签。
  String toolKindLabel(AgentToolKind kind);

  /// 标题栏主活动段文案（不含时长）；idle 返回 null。
  String? activitySegmentLabel(AgentTurnActivitySnapshot activity);

  /// Plan 执行交接卡标题。
  String get planReadyTitle;

  /// 模型改道历史事件标题。
  String get modelReroutedTitle;

  /// 标题栏改道提示；[toModel] 为 Provider 原文。
  String modelReroutedNotice(String toModel);

  /// 适配层弃用提示标题。
  String get deprecationNoticeTitle;

  /// 适配层弃用提示的升级引导。
  String get deprecationUpgradeHint;

  /// 已知的高风险网络活动改道原因。
  String get rerouteReasonHighRisk;

  /// 未知改道原因；[reason] 为 Provider 原文。
  String rerouteReasonUnknown(String reason);

  /// turn 终态失败且未先收到 error 事件时的前缀。
  String get turnFailedPrefix;

  /// Provider 未给出错误概要时的占位。
  String get unknownProviderError;

  /// 服务端将自动重试的附加说明。
  String get serverWillRetry;

  /// 按中立错误码返回可操作引导；未知码返回 null。
  String? errorGuidance(String code);

  String get webSearchTitle;

  String get viewImageTitle;

  String get generateImageTitle;

  String get collaboratePrefix;

  String get toolCallFallbackTitle;

  String get reviewModeEnteredTitle;

  String get reviewModeExitedTitle;

  String get contextCompactedTitle;

  String get contextCompactedDescription;

  String get hookPromptTitle;

  String get waitingTitle;

  String sleepMinutes(String minutes);

  String sleepMinutesSeconds(String minutes, String seconds);

  String sleepSeconds(String seconds);

  String get subAgentActivityTitle;

  String get subAgentStarted;

  String get subAgentInteracted;

  String get subAgentInterrupted;

  String get subAgentUpdated;

  String get userCancelled;

  String get permissionAskDescription;

  String get permissionAcceptEditsDescription;

  String get permissionPlanDescription;

  String get permissionBypassDescription;

  String get planQuotaLabel;

  String get onDemandQuotaLabel;

  String get primaryQuotaLabel;

  String get extraQuotaLabel;

  String get waitingApproval;

  String get waitingInput;

  String get systemError;

  String get loadingConversationModes;

  String get modeNotSelectableNow;

  String get modelCatalogRefreshFailed;

  String get modelListRefreshFailed;

  String get cannotSwitchPermissionDuringTurn;

  String providerReady(String name);

  String get couldNotLoadProviders;

  String get agentIsWorking;

  String get loadingHistory;

  String get creatingBranch;

  String get couldNotUpdateSessionOption;

  String get providerOperationFailed;

  String get modeLoadFailed;

  String fastIncompatible(String effort);

  String fastDisableAndSwitch(String effort);

  String fastSwitchAndEnable(String effort);

  String get modelSaveFailed;

  String modelUnavailableSwitched(String previous, String current);

  String get permNextSession;

  String get permCurrentTurn;

  String get permUnsupported;

  String get permNextSend;

  String get permSavedButPersistFailed;

  String get permAppliedButPersistFailed;

  String get permRuntimeStale;

  String get permSwitchFailed;

  String get providerDefaultPermission;

  String threadDisabled(String name);

  String startingProvider(String name);

  String preparingProvider(String name);

  String couldNotStart(String name);

  String protocolWarning(String name);

  String requestTimedOut(String name);

  String connectionClosedRetry(String name);

  String appServerConnectionClosed(String name);

  String processExited(String name);

  String get failedToSendPrompt;

  String waitingApprovalFor(String title);

  String waitingAnswersFor(String title);

  String get waitingPlanApproval;

  String get planApprovalTitle;

  String sessionIdentityChanged(String name);

  String couldNotRestoreSession(String name);

  String permissionRequestDescription(String name, String tool);

  String get applyPatchTitle;

  String get toolSearchTitle;

  String get historyWebSearchTitle;

  String get agentRequestsInput;

  String get defaultThreadTitle;

  String usageWindowWeeks(String count);

  String usageWindowDays(String count);

  String usageWindowHours(String count);

  String usageWindowHoursMinutes(String hours, String minutes);

  String usageWindowMinutes(String count);

  String get usageWindowOneWeek;

  String get usageWindowOneDay;

  String get quotaFiveHours;

  String get quotaOneWeek;

  String get quotaSonnetOneWeek;

  String get quotaOpusOneWeek;

  String get claudeCodeSubscriptionQuota;

  String get couldNotLoadThreads;

  String get noEnabledProviders;
}

/// 用当前进程目录解析工具卡展示标题。
extension AgentToolCallUiText on AgentToolCall {
  String displayTitle(AgentUiTextCatalog catalog) {
    return buildAgentToolCallDisplayTitle(
      toolCallId: id,
      kindLabel: catalog.toolKindLabel,
      title: title,
      kind: kind,
      locations: locations,
      rawInput: rawInput,
    );
  }
}

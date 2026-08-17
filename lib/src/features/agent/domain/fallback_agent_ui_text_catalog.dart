import 'package:zeta/src/features/agent/domain/agent_tool_models.dart';
import 'package:zeta/src/features/agent/domain/agent_turn_activity_models.dart';
import 'package:zeta/src/features/agent/domain/agent_ui_text_catalog.dart';

/// 测试与未注入目录时的简体中文等价文案，与当前 zh ARB 逐字一致。
class FallbackAgentUiTextCatalog implements AgentUiTextCatalog {
  const FallbackAgentUiTextCatalog();

  @override
  String get thinkingToolTitle => '思考';

  @override
  String toolKindLabel(AgentToolKind kind) {
    return switch (kind) {
      AgentToolKind.read => '读取',
      AgentToolKind.edit => '编辑',
      AgentToolKind.delete => '删除',
      AgentToolKind.move => '移动',
      AgentToolKind.search => '搜索',
      AgentToolKind.execute => '执行',
      AgentToolKind.think => '思考',
      AgentToolKind.fetch => '获取',
      AgentToolKind.other => '操作',
    };
  }

  @override
  String? activitySegmentLabel(AgentTurnActivitySnapshot activity) {
    return switch (activity.phase) {
      AgentTurnActivityPhase.starting => '启动中',
      AgentTurnActivityPhase.thinking => '思考中',
      AgentTurnActivityPhase.responding => '回复中',
      AgentTurnActivityPhase.toolRunning => () {
        final label = activity.label?.trim();
        if (label == null || label.isEmpty) {
          return '执行中';
        }
        final short = label.length > 28 ? '${label.substring(0, 28)}…' : label;
        return '执行中 · $short';
      }(),
      AgentTurnActivityPhase.idle => null,
    };
  }

  @override
  String get planReadyTitle => '计划就绪';

  @override
  String get modelReroutedTitle => '模型已改道';

  @override
  String modelReroutedNotice(String toModel) => '已改道至 $toModel';

  @override
  String get deprecationNoticeTitle => '适配层弃用提示';

  @override
  String get deprecationUpgradeHint => '请升级 Codex 适配层以继续兼容协议变更。';

  @override
  String get rerouteReasonHighRisk => '原因：高风险网络活动策略';

  @override
  String rerouteReasonUnknown(String reason) => '原因：$reason';

  @override
  String get turnFailedPrefix => 'Turn failed: ';

  @override
  String get unknownProviderError => 'Unknown provider error';

  @override
  String get serverWillRetry => '（服务端将自动重试）';

  @override
  String? errorGuidance(String code) {
    return switch (code) {
      'serverOverloaded' => '。当前模型容量已满，请切换其他模型或稍后重试。',
      'usageLimitExceeded' => '。用量或速率额度已用尽，请检查账户额度或稍后重试。',
      'sessionBudgetExceeded' => '。会话预算已用尽，请开启新会话或调整预算后继续。',
      'unauthorized' => '。认证失败，请检查登录状态或 API 凭证后重试。',
      'internalServerError' => '。服务端内部错误，请稍后重试；若持续出现可切换模型。',
      'httpConnectionFailed' ||
      'responseStreamConnectionFailed' ||
      'responseStreamDisconnected' => '。网络连接异常，请检查网络后重试。',
      'responseTooManyFailedAttempts' => '。多次重试仍失败，请稍后重试或切换模型。',
      _ => null,
    };
  }

  @override
  String get webSearchTitle => 'Web 搜索';

  @override
  String get viewImageTitle => '查看图片';

  @override
  String get generateImageTitle => '生成图片';

  @override
  String get collaboratePrefix => '协作';

  @override
  String get toolCallFallbackTitle => 'Tool call';

  @override
  String get reviewModeEnteredTitle => '进入评审模式';

  @override
  String get reviewModeExitedTitle => '退出评审模式';

  @override
  String get contextCompactedTitle => '上下文已压缩';

  @override
  String get contextCompactedDescription => '会话上下文已压缩以腾出窗口空间。';

  @override
  String get hookPromptTitle => 'Hook 提示';

  @override
  String get waitingTitle => '等待中';

  @override
  String sleepMinutes(String minutes) => '休眠 $minutes 分钟';

  @override
  String sleepMinutesSeconds(String minutes, String seconds) =>
      '休眠 $minutes 分 $seconds 秒';

  @override
  String sleepSeconds(String seconds) => '休眠 $seconds 秒';

  @override
  String get subAgentActivityTitle => '子代理活动';

  @override
  String get subAgentStarted => '已启动';

  @override
  String get subAgentInteracted => '已交互';

  @override
  String get subAgentInterrupted => '已中断';

  @override
  String get subAgentUpdated => '更新';

  @override
  String get userCancelled => '用户取消';

  @override
  String get permissionAskDescription => '每个高风险工具都询问';

  @override
  String get permissionAcceptEditsDescription => '自动允许编辑类工具，其他仍询问';

  @override
  String get permissionPlanDescription => '只读并产出计划，不执行副作用';

  @override
  String get permissionBypassDescription => '跳过权限检查（高风险）';

  @override
  String get planQuotaLabel => '套餐额度';

  @override
  String get onDemandQuotaLabel => '按需额度';

  @override
  String get primaryQuotaLabel => '主要额度';

  @override
  String get extraQuotaLabel => '补充额度';

  @override
  String get waitingApproval => '等待审批';

  @override
  String get waitingInput => '等待输入';

  @override
  String get systemError => '系统错误';

  @override
  String get loadingConversationModes => '正在加载对话模式…';

  @override
  String get modeNotSelectableNow => '当前模式暂不支持主动选择';

  @override
  String get modelCatalogRefreshFailed => '模型目录刷新失败，正在使用本地缓存。';

  @override
  String get modelListRefreshFailed => '模型列表刷新失败，已保留现有配置。';

  @override
  String get cannotSwitchPermissionDuringTurn => '当前回合执行中，请等待结束后再切换权限模式。';

  @override
  String providerReady(String name) => '$name ready';

  @override
  String get couldNotLoadProviders => 'Could not load Agent providers';

  @override
  String get agentIsWorking => 'Agent is working';

  @override
  String get loadingHistory => 'Loading history';

  @override
  String get creatingBranch => 'Creating branch';

  @override
  String get couldNotUpdateSessionOption => 'Could not update session option';

  @override
  String get providerOperationFailed => 'Agent provider operation failed';

  @override
  String get modeLoadFailed => '无法加载对话模式，请重试。';

  @override
  String fastIncompatible(String effort) => 'Fast 与“$effort”不兼容';

  @override
  String fastDisableAndSwitch(String effort) => '关闭 Fast 并切换到 $effort';

  @override
  String fastSwitchAndEnable(String effort) => '切换到 $effort 并开启 Fast';

  @override
  String get modelSaveFailed => '配置保存失败，已恢复上次有效设置。';

  @override
  String modelUnavailableSwitched(String previous, String current) =>
      '模型“$previous”当前不可用，已切换到 $current。';

  @override
  String get permNextSession => '下次会话生效';

  @override
  String get permCurrentTurn => '本回合生效';

  @override
  String get permUnsupported => '当前 Provider 不支持权限选择';

  @override
  String get permNextSend => '下次发送时生效';

  @override
  String get permSavedButPersistFailed => '权限偏好已更新，但保存失败；可重试';

  @override
  String get permAppliedButPersistFailed => '权限偏好已应用，但保存失败；可重试';

  @override
  String get permRuntimeStale => 'Provider 运行实例已失效，请重试';

  @override
  String get permSwitchFailed => '权限模式切换失败';

  @override
  String get providerDefaultPermission => 'Provider 默认权限';

  @override
  String threadDisabled(String name) => '$name 已禁用或不可用；无法修改会话。';
}

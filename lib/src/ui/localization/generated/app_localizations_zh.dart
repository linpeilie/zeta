// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appTitle => 'Zeta';

  @override
  String localizationContractGreeting(String name) {
    return '你好 $name';
  }

  @override
  String get shadcnFormNotEmpty => '此项不能为空';

  @override
  String get shadcnInvalidValue => '值无效';

  @override
  String get shadcnInvalidEmail => '邮箱无效';

  @override
  String get shadcnInvalidURL => 'URL 无效';

  @override
  String shadcnFormLessThan(String value) {
    return '必须小于 $value';
  }

  @override
  String shadcnFormGreaterThan(String value) {
    return '必须大于 $value';
  }

  @override
  String shadcnFormLessThanOrEqualTo(String value) {
    return '必须小于或等于 $value';
  }

  @override
  String shadcnFormGreaterThanOrEqualTo(String value) {
    return '必须大于或等于 $value';
  }

  @override
  String get shadcnFormPhoneNumberInvalid => '电话号码无效';

  @override
  String get shadcnFormPhoneNumberEmpty => '请填写电话号码';

  @override
  String shadcnFormBetweenInclusively(String min, String max) {
    return '必须介于 $min 和 $max 之间（含边界）';
  }

  @override
  String shadcnFormBetweenExclusively(String min, String max) {
    return '必须介于 $min 和 $max 之间（不含边界）';
  }

  @override
  String shadcnFormLengthLessThan(String value) {
    return '至少 $value 个字符';
  }

  @override
  String shadcnFormLengthGreaterThan(String value) {
    return '最多 $value 个字符';
  }

  @override
  String get shadcnFormPasswordDigits => '至少包含一位数字';

  @override
  String get shadcnFormPasswordLowercase => '至少包含一个小写字母';

  @override
  String get shadcnFormPasswordUppercase => '至少包含一个大写字母';

  @override
  String get shadcnFormPasswordSpecial => '至少包含一个特殊字符';

  @override
  String get shadcnCommandSearch => '输入命令或搜索…';

  @override
  String get shadcnCommandEmpty => '未找到结果。';

  @override
  String get shadcnCommandMoveUp => '上移';

  @override
  String get shadcnCommandMoveDown => '下移';

  @override
  String get shadcnCommandActivate => '选择';

  @override
  String get shadcnDatePickerSelectYear => '选择年份';

  @override
  String get shadcnPlaceholderDatePicker => '选择日期';

  @override
  String get shadcnPlaceholderTimePicker => '选择时间';

  @override
  String get shadcnPlaceholderColorPicker => '选择颜色';

  @override
  String get shadcnPlaceholderDurationPicker => '选择时长';

  @override
  String get shadcnButtonCancel => '取消';

  @override
  String get shadcnButtonSave => '保存';

  @override
  String get shadcnButtonPrevious => '上一页';

  @override
  String get shadcnButtonNext => '下一页';

  @override
  String get shadcnTimeHour => '时';

  @override
  String get shadcnTimeMinute => '分';

  @override
  String get shadcnTimeSecond => '秒';

  @override
  String get shadcnTimeAM => 'AM';

  @override
  String get shadcnTimePM => 'PM';

  @override
  String get shadcnColorRed => '红';

  @override
  String get shadcnColorGreen => '绿';

  @override
  String get shadcnColorBlue => '蓝';

  @override
  String get shadcnColorAlpha => '透明';

  @override
  String get shadcnColorHue => '色相';

  @override
  String get shadcnColorSaturation => '饱和';

  @override
  String get shadcnColorValue => '明度';

  @override
  String get shadcnColorLightness => '亮度';

  @override
  String get shadcnMenuCut => '剪切';

  @override
  String get shadcnMenuCopy => '复制';

  @override
  String get shadcnMenuPaste => '粘贴';

  @override
  String get shadcnMenuSelectAll => '全选';

  @override
  String get shadcnMenuUndo => '撤销';

  @override
  String get shadcnMenuRedo => '重做';

  @override
  String get shadcnMenuDelete => '删除';

  @override
  String get shadcnMenuShare => '分享';

  @override
  String get shadcnMenuSearchWeb => '搜索网页';

  @override
  String get shadcnMenuLiveTextInput => '实况文本';

  @override
  String get shadcnRefreshTriggerPull => '下拉刷新';

  @override
  String get shadcnRefreshTriggerRelease => '松开刷新';

  @override
  String get shadcnRefreshTriggerRefreshing => '正在刷新…';

  @override
  String get shadcnRefreshTriggerComplete => '刷新完成';

  @override
  String get shadcnColorPickerTabRecent => '最近';

  @override
  String get shadcnColorPickerTabRGB => 'RGB';

  @override
  String get shadcnColorPickerTabHSV => 'HSV';

  @override
  String get shadcnColorPickerTabHSL => 'HSL';

  @override
  String get shadcnColorPickerTabHEX => 'HEX';

  @override
  String shadcnDataTableSelectedRows(String count, String total) {
    return '已选择 $count / $total 行。';
  }

  @override
  String get shadcnDataTableNext => '下一页';

  @override
  String get shadcnDataTablePrevious => '上一页';

  @override
  String get shadcnDataTableColumns => '列';

  @override
  String get shadcnTimeDaysAbbreviation => 'DD';

  @override
  String get shadcnTimeHoursAbbreviation => 'HH';

  @override
  String get shadcnTimeMinutesAbbreviation => 'MM';

  @override
  String get shadcnTimeSecondsAbbreviation => 'SS';

  @override
  String get shadcnDurationDay => '天';

  @override
  String get shadcnDurationHour => '小时';

  @override
  String get shadcnDurationMinute => '分钟';

  @override
  String get shadcnDurationSecond => '秒';

  @override
  String get shadcnAbbreviatedMonday => 'Mo';

  @override
  String get shadcnAbbreviatedTuesday => 'Tu';

  @override
  String get shadcnAbbreviatedWednesday => 'We';

  @override
  String get shadcnAbbreviatedThursday => 'Th';

  @override
  String get shadcnAbbreviatedFriday => 'Fr';

  @override
  String get shadcnAbbreviatedSaturday => 'Sa';

  @override
  String get shadcnAbbreviatedSunday => 'Su';

  @override
  String get shadcnMonthJanuary => 'January';

  @override
  String get shadcnMonthFebruary => 'February';

  @override
  String get shadcnMonthMarch => 'March';

  @override
  String get shadcnMonthApril => 'April';

  @override
  String get shadcnMonthMay => 'May';

  @override
  String get shadcnMonthJune => 'June';

  @override
  String get shadcnMonthJuly => 'July';

  @override
  String get shadcnMonthAugust => 'August';

  @override
  String get shadcnMonthSeptember => 'September';

  @override
  String get shadcnMonthOctober => 'October';

  @override
  String get shadcnMonthNovember => 'November';

  @override
  String get shadcnMonthDecember => 'December';

  @override
  String get shadcnAbbreviatedJanuary => 'Jan';

  @override
  String get shadcnAbbreviatedFebruary => 'Feb';

  @override
  String get shadcnAbbreviatedMarch => 'Mar';

  @override
  String get shadcnAbbreviatedApril => 'Apr';

  @override
  String get shadcnAbbreviatedMay => 'May';

  @override
  String get shadcnAbbreviatedJune => 'Jun';

  @override
  String get shadcnAbbreviatedJuly => 'Jul';

  @override
  String get shadcnAbbreviatedAugust => 'Aug';

  @override
  String get shadcnAbbreviatedSeptember => 'Sep';

  @override
  String get shadcnAbbreviatedOctober => 'Oct';

  @override
  String get shadcnAbbreviatedNovember => 'Nov';

  @override
  String get shadcnAbbreviatedDecember => 'Dec';

  @override
  String get settingsNavGeneral => '常规';

  @override
  String get settingsNavAppearance => '外观';

  @override
  String get settingsNavAgents => 'Agent 管理';

  @override
  String get settingsAgentsUnavailable => 'Agent 管理服务不可用。';

  @override
  String get settingsSendShortcutCmdEnter => 'Cmd + Enter 发送';

  @override
  String get settingsSendShortcutCtrlEnter => 'Ctrl + Enter 发送';

  @override
  String get settingsSendShortcutEnterHint =>
      '按 Enter 发送消息，按 Shift + Enter 换行。';

  @override
  String get settingsSendShortcutCmdHint => '按 Cmd + Enter 发送消息，按 Enter 换行。';

  @override
  String get settingsSendShortcutCtrlHint => '按 Ctrl + Enter 发送消息，按 Enter 换行。';

  @override
  String get settingsMessageSending => '消息发送';

  @override
  String get settingsSendShortcut => '发送快捷键';

  @override
  String get settingsSendShortcutEnter => 'Enter 发送';

  @override
  String get settingsNotifications => '通知';

  @override
  String get settingsSystemNotifications => '系统通知';

  @override
  String get settingsSystemNotificationsHint => '在任务转入后台或其他会话时发送系统提醒。';

  @override
  String get settingsTurnTerminalNotifications => '任务结束';

  @override
  String get settingsTurnTerminalNotificationsHint => '任务完成、失败或中断时提醒。';

  @override
  String get settingsActionRequiredNotifications => '需要确认';

  @override
  String get settingsActionRequiredNotificationsHint =>
      '权限、问题、计划审批或执行确认等待处理时提醒。';

  @override
  String get settingsThemeFollowSystem => '跟随系统';

  @override
  String get settingsThemeFollowSystemHint => '使用系统当前的浅色或深色偏好。';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeLightHint => '使用浅底、低对比度边框和蔚蓝强调色。';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsThemeDarkHint => '使用深底、高对比度面板和明亮强调色。';

  @override
  String get settingsTheme => '主题';

  @override
  String get settingsFonts => '字体';

  @override
  String get settingsUiFont => '界面字体';

  @override
  String get settingsUiFontHint => '用于普通界面文本与非代码 Markdown 正文。';

  @override
  String get settingsUiFontLoadError => '无法加载所选界面字体。';

  @override
  String get settingsUiFontSize => '界面字号';

  @override
  String settingsUiFontSizeHint(String min, String max) {
    return '缩放普通界面文本（$min–$max px）。';
  }

  @override
  String get settingsCodeFont => '代码字体';

  @override
  String get settingsCodeFontHint => '用于代码块、命令、Diff 和工具输出。';

  @override
  String get settingsCodeFontLoadError => '无法加载所选代码字体。';

  @override
  String get settingsCodeFontSize => '代码字号';

  @override
  String settingsCodeFontSizeHint(String min, String max) {
    return '缩放代码内容（$min–$max px）。';
  }

  @override
  String get settingsThemeMode => '主题模式';

  @override
  String settingsLabeledValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String settingsSearchSomething(String label) {
    return '搜索$label';
  }

  @override
  String get settingsNoMatchingFonts => '没有匹配的字体。';

  @override
  String get settingsFontListLoadFailed => '字体列表加载失败。';

  @override
  String settingsFontSizeSemantics(String label, String size) {
    return '$label，当前 $size 像素';
  }

  @override
  String settingsDecreaseSomething(String label) {
    return '减小$label';
  }

  @override
  String settingsPixelValue(String size) {
    return '$size px';
  }

  @override
  String settingsIncreaseSomething(String label) {
    return '增大$label';
  }

  @override
  String get settingsFontGeistDefault => 'Geist（内置默认）';

  @override
  String get settingsFontJetBrainsDefault => 'JetBrainsMono（内置默认）';

  @override
  String get commonCancel => '取消';

  @override
  String get commonConfirm => '确认';

  @override
  String get commonRetry => '重试';

  @override
  String get commonMore => '更多';

  @override
  String get commonRemove => '移除';

  @override
  String get commonMenu => '菜单';

  @override
  String get workbenchHideLeftSidebar => '隐藏左侧栏';

  @override
  String get workbenchShowLeftSidebar => '显示左侧栏';

  @override
  String get workbenchBackToHome => '返回主界面';

  @override
  String get workbenchUsageStatistics => 'Usage statistics';

  @override
  String get workbenchOpenUsageStatistics => 'Open usage statistics page';

  @override
  String get workbenchOpenSettings => 'Open settings page';

  @override
  String get workbenchHideRightSidebar => '隐藏右侧栏';

  @override
  String get workbenchShowRightSidebar => '显示右侧栏';

  @override
  String get workbenchRightSidebarHomeOnly => '右侧栏仅在主界面可用';

  @override
  String get workbenchMenuFile => '文件';

  @override
  String get workbenchMenuOpenProject => '打开项目';

  @override
  String get workbenchMenuQuit => '退出';

  @override
  String get workbenchResizeLeftPanel => 'Resize left panel width';

  @override
  String get workbenchResizeRightPanel => 'Resize right panel width';

  @override
  String get workbenchCannotOpenNotificationThread =>
      '无法打开通知对应的会话：该会话可能已被删除或不在当前项目列表中。';

  @override
  String workbenchProviderDetectionFailed(String error) {
    return '无法检测 Provider：$error';
  }

  @override
  String get workbenchCloseOverlay => 'Close workbench overlay';

  @override
  String get workbenchLogoSemantics => 'Zeta Logo';

  @override
  String get timelineScrollbar => '对话滚动条';

  @override
  String get timelineScrollToBottom => '滚动到对话底部';

  @override
  String get timelineNewContent => '有新内容';

  @override
  String get timelineBackToBottom => '回到底部';

  @override
  String get imagePreviewUnavailable => '图片文件不可用';

  @override
  String get imagePreviewViewLarge => '查看大图';

  @override
  String get imagePreviewView => '查看图片';

  @override
  String tabsLoadingSuffix(String label) {
    return '$label，正在加载';
  }

  @override
  String get homeWelcomeTitle => '欢迎使用 Zeta';

  @override
  String get homeWelcomeSubtitle => '继续最近的工作，或打开一个项目开始。';

  @override
  String get homeOpenProjectFolder => '打开项目文件夹';

  @override
  String get homeOpenProject => '打开项目';

  @override
  String get homeRecentProjects => '近期项目';

  @override
  String get homeReadingRecentProjects => '正在读取近期项目…';

  @override
  String get homeNoRecentProjects => '暂无近期项目';

  @override
  String get homeRecentProjectsAfterRestore => '恢复完成后会在这里显示最近访问的项目。';

  @override
  String get homeRecentProjectsAfterOpen => '打开一个项目后，它会显示在这里。';

  @override
  String get homeRecentSessions => '近期会话';

  @override
  String get homeRefreshFailed => '刷新失败';

  @override
  String get homeCannotRefreshSessions => '无法刷新近期会话';

  @override
  String get homeLoadingRecentSessions => '正在加载近期会话…';

  @override
  String get homeNoRecentSessions => '暂无近期会话';

  @override
  String get homeSessionsCacheHint => '缓存会先显示，最新会话将在后台补齐。';

  @override
  String get homeSessionsEmptyHint => '创建会话后，它会按最近活跃时间显示。';

  @override
  String get homeInstalledProviders => '已安装 Provider';

  @override
  String get homeDetectionFailed => '检测失败';

  @override
  String get homeProviderDetectionFailedTitle => 'Provider 检测失败';

  @override
  String get homeDetectingProviders => '正在检测 Provider…';

  @override
  String get homeNoInstalledProviders => '未检测到已安装 Provider';

  @override
  String get homeProvidersAfterDetect => '检测完成后会显示本机可用的 Agent 环境。';

  @override
  String get homeProvidersAfterInstall => '安装并配置受支持的 Agent 后，它会显示在这里。';

  @override
  String homeOpenRecentProject(String name) {
    return '打开近期项目 $name';
  }

  @override
  String homeOpenRecentSession(String title) {
    return '打开近期会话 $title';
  }

  @override
  String homeCommaJoin(String left, String right) {
    return '$left，$right';
  }

  @override
  String get homeProviderAvailable => '可用';

  @override
  String get homeProviderRunning => '运行中';

  @override
  String get homeProviderDisabled => '已禁用';

  @override
  String get homeProviderNeedsLogin => '需登录';

  @override
  String get homeProviderError => '异常';

  @override
  String get homeProviderUpdateAvailable => '可更新';

  @override
  String get homeProviderDetecting => '检测中';

  @override
  String get projectNewSession => '新建会话';

  @override
  String projectNewSessionFor(String name) {
    return '为 $name 新建会话';
  }

  @override
  String get projectNoRecentSessions => '暂无近期会话';

  @override
  String get projectCreateThreadHint => '创建一个 Thread 后，它会显示在这里。';

  @override
  String get projectCannotLoadSessions => '无法加载近期会话';

  @override
  String get projectPleaseRetryLater => '请稍后重试。';

  @override
  String get projectRetryLoadSessions => '重试加载近期会话';

  @override
  String projectOpenSession(String title) {
    return '打开会话 $title';
  }

  @override
  String get threadWaitingApproval => '等待审批';

  @override
  String get threadWaitingInput => '等待输入';

  @override
  String get threadRunning => '执行中';

  @override
  String get threadSystemError => '系统错误';

  @override
  String get projectOpenFolder => 'Open folder';

  @override
  String get projectRefreshSessions => '刷新会话';

  @override
  String get projectHasRunningThreads => 'Project has running threads';

  @override
  String get threadRename => '重命名';

  @override
  String get threadUnarchive => '取消归档';

  @override
  String get threadArchive => '归档';

  @override
  String get threadFork => '分叉';

  @override
  String get threadDelete => '删除';

  @override
  String get threadRemoveFromZetaOnly => '仅从 Zeta 列表移除';

  @override
  String get threadRemoveFromList => '从列表移除会话';

  @override
  String get threadDeleteSession => '删除会话';

  @override
  String get threadDeleteIrreversible => '此操作不可撤销，将永久删除该会话。';

  @override
  String get threadRemoveIndexOnlyHint =>
      '只会移除 Zeta 的本地索引记录，Provider 端历史文件仍会保留。';

  @override
  String get threadDeleteInAgentHint => '如需彻底删除，请在对应 Agent 工具中处理。';

  @override
  String get threadRunningStatus => 'Thread running';

  @override
  String get threadCompletedClickToDismiss => '执行完毕，点击关闭';

  @override
  String get threadCouldNotLoadThreads => 'Could not load threads';

  @override
  String get projectOpenInFinder => '在 Finder 中打开';

  @override
  String get projectOpenInExplorer => '在资源管理器中打开';

  @override
  String get projectOpenInFileManager => '在文件管理器中打开';

  @override
  String get newThreadSelectProvider => '选择 Agent Provider';

  @override
  String get newThreadLoadingAgents => '正在加载 Agent…';

  @override
  String newThreadCannotLoadAgents(String error) {
    return '无法加载 Agent：$error';
  }

  @override
  String get newThreadNoEnabledProviders =>
      '没有已启用且受支持的 Agent provider。请先在 Settings > Agents 中启用。';

  @override
  String get newThreadChooseAgent => '请选择用于创建新会话的 Agent。';

  @override
  String newThreadUseProvider(String name) {
    return '使用 $name 创建 thread';
  }

  @override
  String get usageTimeRangeToday => '当天';

  @override
  String get usageTimeRangeLast7Days => '最近7天';

  @override
  String get usageTimeRangeLast30Days => '最近30天';

  @override
  String get usageTimeRangeLast90Days => '最近90天';

  @override
  String get usageTimeRangeThisMonth => '本月';

  @override
  String get usageTimeRangePreviousMonth => '上个月';

  @override
  String get usageTimeRangeCustom => '自定义时间';

  @override
  String get usageTaskStatusRunning => '运行中';

  @override
  String get usageTaskStatusCompleted => '成功';

  @override
  String get usageTaskStatusInterrupted => '已取消';

  @override
  String get usageTaskStatusFailed => '失败';

  @override
  String get usageTaskStatusUnknown => '未知';

  @override
  String get usageErrorCategoryAccount => '账号异常';

  @override
  String get usageErrorCategoryCli => '运行时异常';

  @override
  String get usageErrorCategoryNetwork => '网络错误';

  @override
  String get usageErrorCategoryTimeout => '超时';

  @override
  String get usageErrorCategoryCancelled => '用户取消';

  @override
  String get usageErrorCategoryOther => '其他异常';

  @override
  String get usageErrorNextActionAccount => '检查 Codex 登录状态与当前套餐额度。';

  @override
  String get usageErrorNextActionCli => '检查 Codex 版本、配置和运行日志。';

  @override
  String get usageErrorNextActionNetwork => '检查网络、代理设置后重试。';

  @override
  String get usageErrorNextActionTimeout => '缩小任务范围后重试。';

  @override
  String get usageErrorNextActionCancelled => '如需继续，请重新发起该任务。';

  @override
  String get usageErrorNextActionOther => '打开任务详情或 Agent 日志查看原始原因。';

  @override
  String get usageTrendMetricCalls => '调用次数';

  @override
  String get usageTrendMetricSuccessRate => '成功率';

  @override
  String get usageTrendMetricTotalTokens => 'Token 消耗';

  @override
  String get usageTrendMetricAverageResponse => '平均响应时间';

  @override
  String get usageTrendMetricAverageDuration => '任务耗时';

  @override
  String get usageRankSortCalls => '调用次数';

  @override
  String get usageRankSortTotalTokens => 'Token 消耗';

  @override
  String get usageRankSortFailures => '失败次数';

  @override
  String get usageRankSortAverageDuration => '任务耗时';

  @override
  String get usageUnknownProject => '未知项目';

  @override
  String usageLoadFailed(String error) {
    return '无法加载使用统计：$error';
  }

  @override
  String get usageQuotaUnreadable => '套餐额度暂时无法读取';

  @override
  String get usageAgentTemporarilyUnavailable => '当前 Agent 暂时无法连接';

  @override
  String get usageTokenHistoryUnavailable => 'Token 历史暂时无法读取';

  @override
  String get usageTokenSourceMismatch => 'Token 历史数据源配置不匹配';

  @override
  String get usageNoTokenHistory => '暂无 Token 历史';

  @override
  String get usageTodayTokensUnreadable => '今日 Token 暂时无法读取';

  @override
  String get usageIndexWriteFailed => '统计索引暂时无法保存，本次结果仍可正常查看。';

  @override
  String usageIndexReadRescanned(String providerName) {
    return '$providerName 统计索引暂时无法读取，已重新扫描本地历史。';
  }

  @override
  String get usageAgentDisabledOrUnavailable => '该 Agent 已禁用或不可用';

  @override
  String get usageAgentUsageTemporarilyUnavailable => 'Agent 用量暂时无法读取';

  @override
  String get usagePageTitle => '使用统计';

  @override
  String get usagePageSubtitle => '分析调用、性能、Token、项目与套餐额度';

  @override
  String get usageLoadFailedTitle => '统计加载失败';

  @override
  String get usagePartialUnavailable => '部分数据不可用';

  @override
  String get usageReload => '重新加载';

  @override
  String get usageTimeRangeLabel => '时间范围';

  @override
  String get usageAllAgents => '全部 Agent';

  @override
  String get usageModelLabel => '模型';

  @override
  String get usageAllModels => '全部模型';

  @override
  String usageLastUpdated(String time) {
    return '最后更新：$time';
  }

  @override
  String get usageRefresh => '刷新';

  @override
  String usageTokenBreakdownLine(
    String input,
    String output,
    String reasoning,
  ) {
    return '输入 $input · 输出 $output · 推理 $reasoning';
  }

  @override
  String get usageNoTokenStats => '当前筛选下暂无 Token 统计';

  @override
  String get usageTokenUsageLabel => 'Token 使用量';

  @override
  String usageTokenUsageAmount(String amount) {
    return 'Token 使用量 $amount';
  }

  @override
  String get usageCallCount => '调用次数';

  @override
  String usageCallCountSemantic(String count) {
    return '调用次数 $count';
  }

  @override
  String get usageTrendTitle => '使用趋势';

  @override
  String get usageTrendSubtitle => 'Token 消耗 · 粒度根据时间范围自动调整';

  @override
  String usageTrendSemantic(String metric, String count) {
    return '$metric趋势，共 $count 个时间点';
  }

  @override
  String get usageDetailTabsSemantic => '使用统计详情分类';

  @override
  String get usageAgentStats => 'Agent 统计';

  @override
  String get usageModelStats => '模型统计';

  @override
  String get usageProjectList => '项目列表';

  @override
  String get usageTaskList => '任务列表';

  @override
  String get usageRankSummary => '按当前筛选范围汇总';

  @override
  String get usageUnsupported => '不支持';

  @override
  String get usageHeaderCalls => '调用次数';

  @override
  String get usageHeaderSuccessRate => '成功率';

  @override
  String get usageHeaderToken => 'Token';

  @override
  String get usageHeaderFailures => '失败';

  @override
  String get usageHeaderAverageDuration => '平均耗时';

  @override
  String get usageModelTokenShare => '模型 Token 消耗与占比';

  @override
  String get usageNoModelStats => '当前筛选下暂无模型统计';

  @override
  String get usageTokenTotal => '总量';

  @override
  String get usageTokenInput => '输入';

  @override
  String get usageTokenCachedInput => '缓存输入';

  @override
  String get usageTokenOutput => '输出';

  @override
  String get usageTokenReasoning => '推理';

  @override
  String get usageHeaderModel => '模型';

  @override
  String get usageHeaderShare => '占比';

  @override
  String get usageProjectSummary => '按当前筛选范围汇总 · 点击项目可聚焦该项目';

  @override
  String get usageHeaderProject => '项目';

  @override
  String get usageHeaderLastUsed => '最近使用';

  @override
  String usageTaskListSummary(String count, String pageSize) {
    return '共 $count 条 · 每页 $pageSize 条 · 仅展示统计元数据';
  }

  @override
  String get usageHeaderTime => '时间';

  @override
  String get usageHeaderDuration => '耗时';

  @override
  String get usageHeaderStatus => '状态';

  @override
  String get usageUnknownModel => '未知模型';

  @override
  String usageOpenDetail(String name) {
    return '打开$name详情';
  }

  @override
  String get usageTaskDetail => '任务详情';

  @override
  String get usageFieldProject => '项目';

  @override
  String get usageFieldProjectPath => '项目路径';

  @override
  String get usageFieldSource => '来源';

  @override
  String get usageFieldStartTime => '开始时间';

  @override
  String get usageFieldDuration => '执行时间';

  @override
  String get usageFieldFirstResponse => '首次响应';

  @override
  String get usageTokenNotSupported => '当前记录不支持 Token 统计';

  @override
  String usageTokenFullDetail(
    String total,
    String input,
    String cached,
    String output,
    String reasoning,
  ) {
    return '$total （输入 $input / 缓存 $cached / 输出 $output / 推理 $reasoning）';
  }

  @override
  String usageTokenDetail(String cached, String output, String reasoning) {
    return '缓存 $cached / 输出 $output / 推理 $reasoning）';
  }

  @override
  String get usageFieldStatus => '状态';

  @override
  String get usageFieldErrorCategory => '错误分类';

  @override
  String get usageFieldReason => '原因';

  @override
  String get usageNoReason => '未提供详细原因';

  @override
  String get usageFieldNextStep => '下一步';

  @override
  String get usageSourceKindCli => '本地记录';

  @override
  String get usageEmptyTitle => '暂无使用记录';

  @override
  String get usageEmptyBody => '开始使用 Agent 后，这里会展示调用次数、性能和资源消耗。';

  @override
  String get usageOpenAgentManagement => '打开 Agent 管理';

  @override
  String get usageLoading => '正在加载使用统计';

  @override
  String get usageQuickShortcuts => '快捷';

  @override
  String get usageRefreshUsage => '刷新用量';

  @override
  String get usageNoEnabledAgent => '暂无已启用的 Agent';

  @override
  String get usageNoStats => '暂无统计';

  @override
  String get usageCollapseAgentStats => '折叠 Agent 统计';

  @override
  String get usageExpandAgentStats => '展开 Agent 统计';

  @override
  String get usageTodayToken => '今日 Token';

  @override
  String get usageReadingAgentUsage => '正在读取 Agent 用量';

  @override
  String get usageRetryReadAgentUsage => '重试读取 Agent 用量';

  @override
  String get usageSelectAgentUsage => '选择 Agent 用量';

  @override
  String get usageAvailableResetCards => '可用重置卡';

  @override
  String usageResetCardCount(String count) {
    return '$count 张';
  }

  @override
  String get usageAgentStatsSummary => 'Agent 统计摘要';

  @override
  String get usagePlanBusinessUsageBased => 'ChatGPT Business（按量）';

  @override
  String get usagePlanEnterpriseUsageBased => 'ChatGPT Enterprise（按量）';

  @override
  String get usageRetry => '重试';

  @override
  String get usagePrevWindow => '上一窗口';

  @override
  String get usageNextWindow => '下一窗口';

  @override
  String mgmtLocating(String name) {
    return '正在定位 $name';
  }

  @override
  String get mgmtLocatingClaudeCodeCli => '正在检测 Claude Code CLI';

  @override
  String mgmtNotFound(String name) {
    return '未找到 $name';
  }

  @override
  String get mgmtNotFoundClaudeCodeCli => '未找到 Claude Code CLI';

  @override
  String mgmtInstallAndAddToPath(String name) {
    return '请先安装 $name，并确认可执行文件已加入 PATH。';
  }

  @override
  String get mgmtInstallClaudeCodeAndAddToPath =>
      '请先安装 Claude Code，并确认 claude 已加入 PATH。';

  @override
  String mgmtFound(String name) {
    return '已找到 $name';
  }

  @override
  String get mgmtConfirmExecutableThenRedetect => '请确认检测到的可执行文件可以正常执行，然后重新检测。';

  @override
  String get mgmtConfirmClaudeVersionCommand =>
      '请确认 Claude Code CLI 可以正常执行 `claude --version`。';

  @override
  String get mgmtVersionDetected => '已检测当前版本';

  @override
  String get mgmtClaudeVersionDetected => '已检测 Claude Code 版本';

  @override
  String get mgmtAccountDetected => '已检测账号状态';

  @override
  String get mgmtClaudeAuthDetected => '已检测 Claude Code 登录状态';

  @override
  String get mgmtConfigStatusRead => '已读取配置文件状态';

  @override
  String mgmtLogsLocated(String name) {
    return '已定位 $name 日志';
  }

  @override
  String get mgmtLatestVersionChecked => '已检查最新版本';

  @override
  String get mgmtHandshakeComplete => '已完成协议握手';

  @override
  String mgmtDetectionComplete(String name) {
    return '$name 检测完成';
  }

  @override
  String mgmtRetestAfterCheckingConfig(String name) {
    return '请检查 $name 配置和账号状态后重新测试连接。';
  }

  @override
  String get mgmtRetestAfterCheckingGrokAuth => '请检查 Grok 登录态与配置后重新测试连接。';

  @override
  String get mgmtConfirmClaudeAuthStatusJson =>
      '请确认 `claude auth status --json` 可执行；也可运行连接测试确认当前 CLI 认证路径。';

  @override
  String get mgmtNoClaudeLoginEvidenceSuggestion =>
      '未检测到 Claude.ai 登录证据；如需登录可运行 `claude auth login`，也可直接执行连接测试确认当前 CLI 认证路径。';

  @override
  String mgmtCannotIdentifyVersion(String name) {
    return '无法识别 $name 版本。';
  }

  @override
  String get mgmtLatestVersionCheckFailed => '最新版本检查失败。';

  @override
  String get mgmtCannotParseVersionCheck => '无法解析版本检查结果。';

  @override
  String get mgmtVersionServiceUnknownFormat => '版本服务返回了未知格式。';

  @override
  String get mgmtVersionServiceMissingVersion => '版本服务未返回最新版本号。';

  @override
  String mgmtCannotGetLatestVersion(String name) {
    return '无法获取 $name 最新版本。';
  }

  @override
  String get mgmtAccountLoggedIn => '账号已登录';

  @override
  String get mgmtRunCodexLogin => '请在终端运行 codex login 后重新检测。';

  @override
  String get mgmtRunGrokLogin => '请在终端运行 grok login 后重新检测。';

  @override
  String get mgmtRerunGrokLogin => '请重新运行 grok login。';

  @override
  String get mgmtRunCodexLoginStatus => '请在终端运行 codex login status 查看详细信息。';

  @override
  String get mgmtFixConfigTomlThenRedetect => '请修复 config.toml 中提示的字段后重新检测。';

  @override
  String get mgmtCodexConfigUnparseable => 'Codex 配置文件无法解析。';

  @override
  String get mgmtCannotDetectAccount => '无法检测账号状态。';

  @override
  String get mgmtAccountCheckFailed => '账号状态检测失败。';

  @override
  String mgmtConfirmCliRuns(String name) {
    return '请确认 $name 可以在终端中正常运行。';
  }

  @override
  String get mgmtCannotParseGrokLoginCache => '无法解析 Grok 登录缓存。';

  @override
  String get mgmtNoClaudeLoginEvidenceLabel =>
      '未检测到 Claude.ai OAuth 或 API key 登录证据';

  @override
  String get mgmtCannotCheckClaudeAuth => '无法通过 Claude CLI 检查登录状态。';

  @override
  String get mgmtCannotStartClaudeInitialize =>
      '无法启动 Claude Code initialize 探测。';

  @override
  String get mgmtClaudeAuthViaApiKey => '已通过 Anthropic API key 配置认证';

  @override
  String get mgmtClaudeAuthViaApiKeyHelper => '已通过 API key helper 配置认证';

  @override
  String get mgmtClaudeAuthViaOauthToken => '已通过 OAuth token 配置认证';

  @override
  String get mgmtClaudeAuthPathDetected => '已检测到 Claude Code 认证路径';

  @override
  String get mgmtThirdPartyApiProviderConfigured => '已配置第三方 API Provider';

  @override
  String mgmtConfiguredProvider(String provider) {
    return '已配置 $provider';
  }

  @override
  String get mgmtPathNotRegularFile => '该路径不存在或不是普通文件';

  @override
  String get mgmtRefuseSymlinkConfig => '拒绝写入符号链接配置文件';

  @override
  String get mgmtConfigExternallyModified => '配置文件已在外部发生修改。';

  @override
  String get mgmtCompatSupported => '已验证支持';

  @override
  String get mgmtCompatLimited => '兼容运行，部分能力关闭';

  @override
  String get mgmtCompatNewerUntested => '版本较新，尚未完整验证';

  @override
  String get mgmtCompatOlderUnsupported => '版本过旧，不受支持';

  @override
  String get mgmtCompatProtocolMismatch => '协议不兼容';

  @override
  String mgmtCannotEnable(String name, String error) {
    return '无法启用 $name：$error';
  }

  @override
  String mgmtCannotDisable(String name, String error) {
    return '无法禁用 $name：$error';
  }

  @override
  String mgmtAccountDataEnrichmentSaveFailed(String error) {
    return '额度详情增强设置保存失败：$error';
  }

  @override
  String mgmtConnectionTestFailed(String error) {
    return '连接测试失败：$error';
  }

  @override
  String mgmtConfigurationReadFailed(String error) {
    return '配置文件读取失败：$error';
  }

  @override
  String get mgmtConfigurationNotLoaded => '配置文件尚未加载';

  @override
  String mgmtLogsReadFailed(String error) {
    return '运行日志读取失败：$error';
  }

  @override
  String get mgmtOperationIncomplete => '操作未完成';

  @override
  String get mgmtFilterInstalled => '已安装';

  @override
  String get mgmtFilterAllSupported => '全部支持';

  @override
  String get mgmtSearchPlaceholder => '搜索 Agent 或厂商';

  @override
  String get mgmtDetecting => '正在检测…';

  @override
  String get mgmtAutoDetect => '自动检测 Agent';

  @override
  String get mgmtEmptyInstalledTitle => '暂未检测到已安装的 Agent';

  @override
  String get mgmtEmptyInstalledBody => '可以自动检测本机环境，或者前往“全部支持”查看当前应用支持的 Agent。';

  @override
  String get mgmtViewAllSupported => '查看全部支持';

  @override
  String get mgmtNoMatchTitle => '没有找到匹配的 Agent';

  @override
  String get mgmtNoMatchBody => '请尝试修改搜索内容。';

  @override
  String get mgmtClearSearch => '清除搜索';

  @override
  String mgmtVersionWithValue(String version) {
    return '版本 $version';
  }

  @override
  String get mgmtUnknown => '未知';

  @override
  String get mgmtTesting => '正在测试…';

  @override
  String get mgmtTestConnection => '测试连接';

  @override
  String get mgmtViewLogs => '查看运行日志';

  @override
  String get mgmtDisableAgent => '禁用 Agent';

  @override
  String get mgmtEnableAgent => '启用 Agent';

  @override
  String get mgmtTabBasics => '基础信息';

  @override
  String get mgmtTabModels => '模型';

  @override
  String get mgmtTabConfig => '配置';

  @override
  String get mgmtCopiedCommand => '已复制启动命令。';

  @override
  String get mgmtCannotLoadModels => '无法加载模型列表';

  @override
  String get mgmtModelsNeedLogin => '当前账号尚未登录。登录 Codex 后重新加载。';

  @override
  String get mgmtReload => '重新加载';

  @override
  String mgmtModelSourceUpdated(String source, String updated) {
    return '数据来源：$source · 更新时间：$updated';
  }

  @override
  String get mgmtDisableWarning => '禁用后将停止当前任务，已有会话会变为只读模式。';

  @override
  String get mgmtStopAndDisable => '停止并禁用';

  @override
  String get mgmtTestClaudeTitle => '测试 Claude Code 连接';

  @override
  String get mgmtTestClaudeBody =>
      '只发送无 Prompt 的 initialize 控制请求，不调用模型；Claude CLI 仍可能维护自身认证或 bootstrap 缓存。';

  @override
  String get mgmtContinueTest => '继续测试';

  @override
  String mgmtConnectionTestSuccess(String ms) {
    return '连接测试成功，响应耗时 $ms ms。';
  }

  @override
  String mgmtConnectionTestFailedMessage(String message) {
    return '连接测试失败：$message';
  }

  @override
  String get mgmtUnknownError => '未知错误';

  @override
  String mgmtCannotOpenExecutableDir(String error) {
    return '无法打开可执行文件目录：$error';
  }

  @override
  String mgmtViewDetails(String name) {
    return '查看 $name 详情';
  }

  @override
  String get mgmtVersionUnknown => '版本未知';

  @override
  String get mgmtNotInstalled => '未安装';

  @override
  String get mgmtConnectionAvailable => '连接可用';

  @override
  String get mgmtUpdateAvailable => '可更新';

  @override
  String get mgmtDetectingShort => '检测中';

  @override
  String get mgmtRunning => '运行中';

  @override
  String get mgmtEnabled => '已启用';

  @override
  String get mgmtInstalled => '已安装';

  @override
  String get mgmtSectionBasics => '基础信息';

  @override
  String get mgmtBasicAttributes => '基本属性';

  @override
  String get mgmtName => '名称';

  @override
  String get mgmtVendor => '厂商';

  @override
  String get mgmtProtocol => '通信协议';

  @override
  String get mgmtTransport => '传输方式';

  @override
  String get mgmtSectionVersion => '版本';

  @override
  String get mgmtCurrentVersion => '当前版本';

  @override
  String get mgmtLatestVersion => '最新版本';

  @override
  String get mgmtPathsAndCommands => '路径与命令';

  @override
  String get mgmtLaunchCommand => '启动命令';

  @override
  String get mgmtExecutablePath => '可执行文件路径';

  @override
  String get mgmtNotDetected => '未检测到';

  @override
  String get mgmtExecutableNotDetectedHint => '尚未检测到可执行文件，请先安装并确保已加入 PATH';

  @override
  String get mgmtAutoDetectShort => '自动检测';

  @override
  String get mgmtOpenDirectory => '打开目录';

  @override
  String get mgmtProgram => '程序';

  @override
  String get mgmtExecutablePresent => '可执行文件存在且可调用';

  @override
  String get mgmtExecutableMissing => '未找到可执行文件';

  @override
  String get mgmtAuthEvidence => '认证证据';

  @override
  String get mgmtCommunication => '通信';

  @override
  String get mgmtConnectionProbeOk => '连接探测成功';

  @override
  String get mgmtHandshakeOk => '基础握手正常';

  @override
  String get mgmtNotConfirmed => '尚未确认';

  @override
  String get mgmtLastDetected => '最近检测';

  @override
  String get mgmtLastTestDuration => '最近测试耗时';

  @override
  String get mgmtHandshakeIdentity => '握手身份';

  @override
  String get mgmtNegotiatedCapabilities => '协商能力';

  @override
  String get mgmtCompatibility => '兼容性';

  @override
  String get mgmtExitReason => '退出原因';

  @override
  String get mgmtFailureStage => '异常阶段';

  @override
  String get mgmtDiagnostics => '诊断';

  @override
  String get mgmtConnectionHealthy => '连接正常';

  @override
  String mgmtSuggestedAction(String suggestion) {
    return '建议操作：$suggestion';
  }

  @override
  String get mgmtHidden => '隐藏';

  @override
  String get mgmtAvailable => '可用';

  @override
  String get mgmtChipText => '文本';

  @override
  String get mgmtChipImage => '图片';

  @override
  String get mgmtChipCode => '代码';

  @override
  String get mgmtChipFiles => '文件操作';

  @override
  String get mgmtChipTools => '工具调用';

  @override
  String get mgmtChipTerminal => '终端';

  @override
  String get mgmtChipStreaming => '流式输出';

  @override
  String get mgmtReasoningUnknown => '思考能力：未知';

  @override
  String mgmtReasoningAdjustable(String efforts) {
    return '思考能力：可调节（$efforts）';
  }

  @override
  String get mgmtQuotaEnrichmentTitle => '额度详情增强';

  @override
  String get mgmtQuotaEnrichmentLabel => '读取 Claude Code 额度详情';

  @override
  String get mgmtQuotaEnrichmentBody =>
      '此开关只控制 Zeta 是否瞬时读取 Claude Code OAuth 凭据并调用 usage REST。模型列表与套餐名称始终来自 Claude CLI；Zeta 不会刷新、写回或持久化凭据。';

  @override
  String get mgmtOnboardingTitle => '接入指引';

  @override
  String get mgmtOnboardingSubtitle => '安装 · 登录 · 文档';

  @override
  String get mgmtAccountUnknown => '无法检测';

  @override
  String get mgmtAccountChecking => '检测中';

  @override
  String get mgmtAccountLoggedInShort => '已登录';

  @override
  String get mgmtAccountLoggedOut => '未登录';

  @override
  String get mgmtAccountExpired => '登录失效';

  @override
  String get mgmtAccountNotRequired => '无需登录';

  @override
  String get mgmtRuntimeNotRunning => '未运行';

  @override
  String get mgmtRuntimeIdle => '空闲';

  @override
  String get mgmtRuntimeStarting => '启动中';

  @override
  String get mgmtRuntimeStopping => '停止中';

  @override
  String get mgmtRuntimeError => '异常';

  @override
  String get mgmtRuntimeUnavailable => '不可用';

  @override
  String get mgmtRuntimeDisabled => '已禁用';

  @override
  String get mgmtStageFileDetection => '文件检测';

  @override
  String get mgmtStageCliStartup => '进程启动';

  @override
  String get mgmtStageVersionDetection => '版本检测';

  @override
  String get mgmtStageAccountAuthentication => '账号认证';

  @override
  String get mgmtStageProtocolHandshake => '协议握手';

  @override
  String get mgmtStageModelLoading => '模型读取';

  @override
  String get mgmtStageConfigurationRead => '配置读取';

  @override
  String get mgmtStageTestRequest => '测试请求';

  @override
  String get mgmtStageProcessExit => '进程退出';

  @override
  String get mgmtListScope => 'Agent 列表范围';

  @override
  String get mgmtDetailTabs => 'Agent 详情';

  @override
  String get mgmtModelsHandshakeFailed => 'Codex app-server 未返回模型，或当前配置无法完成握手。';

  @override
  String mgmtAgentCurrentlyRunning(String name) {
    return '$name 当前正在运行';
  }

  @override
  String get mgmtStatusNeedsCheck => '状态需要检查';

  @override
  String mgmtRuntimeLogsTitle(String name) {
    return '$name 运行日志';
  }

  @override
  String mgmtLogSourcesLoaded(String sources, String lines) {
    return '$sources 个诊断来源 · $lines 行已加载';
  }

  @override
  String get mgmtNotUpdated => '尚未更新';

  @override
  String get mgmtUnsavedTitle => '配置尚未保存';

  @override
  String get mgmtUnsavedBody => '离开后本次修改将丢失。';

  @override
  String get mgmtKeepEditing => '继续编辑';

  @override
  String get mgmtDiscardChanges => '放弃修改';

  @override
  String get mgmtLoadingConfig => '正在加载配置文件';

  @override
  String get mgmtConfigNotLoadedYet => '配置文件尚未加载。';

  @override
  String get mgmtSensitiveMaskedTitle => '敏感值已遮挡';

  @override
  String get mgmtSensitiveMaskedBody =>
      '为避免凭证意外暴露，默认以只读方式显示。点击“显示敏感值”后才可编辑完整配置。';

  @override
  String get mgmtConfigFile => '配置文件';

  @override
  String get mgmtConfigExists => '已存在';

  @override
  String get mgmtConfigMissing => '尚未创建';

  @override
  String mgmtLastLoaded(String time) {
    return '最后加载 $time';
  }

  @override
  String get mgmtReloadConfig => '重新加载';

  @override
  String get mgmtOpenContainingFolder => '打开所在目录';

  @override
  String get mgmtHideSensitive => '隐藏敏感值';

  @override
  String get mgmtShowSensitive => '显示敏感值';

  @override
  String get mgmtSearchInConfig => '在配置中查找';

  @override
  String get mgmtFindNext => '查找下一个';

  @override
  String get mgmtConfigValid => '配置格式有效';

  @override
  String get mgmtCancelEdits => '取消修改';

  @override
  String get mgmtSaving => '正在保存…';

  @override
  String get mgmtSaveConfig => '保存配置';

  @override
  String get mgmtConfigSavedRestart => '配置已保存。请重新启动 Codex 以应用新配置。';

  @override
  String get mgmtConfigSavedBackup => '配置已保存，并已创建原文件备份。';

  @override
  String get mgmtConfigExternalTitle => '配置文件已在外部发生修改';

  @override
  String get mgmtConfigExternalBody => '继续保存将覆盖外部修改。';

  @override
  String get mgmtSaveAnyway => '仍然保存';

  @override
  String mgmtConfigSaveFailed(String error) {
    return '配置保存失败：$error';
  }

  @override
  String mgmtQueryNotFound(String query) {
    return '没有找到“$query”。';
  }

  @override
  String mgmtCannotOpenConfigDir(String error) {
    return '无法打开配置目录：$error';
  }

  @override
  String get mgmtRefreshing => '刷新中…';

  @override
  String get mgmtRefresh => '刷新';

  @override
  String get mgmtCopyLogs => '复制日志';

  @override
  String get mgmtSearchLogKeywords => '搜索日志关键词';

  @override
  String get mgmtLogLevel => '日志级别';

  @override
  String get mgmtAll => '全部';

  @override
  String get mgmtReadingLogs => '正在读取 Agent 日志';

  @override
  String get mgmtNoMatchingLogs => '没有符合当前条件的日志。';

  @override
  String mgmtCopiedLogs(String count) {
    return '已复制 $count 行脱敏日志。';
  }

  @override
  String get agentReadonlyTitle => '此会话为只读模式';

  @override
  String get agentReadonlyBody => '该会话所属的 Agent 已被禁用。你仍可查看历史数据，但不能继续发送消息。';

  @override
  String get agentMessagePlaceholder => 'Message Agent';

  @override
  String get agentSend => 'Send';

  @override
  String get agentCancel => 'Cancel';

  @override
  String get agentCancelAction => '取消';

  @override
  String get agentCancelTurn => '取消回合';

  @override
  String get agentMoreActions => 'More actions';

  @override
  String get agentMoreActionsExpanded => 'More actions, expanded';

  @override
  String get agentMentionFile => 'Mention file';

  @override
  String get agentInsertSkill => 'Insert skill';

  @override
  String get agentAttachImage => 'Attach image';

  @override
  String get agentPermissionMode => '权限模式';

  @override
  String get agentPlanReadOnlyHint => '只读规划，不能改文件';

  @override
  String get agentTokenUsage => 'Token 用量';

  @override
  String get agentContextWindowUsage => 'Context window token usage';

  @override
  String get agentRename => '重命名';

  @override
  String get agentForkSession => '分叉当前会话';

  @override
  String get agentArchive => '归档';

  @override
  String get agentContext => '上下文';

  @override
  String get agentMore => '更多';

  @override
  String agentProjectName(String name) {
    return '项目 $name';
  }

  @override
  String get agentReadonlyPlanMode => '只读 Plan 模式';

  @override
  String get agentLoadingSession => '正在加载会话…';

  @override
  String get agentAcceptPlan => '接受计划';

  @override
  String get agentAcceptPlanHint => '接受计划仅确认方案；命令、文件与网络权限仍会单独请求。';

  @override
  String get agentCommandGroup => '命令组';

  @override
  String get agentFileEditGroup => '文件编辑组';

  @override
  String get agentToolCall => '工具调用';

  @override
  String get agentThinking => '思考中';

  @override
  String get agentRunning => '执行中';

  @override
  String agentRunningPrefix(String title) {
    return '执行中 · $title';
  }

  @override
  String get agentExecute => '执行';

  @override
  String get agentSteps => '步骤';

  @override
  String get agentRevisePlanHint => '补充或修改计划…';

  @override
  String get agentRevise => '修改';

  @override
  String get agentAbandon => '放弃';

  @override
  String get agentExecPermission => '执行权限';

  @override
  String get agentChooseExecPermission => '请选择执行权限';

  @override
  String get agentPermCatalogDefault => '保守默认';

  @override
  String get agentPermUserOverride => '仅本次';

  @override
  String get agentPermNeedsChoice => '需要选择';

  @override
  String agentPermissionRequest(String kind, String title) {
    return '权限请求：$kind · $title';
  }

  @override
  String get agentDeny => '拒绝';

  @override
  String get agentAllowSession => '本会话允许';

  @override
  String get agentAlwaysAllow => '始终允许';

  @override
  String get agentOverrideGuard => '覆盖守护';

  @override
  String get agentAllow => '允许';

  @override
  String get agentPermKindCommand => '执行命令';

  @override
  String get agentPermKindFile => '应用文件变更';

  @override
  String get agentPermKindPermissions => '授予权限';

  @override
  String get agentPermKindOther => '请求确认';

  @override
  String get agentPermShortCommand => '命令';

  @override
  String get agentPermShortFile => '文件';

  @override
  String get agentPermShortPermissions => '权限';

  @override
  String get agentPermShortOther => '确认';

  @override
  String get agentCloseQuestion => '关闭提问';

  @override
  String get agentNoAnswerableQuestions => '该请求没有可回答的问题。';

  @override
  String get agentSubmitAnswers => '提交答案';

  @override
  String get agentConfirmNextQuestion => '确认并进入下一题';

  @override
  String get agentSkip => '跳过';

  @override
  String get agentSubmit => '提交';

  @override
  String get agentNext => '下一步';

  @override
  String get agentMultiSelect => '可选择多个选项';

  @override
  String get agentPreviousQuestion => '上一题';

  @override
  String get agentNextQuestion => '下一题';

  @override
  String get agentCustomSolutionHint => '输入你的解决方案…';

  @override
  String get agentOtherCustomSolution => '其他，输入自定义解决方案';

  @override
  String get agentWaitingApproval => '等待审批';

  @override
  String get agentWaitingInput => '等待输入';

  @override
  String get agentSystemError => '系统错误';

  @override
  String get agentToolRead => '读取';

  @override
  String get agentToolEdit => '编辑';

  @override
  String get agentToolDelete => '删除';

  @override
  String get agentToolMove => '移动';

  @override
  String get agentToolSearch => '搜索';

  @override
  String get agentToolExecute => '执行';

  @override
  String get agentToolThink => '思考';

  @override
  String get agentToolFetch => '获取';

  @override
  String get agentToolOther => '操作';

  @override
  String get agentTurnChanges => '本回合改动';

  @override
  String agentFileCount(String count) {
    return '$count 个文件';
  }

  @override
  String get agentNavConversation => '对话导航';

  @override
  String agentTurnOrdinal(String n) {
    return '第 $n 个回合';
  }

  @override
  String agentTurnOrdinalWithLabel(String n, String label) {
    return '第 $n 个回合：$label';
  }

  @override
  String get agentStatusStreaming => '生成中';

  @override
  String get agentStatusCompleted => '已完成';

  @override
  String get agentStatusFailed => '失败';

  @override
  String get agentStatusInterrupted => '已中断';

  @override
  String get agentStatusUnknown => '未知';

  @override
  String get agentCreateBranchHere => '从此处创建分支';

  @override
  String get agentCreateBranchRetry => '创建分支并重试';

  @override
  String get agentCreateBranchBody =>
      '将保留原会话，并从上一回合结束处创建新分支。工作区文件不会回滚，之前由 Agent 写入的改动仍然存在。';

  @override
  String get agentEditMessage => '编辑消息…';

  @override
  String get agentCreateBranchSend => '创建分支并发送';

  @override
  String get agentPlan => '计划';

  @override
  String get agentCollapsePlan => '收起计划';

  @override
  String get agentExpandPlan => '展开计划';

  @override
  String get agentCollapseCurrentPlan => '收起当前计划';

  @override
  String get agentExpandCurrentPlan => '展开当前计划';

  @override
  String agentCurrentPlanProgress(String progress) {
    return '当前计划进度 $progress';
  }

  @override
  String agentCurrentStep(String content) {
    return '当前步骤：$content';
  }

  @override
  String get agentCurrent => '当前';

  @override
  String get agentPlanCompleted => '已完成';

  @override
  String get agentPlanInProgress => '进行中';

  @override
  String get agentPlanPending => '待处理';

  @override
  String get agentPlanUnknown => '状态未知';

  @override
  String get agentNoExecPermission => '当前没有可用的执行权限，请先选择；执行不会预授权命令、文件或网络。';

  @override
  String agentDefaultExecPermission(String label) {
    return '默认使用“$label”；执行将开启新的 Default 回合，命令、文件与网络权限仍按该模式处理。';
  }

  @override
  String get agentSlashCommands => '命令';

  @override
  String get agentModel => '模型';

  @override
  String get agentModelLoadFailed => '模型加载失败';

  @override
  String get agentModelConfig => '模型配置';

  @override
  String get agentLoadingModels => '正在加载模型…';

  @override
  String get agentNoModels => '暂无可用模型';

  @override
  String get agentConfigNextTurn => '配置将在下一回合生效';

  @override
  String get agentModelUnavailable => '该模型当前不可用';

  @override
  String get agentNoReasoningConfig => '该模型未提供可配置的思考程度';

  @override
  String get agentRetry => '重试';

  @override
  String get agentReasoningEffort => '思考程度';

  @override
  String get agentFastOn => '已开启';

  @override
  String get agentFastOff => '已关闭';

  @override
  String get agentClose => '关闭';

  @override
  String get agentSessionName => '会话名称';

  @override
  String get agentSessionId => '会话 ID';

  @override
  String get agentMessageCount => '消息数';

  @override
  String get agentProvider => '提供商';

  @override
  String get agentContextLimit => '上下文限制';

  @override
  String get agentTotalTokens => '总 Token';

  @override
  String get agentInputTokens => '输入 Token';

  @override
  String get agentOutputTokens => '输出 Token';

  @override
  String get agentCachedTokens => '缓存 Token';

  @override
  String get agentCreatedAt => '创建时间';

  @override
  String get agentLastActive => '最后活跃时间';

  @override
  String get agentRawMessages => '原始消息';

  @override
  String get agentChatOnly => '仅对话';

  @override
  String get agentAll => '全部';

  @override
  String get agentShowChatOnly => '当前仅显示对话消息，点击显示全部';

  @override
  String get agentShowAllMessages => '当前显示全部消息，点击仅显示对话';

  @override
  String get agentNoChatMessages => '暂无对话消息';

  @override
  String get agentNoRawMessages => '暂无原始消息';

  @override
  String get agentCopyOriginal => '复制原文';

  @override
  String get agentCopiedOriginal => '已复制原文。';

  @override
  String get agentKindApproval => '审批';

  @override
  String get agentKindQuestion => '提问';

  @override
  String get agentKindPlanApproval => '计划审批';

  @override
  String get agentKindFileChange => '文件变更';

  @override
  String get agentRoleUser => '用户';

  @override
  String get agentRoleAgent => '助手';

  @override
  String get agentRoleSystem => '系统';

  @override
  String get agentEvidenceReplaceBefore => '替换前';

  @override
  String get agentEvidenceReplaceAfter => '替换后';

  @override
  String get agentEvidenceEmptySnippet => '空片段（Provider 明确提供）';

  @override
  String get agentEvidenceEmptyContent => '空内容（Provider 明确提供）';

  @override
  String get agentEvidenceEmptyDiff => '空差异（Provider 明确提供）';

  @override
  String get agentEvidenceAdd => '新增';

  @override
  String get agentEvidenceRemove => '删除';

  @override
  String get agentEvidenceWrite => '写入';

  @override
  String get agentWrittenContent => '写入内容';

  @override
  String agentWrittenContentWithStatus(String title, String status) {
    return '$title · $status';
  }

  @override
  String get agentUnifiedDiff => '统一差异';

  @override
  String get agentDiffMetadata => '差异元数据';

  @override
  String get agentDiffHunkTitle => '差异分块标题';

  @override
  String get agentEmptyLine => '空行';

  @override
  String get agentLiveSummary => '本回合实时汇总';

  @override
  String get agentLiveSummaryHint => '本回合实时汇总，不可从历史恢复';

  @override
  String get agentTurnSummary => '本回合汇总';

  @override
  String get agentReplaceSnippet => '替换片段';

  @override
  String get agentReplaceSnippetAll => '替换片段 · 全部匹配';

  @override
  String get agentFileCreated => '新建';

  @override
  String get agentFileModified => '修改';

  @override
  String get agentFileDeleted => '删除';

  @override
  String get agentFileMoved => '移动';

  @override
  String get agentFileChanged => '文件变更';

  @override
  String get agentToolPending => '待执行';

  @override
  String get agentToolInProgress => '进行中';

  @override
  String get agentToolCompleted => '已完成';

  @override
  String get agentToolFailed => '失败';

  @override
  String get agentToolCancelled => '已取消';

  @override
  String get agentConversationModeIcon => '对话模式图标';

  @override
  String get agentConversationModeOptions => '对话模式选项';

  @override
  String get agentModeSelected => '已选择';

  @override
  String get agentModeSelectable => '可选择';

  @override
  String get agentModeNotSelectable => '不可选择';

  @override
  String get agentLoadingModes => '正在加载对话模式';

  @override
  String get agentCannotLoadModes => '当前 Provider 无法加载对话模式';

  @override
  String get agentStarting => '启动中';

  @override
  String get agentResponding => '回复中';

  @override
  String get agentPlanReady => '计划就绪';

  @override
  String get agentModelRerouted => '模型已改道';

  @override
  String agentModelReroutedTo(String model) {
    return '已改道至 $model';
  }

  @override
  String get agentDeprecationNotice => '适配层弃用提示';

  @override
  String get agentDeprecationUpgradeHint => '请升级 Codex 适配层以继续兼容协议变更。';

  @override
  String get agentRerouteReasonHighRisk => '原因：高风险网络活动策略';

  @override
  String agentRerouteReasonUnknown(String reason) {
    return '原因：$reason';
  }

  @override
  String get agentTurnFailedPrefix => 'Turn failed: ';

  @override
  String get agentUnknownProviderError => 'Unknown provider error';

  @override
  String get agentServerWillRetry => '（服务端将自动重试）';

  @override
  String get agentErrorGuidanceServerOverloaded => '。当前模型容量已满，请切换其他模型或稍后重试。';

  @override
  String get agentErrorGuidanceUsageLimit => '。用量或速率额度已用尽，请检查账户额度或稍后重试。';

  @override
  String get agentErrorGuidanceSessionBudget => '。会话预算已用尽，请开启新会话或调整预算后继续。';

  @override
  String get agentErrorGuidanceUnauthorized => '。认证失败，请检查登录状态或 API 凭证后重试。';

  @override
  String get agentErrorGuidanceInternalServer => '。服务端内部错误，请稍后重试；若持续出现可切换模型。';

  @override
  String get agentErrorGuidanceNetwork => '。网络连接异常，请检查网络后重试。';

  @override
  String get agentErrorGuidanceTooManyAttempts => '。多次重试仍失败，请稍后重试或切换模型。';

  @override
  String get agentWebSearch => 'Web 搜索';

  @override
  String get agentViewImage => '查看图片';

  @override
  String get agentGenerateImage => '生成图片';

  @override
  String get agentCollaboratePrefix => '协作';

  @override
  String get agentToolCallFallback => 'Tool call';

  @override
  String get agentReviewModeEntered => '进入评审模式';

  @override
  String get agentReviewModeExited => '退出评审模式';

  @override
  String get agentContextCompacted => '上下文已压缩';

  @override
  String get agentContextCompactedDescription => '会话上下文已压缩以腾出窗口空间。';

  @override
  String get agentHookPrompt => 'Hook 提示';

  @override
  String get agentWaiting => '等待中';

  @override
  String agentSleepMinutes(String minutes) {
    return '休眠 $minutes 分钟';
  }

  @override
  String agentSleepMinutesSeconds(String minutes, String seconds) {
    return '休眠 $minutes 分 $seconds 秒';
  }

  @override
  String agentSleepSeconds(String seconds) {
    return '休眠 $seconds 秒';
  }

  @override
  String get agentSubAgentActivity => '子代理活动';

  @override
  String get agentSubAgentStarted => '已启动';

  @override
  String get agentSubAgentInteracted => '已交互';

  @override
  String get agentSubAgentInterrupted => '已中断';

  @override
  String get agentSubAgentUpdated => '更新';

  @override
  String get agentUserCancelled => '用户取消';

  @override
  String get agentPermissionAskDescription => '每个高风险工具都询问';

  @override
  String get agentPermissionAcceptEditsDescription => '自动允许编辑类工具，其他仍询问';

  @override
  String get agentPermissionPlanDescription => '只读并产出计划，不执行副作用';

  @override
  String get agentPermissionBypassDescription => '跳过权限检查（高风险）';

  @override
  String get agentPlanQuota => '套餐额度';

  @override
  String get agentOnDemandQuota => '按需额度';

  @override
  String get agentPrimaryQuota => '主要额度';

  @override
  String get agentExtraQuota => '补充额度';

  @override
  String get desktopAttentionTurnCompleted => '任务已完成';

  @override
  String get desktopAttentionTurnFailed => '任务执行失败';

  @override
  String get desktopAttentionTurnInterrupted => '任务已中断';

  @override
  String get desktopAttentionPermissionRequired => '需要确认权限';

  @override
  String get desktopAttentionQuestionRequired => '需要回答问题';

  @override
  String get desktopAttentionPlanApprovalRequired => '需要确认计划';

  @override
  String get desktopAttentionPlanExecutionRequired => '计划可以执行';

  @override
  String get desktopAttentionCurrentProject => '当前项目';

  @override
  String desktopAttentionSessionBody(String project) {
    return '$project · Agent 会话';
  }

  @override
  String get desktopAttentionLinuxAction => '打开 Zeta';

  @override
  String get timelineScrollToEnd => '滚动到对话底部';

  @override
  String get relativeTimeJustNow => '刚刚';

  @override
  String relativeTimeMinutesAgo(String count) {
    return '$count 分钟前';
  }

  @override
  String relativeTimeHoursAgo(String count) {
    return '$count 小时前';
  }

  @override
  String relativeTimeDaysAgo(String count) {
    return '$count 天前';
  }

  @override
  String get contextRoleUser => '用户';

  @override
  String get contextRoleAssistant => '助手';

  @override
  String get contextRoleSystem => '系统';

  @override
  String get contextRolePlan => '计划';

  @override
  String get contextEventPermission => '审批';

  @override
  String get contextEventWarning => '警告';

  @override
  String get usageNoData => '暂无数据';

  @override
  String get usageUnknownPlan => '未知套餐';

  @override
  String get mgmtCapText => '文本';

  @override
  String get mgmtCapImage => '图片';

  @override
  String get mgmtCapCode => '代码';

  @override
  String get mgmtCapFileOps => '文件操作';

  @override
  String get mgmtCapToolCall => '工具调用';

  @override
  String get mgmtCapTerminal => '终端';

  @override
  String get mgmtCapStreaming => '流式输出';

  @override
  String get mgmtQuotaEnrichmentSubtitle => 'OAuth 凭据 · Usage REST';

  @override
  String get mgmtSetupGuideTitle => '接入指引';

  @override
  String get mgmtSetupGuideSubtitle => '安装 · 登录 · 文档';

  @override
  String get mgmtSetupInstallTitle => '1. 安装 Claude Code CLI';

  @override
  String get mgmtSetupInstallBody =>
      '在终端执行 npm install -g @anthropic-ai/claude-code，并确认 claude 已加入 PATH。';

  @override
  String get mgmtSetupLoginTitle => '2. 登录账号';

  @override
  String get mgmtSetupLoginBody =>
      '运行 claude auth login 完成 Anthropic 账号登录。自动检测不会读取凭据内容；额度详情增强只做上方说明的瞬时只读查询，且绝不写回凭据文件。';

  @override
  String get mgmtSetupDocsTitle => '3. 官方文档';

  @override
  String mgmtSetupDocsBody(String url) {
    return '完整能力与协议说明见 Anthropic Claude Code 文档：$url';
  }

  @override
  String get fontGeistBundled => 'Geist（内置默认）';

  @override
  String get fontSystemDefaultAlias => '系统默认';

  @override
  String get fontJetBrainsBundled => 'JetBrainsMono（内置默认）';

  @override
  String get agentModeLoadFailed => '无法加载对话模式，请重试。';

  @override
  String agentFastIncompatible(String effort) {
    return 'Fast 与“$effort”不兼容';
  }

  @override
  String agentFastDisableAndSwitch(String effort) {
    return '关闭 Fast 并切换到 $effort';
  }

  @override
  String agentFastSwitchAndEnable(String effort) {
    return '切换到 $effort 并开启 Fast';
  }

  @override
  String get agentModelSaveFailed => '配置保存失败，已恢复上次有效设置。';

  @override
  String agentModelUnavailableSwitched(String previous, String current) {
    return '模型“$previous”当前不可用，已切换到 $current。';
  }

  @override
  String get agentPermNextSession => '下次会话生效';

  @override
  String get agentPermCurrentTurn => '本回合生效';

  @override
  String get agentPermUnsupported => '当前 Provider 不支持权限选择';

  @override
  String get agentPermNextSend => '下次发送时生效';

  @override
  String get agentPermSavedButPersistFailed => '权限偏好已更新，但保存失败；可重试';

  @override
  String get agentPermAppliedButPersistFailed => '权限偏好已应用，但保存失败；可重试';

  @override
  String get agentPermRuntimeStale => 'Provider 运行实例已失效，请重试';

  @override
  String get agentPermSwitchFailed => '权限模式切换失败';

  @override
  String get agentProviderDefaultPermission => 'Provider 默认权限';

  @override
  String agentThreadDisabled(String name) {
    return '$name 已禁用或不可用；无法修改会话。';
  }

  @override
  String get agentNoRawPayload => '（无原始数据）';

  @override
  String get agentTurnRunning => 'Turn running';

  @override
  String get agentToolRunning => 'Tool running';

  @override
  String get agentNoPromptSummary => '（无提问摘要）';

  @override
  String agentStatusWithValue(String status) {
    return '状态：$status';
  }

  @override
  String agentTimeWithValue(String time) {
    return '时间：$time';
  }

  @override
  String get agentLoadingHistory => 'Loading thread history';

  @override
  String get agentNoSkills => 'No skills found';

  @override
  String get agentNoMatches => 'No matches';

  @override
  String agentCountTimes(String count, String kind) {
    return '$count 次$kind';
  }

  @override
  String agentElapsedTotal(String duration) {
    return '共 $duration';
  }

  @override
  String get agentCurrentlyViewing => '，当前查看';

  @override
  String agentLineCount(String count) {
    return '$count 行';
  }

  @override
  String agentAddedRemovedLines(String added, String removed) {
    return '新增 $added 行，删除 $removed 行';
  }

  @override
  String get agentNoContentEvidence => 'Provider 未提供内容证据';

  @override
  String get agentBeforePlan => 'Plan 前';

  @override
  String get agentAsk => 'Agent 提问';

  @override
  String get agentReadOnlyCustomMode => '当前为只读的自定义模式，可选择内置模式覆盖。';

  @override
  String get agentModeLoadingSemantic => 'Mode…，对话模式，正在加载';

  @override
  String agentModeErrorSemantic(String detail) {
    return 'Mode unavailable，对话模式，$detail';
  }

  @override
  String agentNextTurnShort(String label) {
    return '$label · 下一回合';
  }

  @override
  String get agentModeReadOnlySuffix => '，当前模式只读';

  @override
  String get agentNextTurnSuffix => '，下一回合生效';

  @override
  String get agentModeProviderSet => '当前模式由 Provider 设置；可选择内置模式覆盖';

  @override
  String agentNextTurnAppliesTooltip(String label) {
    return '$label\n将在下一回合生效';
  }

  @override
  String agentConversationModeSemantic(String label, String suffix) {
    return '$label，对话模式$suffix';
  }

  @override
  String agentModeOptionSemantic(String label, String state) {
    return '$label，$state';
  }

  @override
  String agentReasoningEffortValue(String value) {
    return '思考程度：$value';
  }

  @override
  String agentFastValue(String value) {
    return 'Fast：$value';
  }

  @override
  String agentModelConfigSemantic(String label) {
    return '$label，模型配置';
  }

  @override
  String agentModelConfigErrorSemantic(String label, String error) {
    return '$label，$error';
  }

  @override
  String get agentPlanModeClearNextTurn => 'Plan，对话模式，下一回合生效，点击清除';

  @override
  String get agentPlanModeClear => 'Plan，对话模式，点击清除';

  @override
  String get agentPlanNextTurnTooltip => 'Plan\n将在下一回合生效';

  @override
  String get agentLoadingModesStatus => '正在加载对话模式…';

  @override
  String get agentModeNotSelectableNow => '当前模式暂不支持主动选择';

  @override
  String get agentModelCatalogRefreshFailed => '模型目录刷新失败，正在使用本地缓存。';

  @override
  String get agentModelListRefreshFailed => '模型列表刷新失败，已保留现有配置。';

  @override
  String get agentCannotSwitchPermissionDuringTurn => '当前回合执行中，请等待结束后再切换权限模式。';

  @override
  String agentProviderReady(String name) {
    return '$name ready';
  }

  @override
  String get agentCouldNotLoadProviders => 'Could not load Agent providers';

  @override
  String get agentIsWorking => 'Agent is working';

  @override
  String get agentCreatingBranch => 'Creating branch';

  @override
  String get agentCouldNotUpdateSessionOption =>
      'Could not update session option';

  @override
  String get agentProviderOperationFailed => 'Agent provider operation failed';

  @override
  String get agentCursorUnavailable => 'Cursor Agent unavailable';

  @override
  String agentEvidenceReplaceSemantics(String before, String after) {
    return '替换片段，替换前 $before 行，替换后 $after 行';
  }

  @override
  String agentWrittenContentSemantics(String status, String count) {
    return '写入内容，$status，共 $count 行';
  }

  @override
  String agentUnifiedDiffSemantics(String count) {
    return '统一差异，共 $count 行';
  }

  @override
  String agentScrollableLines(String title, String count) {
    return '$title，可滚动，$count 行';
  }

  @override
  String get agentKeyboardScrollHint => '使用方向键、Page Up、Page Down、Home 或 End 滚动';

  @override
  String agentLineAt(String kind, String n, String text) {
    return '$kind，第 $n 行：$text';
  }

  @override
  String agentQuestionProgress(String current, String total) {
    return '$current of $total';
  }

  @override
  String get agentRemoveImage => 'Remove image';

  @override
  String agentPermissionModeHint(String hint) {
    return 'Permission mode · $hint';
  }

  @override
  String agentPermissionModeSemantic(String label, String hint) {
    return '$label，权限模式，$hint';
  }

  @override
  String agentPermissionModeOnly(String label) {
    return '$label，权限模式';
  }

  @override
  String agentFastSemantic(String model, String state) {
    return '$model，Fast，$state';
  }

  @override
  String get agentModelUnavailableNow => '该模型当前不可用';

  @override
  String get agentOptionSelectedSuffix => '，已选择';

  @override
  String agentLabeledValue(String label, String value) {
    return '$label：$value';
  }

  @override
  String agentStartingProvider(String name) {
    return 'Starting $name';
  }

  @override
  String agentPreparingProvider(String name) {
    return 'Preparing $name';
  }

  @override
  String agentCouldNotStart(String name) {
    return 'Could not start $name';
  }

  @override
  String agentProtocolWarning(String name) {
    return '$name protocol warning';
  }

  @override
  String agentRequestTimedOut(String name) {
    return '$name request timed out. Please try again.';
  }

  @override
  String agentConnectionClosedRetry(String name) {
    return '$name connection closed. Reconnect and try again.';
  }

  @override
  String agentAppServerConnectionClosed(String name) {
    return '$name App Server 连接已关闭';
  }

  @override
  String agentProcessExited(String name) {
    return '$name process exited';
  }

  @override
  String get agentFailedToSendPrompt => 'Failed to send prompt';

  @override
  String agentWaitingApprovalFor(String title) {
    return 'Waiting for approval: $title';
  }

  @override
  String agentWaitingAnswersFor(String title) {
    return 'Waiting for answers: $title';
  }

  @override
  String get agentWaitingPlanApproval => 'Waiting for plan approval';

  @override
  String get agentPlanApprovalTitle => 'Plan approval';

  @override
  String agentSessionIdentityChanged(String name) {
    return '$name changed session identity unexpectedly';
  }

  @override
  String agentCouldNotRestoreSession(String name) {
    return '$name could not restore the requested session';
  }

  @override
  String agentPermissionRequestDescription(String name, String tool) {
    return '$name requests permission to use $tool';
  }

  @override
  String get agentApplyPatch => 'Apply patch';

  @override
  String get agentHistoryToolSearch => 'Tool search';

  @override
  String get agentHistoryWebSearch => 'Web search';

  @override
  String get agentRequestsInput => 'Agent requests input';

  @override
  String get agentDefaultThreadTitle => '新建会话';

  @override
  String agentUsageWindowWeeks(String count) {
    return '$count 周';
  }

  @override
  String agentUsageWindowDays(String count) {
    return '$count 天';
  }

  @override
  String agentUsageWindowHours(String count) {
    return '$count 小时';
  }

  @override
  String agentUsageWindowHoursMinutes(String hours, String minutes) {
    return '$hours 小时 $minutes 分钟';
  }

  @override
  String agentUsageWindowMinutes(String count) {
    return '$count 分钟';
  }

  @override
  String get agentUsageWindowOneWeek => '1 周';

  @override
  String get agentUsageWindowOneDay => '1 天';

  @override
  String get agentQuotaFiveHours => '5h';

  @override
  String get agentQuotaOneWeek => '1 周';

  @override
  String get agentQuotaSonnetOneWeek => 'Sonnet 1 周';

  @override
  String get agentQuotaOpusOneWeek => 'Opus 1 周';

  @override
  String get agentClaudeCodeSubscriptionQuota => 'Claude Code 订阅额度';

  @override
  String get agentCursorRetired => 'Cursor Agent 已退役，当前版本不再支持启动或恢复 Cursor 会话。';

  @override
  String agentCursorNoEnabledProvider(String message) {
    return '$message 当前没有已启用的可用 Provider；旧 Cursor 配置保持原样。';
  }

  @override
  String agentCursorFallbackTo(String message, String name) {
    return '$message 已临时回退到 $name；旧 Cursor 配置保持原样。';
  }

  @override
  String agentCursorConfigPreserved(String message) {
    return '$message 旧 Cursor 配置和会话数据保持原样。';
  }

  @override
  String get agentCouldNotLoadThreads => 'Could not load threads';

  @override
  String get agentNoEnabledProviders => 'No enabled Agent providers';

  @override
  String get mgmtClaudeInitializeSuccess =>
      'Claude Code initialize 成功，CLI 与当前认证路径可用。';

  @override
  String get mgmtClaudeInitializeTimeout =>
      'Claude Code initialize 在 20 秒内未完成。';

  @override
  String get mgmtClaudeInitializeFailed => 'Claude Code initialize 探测失败。';

  @override
  String mgmtVersionDetectFailed(String name) {
    return '$name 版本检测失败。';
  }

  @override
  String get mgmtClaudeLoginEvidenceUnavailable => 'Claude Code 登录证据不可用';

  @override
  String get mgmtClaudeInitializeProcessExited =>
      'Claude Code 进程在 initialize 完成前退出。';

  @override
  String get mgmtClaudeInitializeRejected => 'Claude Code 拒绝了 initialize 请求。';

  @override
  String get mgmtClaudeInitializeInvalidResponse =>
      'Claude Code 返回的 initialize 响应无效。';

  @override
  String get mgmtClaudeInitializeInvalidStream =>
      'Claude Code 返回了无效的 stream-json 数据。';

  @override
  String get mgmtClaudeInitializeCommunicationFailed =>
      'Claude Code initialize 通信失败。';

  @override
  String get mgmtClaudeAiLoggedIn => 'Claude.ai 已登录';

  @override
  String mgmtClaudeAiLoggedInAs(String plan) {
    return 'Claude.ai 已登录 · $plan';
  }

  @override
  String mgmtNotLoggedIn(String name) {
    return '$name 尚未登录。';
  }

  @override
  String get mgmtGrokLoginCacheEmpty => 'Grok 登录缓存为空。';

  @override
  String get mgmtGrokAcpOk => 'Grok ACP 连接正常';

  @override
  String get mgmtGrokAcpFailed => 'Grok ACP 连接失败。';

  @override
  String get mgmtGrokLatestVersionNetworkHint =>
      '请检查网络后重新检测，或在终端运行 grok update --check。';

  @override
  String get mgmtCodexAppServerFailed => 'Codex app-server 连接失败。';

  @override
  String mgmtDetectionIncomplete(String error) {
    return 'Agent 检测未能完成：$error';
  }

  @override
  String mgmtDetectionProgress(
    String index,
    String total,
    String name,
    String message,
  ) {
    return '[$index/$total] $name: $message';
  }

  @override
  String usageSessionDirIncomplete(String name) {
    return '$name 会话目录未能完整枚举，已展示可读取的数据。';
  }

  @override
  String usageSessionFilesUnreadable(String count, String name) {
    return '$count 个 $name 会话文件读取失败，已展示其余数据。';
  }

  @override
  String usageHistoryRowsCorrupt(String count, String name) {
    return '$count 行 $name 历史损坏，已跳过并继续统计。';
  }
}

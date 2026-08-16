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
  String get usageRetry => '重试';

  @override
  String get usagePrevWindow => '上一窗口';

  @override
  String get usageNextWindow => '下一窗口';
}

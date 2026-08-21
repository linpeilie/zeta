// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zeta';

  @override
  String localizationContractGreeting(String name) {
    return 'Hello $name';
  }

  @override
  String get shadcnFormNotEmpty => 'This field cannot be empty';

  @override
  String get shadcnInvalidValue => 'Invalid value';

  @override
  String get shadcnInvalidEmail => 'Invalid email';

  @override
  String get shadcnInvalidURL => 'Invalid URL';

  @override
  String shadcnFormLessThan(String value) {
    return 'Must be less than $value';
  }

  @override
  String shadcnFormGreaterThan(String value) {
    return 'Must be greater than $value';
  }

  @override
  String shadcnFormLessThanOrEqualTo(String value) {
    return 'Must be less than or equal to $value';
  }

  @override
  String shadcnFormGreaterThanOrEqualTo(String value) {
    return 'Must be greater than or equal to $value';
  }

  @override
  String get shadcnFormPhoneNumberInvalid => 'Phone number is invalid';

  @override
  String get shadcnFormPhoneNumberEmpty => 'Phone number is required';

  @override
  String shadcnFormBetweenInclusively(String min, String max) {
    return 'Must be between $min and $max (inclusive)';
  }

  @override
  String shadcnFormBetweenExclusively(String min, String max) {
    return 'Must be between $min and $max (exclusive)';
  }

  @override
  String shadcnFormLengthLessThan(String value) {
    return 'Must be at least $value characters';
  }

  @override
  String shadcnFormLengthGreaterThan(String value) {
    return 'Must be at most $value characters';
  }

  @override
  String get shadcnFormPasswordDigits => 'Must contain at least one digit';

  @override
  String get shadcnFormPasswordLowercase =>
      'Must contain at least one lowercase letter';

  @override
  String get shadcnFormPasswordUppercase =>
      'Must contain at least one uppercase letter';

  @override
  String get shadcnFormPasswordSpecial =>
      'Must contain at least one special character';

  @override
  String get shadcnCommandSearch => 'Type a command or search...';

  @override
  String get shadcnCommandEmpty => 'No results found.';

  @override
  String get shadcnCommandMoveUp => 'Move Up';

  @override
  String get shadcnCommandMoveDown => 'Move Down';

  @override
  String get shadcnCommandActivate => 'Select';

  @override
  String get shadcnDatePickerSelectYear => 'Select a year';

  @override
  String get shadcnPlaceholderDatePicker => 'Select a date';

  @override
  String get shadcnPlaceholderTimePicker => 'Select a time';

  @override
  String get shadcnPlaceholderColorPicker => 'Select a color';

  @override
  String get shadcnPlaceholderDurationPicker => 'Select a duration';

  @override
  String get shadcnButtonCancel => 'Cancel';

  @override
  String get shadcnButtonSave => 'Save';

  @override
  String get shadcnButtonPrevious => 'Previous';

  @override
  String get shadcnButtonNext => 'Next';

  @override
  String get shadcnTimeHour => 'Hour';

  @override
  String get shadcnTimeMinute => 'Minute';

  @override
  String get shadcnTimeSecond => 'Second';

  @override
  String get shadcnTimeAM => 'AM';

  @override
  String get shadcnTimePM => 'PM';

  @override
  String get shadcnColorRed => 'Red';

  @override
  String get shadcnColorGreen => 'Green';

  @override
  String get shadcnColorBlue => 'Blue';

  @override
  String get shadcnColorAlpha => 'Alpha';

  @override
  String get shadcnColorHue => 'Hue';

  @override
  String get shadcnColorSaturation => 'Sat';

  @override
  String get shadcnColorValue => 'Val';

  @override
  String get shadcnColorLightness => 'Lum';

  @override
  String get shadcnMenuCut => 'Cut';

  @override
  String get shadcnMenuCopy => 'Copy';

  @override
  String get shadcnMenuPaste => 'Paste';

  @override
  String get shadcnMenuSelectAll => 'Select All';

  @override
  String get shadcnMenuUndo => 'Undo';

  @override
  String get shadcnMenuRedo => 'Redo';

  @override
  String get shadcnMenuDelete => 'Delete';

  @override
  String get shadcnMenuShare => 'Share';

  @override
  String get shadcnMenuSearchWeb => 'Search Web';

  @override
  String get shadcnMenuLiveTextInput => 'Live Text Input';

  @override
  String get shadcnRefreshTriggerPull => 'Pull to refresh';

  @override
  String get shadcnRefreshTriggerRelease => 'Release to refresh';

  @override
  String get shadcnRefreshTriggerRefreshing => 'Refreshing...';

  @override
  String get shadcnRefreshTriggerComplete => 'Refresh complete';

  @override
  String get shadcnColorPickerTabRecent => 'Recent';

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
    return '$count of $total row(s) selected.';
  }

  @override
  String get shadcnDataTableNext => 'Next';

  @override
  String get shadcnDataTablePrevious => 'Previous';

  @override
  String get shadcnDataTableColumns => 'Columns';

  @override
  String get shadcnTimeDaysAbbreviation => 'DD';

  @override
  String get shadcnTimeHoursAbbreviation => 'HH';

  @override
  String get shadcnTimeMinutesAbbreviation => 'MM';

  @override
  String get shadcnTimeSecondsAbbreviation => 'SS';

  @override
  String get shadcnDurationDay => 'Day';

  @override
  String get shadcnDurationHour => 'Hour';

  @override
  String get shadcnDurationMinute => 'Minute';

  @override
  String get shadcnDurationSecond => 'Second';

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
  String get settingsNavGeneral => 'General';

  @override
  String get settingsNavAppearance => 'Appearance';

  @override
  String get settingsNavAgents => 'Agent management';

  @override
  String get settingsAgentsUnavailable => 'Agent management is unavailable.';

  @override
  String get settingsSendShortcutCmdEnter => 'Cmd + Enter to send';

  @override
  String get settingsSendShortcutCtrlEnter => 'Ctrl + Enter to send';

  @override
  String get settingsSendShortcutEnterHint =>
      'Press Enter to send, Shift + Enter for a new line.';

  @override
  String get settingsSendShortcutCmdHint =>
      'Press Cmd + Enter to send, Enter for a new line.';

  @override
  String get settingsSendShortcutCtrlHint =>
      'Press Ctrl + Enter to send, Enter for a new line.';

  @override
  String get settingsLanguage => 'Language';

  @override
  String get settingsLanguageHint =>
      'The interface language changes after you restart the app.';

  @override
  String get settingsLanguageEnglish => 'English';

  @override
  String get settingsLanguageSimplifiedChinese => '简体中文';

  @override
  String get settingsLanguageRestartToApply => 'Takes effect after restart';

  @override
  String get settingsLanguageSaveFailed =>
      'Could not save the language setting. The current selection was kept.';

  @override
  String get settingsMessageSending => 'Sending messages';

  @override
  String get settingsSendShortcut => 'Send shortcut';

  @override
  String get settingsSendShortcutEnter => 'Enter to send';

  @override
  String get settingsNotifications => 'Notifications';

  @override
  String get settingsSystemNotifications => 'System notifications';

  @override
  String get settingsSystemNotificationsHint =>
      'Send system alerts when a task moves to the background or another session.';

  @override
  String get settingsTurnTerminalNotifications => 'Task finished';

  @override
  String get settingsTurnTerminalNotificationsHint =>
      'Notify when a task completes, fails, or is interrupted.';

  @override
  String get settingsActionRequiredNotifications => 'Needs confirmation';

  @override
  String get settingsActionRequiredNotificationsHint =>
      'Notify when permission, a question, plan approval, or execution confirmation is waiting.';

  @override
  String get settingsThemeFollowSystem => 'System';

  @override
  String get settingsThemeFollowSystemHint =>
      'Use the current system light or dark preference.';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeLightHint =>
      'Light background, low-contrast borders, and a blue accent.';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeDarkHint =>
      'Dark background, high-contrast panes, and a bright accent.';

  @override
  String get settingsTheme => 'Theme';

  @override
  String get settingsFonts => 'Fonts';

  @override
  String get settingsUiFont => 'UI font';

  @override
  String get settingsUiFontHint =>
      'Used for regular UI text and non-code Markdown body.';

  @override
  String get settingsUiFontLoadError => 'Could not load the selected UI font.';

  @override
  String get settingsUiFontSize => 'UI font size';

  @override
  String settingsUiFontSizeHint(String min, String max) {
    return 'Scale regular UI text ($min–$max px).';
  }

  @override
  String get settingsCodeFont => 'Code font';

  @override
  String get settingsCodeFontHint =>
      'Used for code blocks, commands, diffs, and tool output.';

  @override
  String get settingsCodeFontLoadError =>
      'Could not load the selected code font.';

  @override
  String get settingsCodeFontSize => 'Code font size';

  @override
  String settingsCodeFontSizeHint(String min, String max) {
    return 'Scale code content ($min–$max px).';
  }

  @override
  String get settingsThemeMode => 'Theme mode';

  @override
  String settingsLabeledValue(String label, String value) {
    return '$label: $value';
  }

  @override
  String settingsSearchSomething(String label) {
    return 'Search $label';
  }

  @override
  String get settingsNoMatchingFonts => 'No matching fonts.';

  @override
  String get settingsFontListLoadFailed => 'Could not load the font list.';

  @override
  String settingsFontSizeSemantics(String label, String size) {
    return '$label, currently $size pixels';
  }

  @override
  String settingsDecreaseSomething(String label) {
    return 'Decrease $label';
  }

  @override
  String settingsPixelValue(String size) {
    return '$size px';
  }

  @override
  String settingsIncreaseSomething(String label) {
    return 'Increase $label';
  }

  @override
  String get settingsFontGeistDefault => 'Geist (built-in default)';

  @override
  String get settingsFontJetBrainsDefault => 'JetBrainsMono (built-in default)';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonConfirm => 'Confirm';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonMore => 'More';

  @override
  String get commonRemove => 'Remove';

  @override
  String get commonMenu => 'Menu';

  @override
  String get workbenchHideLeftSidebar => 'Hide left sidebar';

  @override
  String get workbenchShowLeftSidebar => 'Show left sidebar';

  @override
  String get workbenchBackToHome => 'Back to home';

  @override
  String get workbenchUsageStatistics => 'Usage statistics';

  @override
  String get workbenchOpenUsageStatistics => 'Open usage statistics page';

  @override
  String get workbenchOpenSettings => 'Open settings page';

  @override
  String get workbenchHideRightSidebar => 'Hide right sidebar';

  @override
  String get workbenchShowRightSidebar => 'Show right sidebar';

  @override
  String get workbenchRightSidebarHomeOnly =>
      'The right sidebar is only available on the home screen';

  @override
  String get workbenchMenuFile => 'File';

  @override
  String get workbenchMenuOpenProject => 'Open Project';

  @override
  String get workbenchMenuQuit => 'Quit';

  @override
  String get workbenchResizeLeftPanel => 'Resize left panel width';

  @override
  String get workbenchResizeRightPanel => 'Resize right panel width';

  @override
  String get workbenchCannotOpenNotificationThread =>
      'Could not open the session from the notification. It may have been deleted or is not in the current project list.';

  @override
  String workbenchProviderDetectionFailed(String error) {
    return 'Could not detect Provider: $error';
  }

  @override
  String get workbenchCloseOverlay => 'Close workbench overlay';

  @override
  String get workbenchLogoSemantics => 'Zeta Logo';

  @override
  String get timelineScrollbar => 'Conversation scrollbar';

  @override
  String get timelineScrollToBottom => 'Scroll to end of conversation';

  @override
  String get timelineNewContent => 'New content';

  @override
  String get timelineBackToBottom => 'Back to bottom';

  @override
  String get imagePreviewUnavailable => 'Image file unavailable';

  @override
  String get imagePreviewViewLarge => 'View larger image';

  @override
  String get imagePreviewView => 'View image';

  @override
  String tabsLoadingSuffix(String label) {
    return '$label, loading';
  }

  @override
  String get homeWelcomeTitle => 'Welcome to Zeta';

  @override
  String get homeWelcomeSubtitle =>
      'Open a local project to start working with an Agent.';

  @override
  String get homeOpenProjectFolder => 'Open project folder';

  @override
  String get homeOpenProject => 'Open project';

  @override
  String get homeRecentSessions => 'Recent sessions';

  @override
  String get homeLoadingRecentSessions => 'Loading recent sessions…';

  @override
  String get homeInstalledProviders => 'Installed providers';

  @override
  String get homeDetectionFailed => 'Detection failed';

  @override
  String get homeProviderDetectionFailedTitle => 'Provider detection failed';

  @override
  String get homeDetectingProviders => 'Detecting providers…';

  @override
  String get homeNoInstalledProviders => 'No installed providers detected';

  @override
  String get homeProvidersAfterDetect =>
      'Available Agent environments appear here after detection.';

  @override
  String get homeProvidersAfterInstall =>
      'After you install and configure a supported Agent, it appears here.';

  @override
  String homeCommaJoin(String left, String right) {
    return '$left, $right';
  }

  @override
  String get homeProviderAvailable => 'Available';

  @override
  String get homeProviderRunning => 'Running';

  @override
  String get homeProviderDisabled => 'Disabled';

  @override
  String get homeProviderNeedsLogin => 'Sign-in required';

  @override
  String get homeProviderError => 'Error';

  @override
  String get homeProviderDetecting => 'Detecting';

  @override
  String get projectNewSession => 'New session';

  @override
  String projectNewSessionFor(String name) {
    return 'New session for $name';
  }

  @override
  String get projectNoRecentSessions => 'No recent sessions';

  @override
  String get projectCreateThreadHint =>
      'After you create a Thread, it appears here.';

  @override
  String get projectCannotLoadSessions => 'Could not load recent sessions';

  @override
  String get projectPleaseRetryLater => 'Please try again later.';

  @override
  String get projectRetryLoadSessions => 'Retry loading recent sessions';

  @override
  String projectOpenSession(String title) {
    return 'Open session $title';
  }

  @override
  String get threadWaitingApproval => 'Waiting for approval';

  @override
  String get threadWaitingInput => 'Waiting for input';

  @override
  String get threadRunning => 'Running';

  @override
  String get threadSystemError => 'System error';

  @override
  String get projectOpenFolder => 'Open folder';

  @override
  String get projectRefreshSessions => 'Refresh sessions';

  @override
  String get projectHasRunningThreads => 'Project has running threads';

  @override
  String get threadRename => 'Rename';

  @override
  String get threadUnarchive => 'Unarchive';

  @override
  String get threadArchive => 'Archive';

  @override
  String get threadFork => 'Fork';

  @override
  String get threadDelete => 'Delete';

  @override
  String get threadRemoveFromZetaOnly => 'Remove from Zeta list only';

  @override
  String get threadRemoveFromList => 'Remove session from list';

  @override
  String get threadDeleteSession => 'Delete session';

  @override
  String get threadDeleteIrreversible =>
      'This cannot be undone and permanently deletes the session.';

  @override
  String get threadRemoveIndexOnlyHint =>
      'This only removes Zeta\'s local index. Provider history files remain.';

  @override
  String get threadDeleteInAgentHint =>
      'To delete it completely, use the corresponding Agent tool.';

  @override
  String get threadRunningStatus => 'Thread running';

  @override
  String get threadCompletedClickToDismiss => 'Finished, click to dismiss';

  @override
  String get threadCouldNotLoadThreads => 'Could not load threads';

  @override
  String get projectOpenInFinder => 'Open in Finder';

  @override
  String get projectOpenInExplorer => 'Open in Explorer';

  @override
  String get projectOpenInFileManager => 'Open in file manager';

  @override
  String get newThreadSelectProvider => 'Select Agent Provider';

  @override
  String get newThreadLoadingAgents => 'Loading Agent…';

  @override
  String newThreadCannotLoadAgents(String error) {
    return 'Could not load Agent: $error';
  }

  @override
  String get newThreadNoEnabledProviders =>
      'No enabled supported Agent provider. Enable one in Settings > Agents first.';

  @override
  String get newThreadChooseAgent =>
      'Choose the Agent used to create the new session.';

  @override
  String newThreadUseProvider(String name) {
    return 'Create thread with $name';
  }

  @override
  String get usageTimeRangeToday => 'Today';

  @override
  String get usageTimeRangeLast7Days => 'Last 7 days';

  @override
  String get usageTimeRangeLast30Days => 'Last 30 days';

  @override
  String get usageTimeRangeLast90Days => 'Last 90 days';

  @override
  String get usageTimeRangeThisMonth => 'This month';

  @override
  String get usageTimeRangePreviousMonth => 'Last month';

  @override
  String get usageTimeRangeCustom => 'Custom range';

  @override
  String get usageTaskStatusRunning => 'Running';

  @override
  String get usageTaskStatusCompleted => 'Succeeded';

  @override
  String get usageTaskStatusInterrupted => 'Cancelled';

  @override
  String get usageTaskStatusFailed => 'Failed';

  @override
  String get usageTaskStatusUnknown => 'Unknown';

  @override
  String get usageErrorCategoryAccount => 'Account issue';

  @override
  String get usageErrorCategoryCli => 'Runtime issue';

  @override
  String get usageErrorCategoryNetwork => 'Network error';

  @override
  String get usageErrorCategoryTimeout => 'Timed out';

  @override
  String get usageErrorCategoryCancelled => 'Cancelled by user';

  @override
  String get usageErrorCategoryOther => 'Other error';

  @override
  String get usageErrorNextActionAccount =>
      'Check the Codex sign-in status and current plan quota.';

  @override
  String get usageErrorNextActionCli =>
      'Check the Codex version, configuration, and runtime logs.';

  @override
  String get usageErrorNextActionNetwork =>
      'Check the network and proxy settings, then retry.';

  @override
  String get usageErrorNextActionTimeout => 'Narrow the task scope and retry.';

  @override
  String get usageErrorNextActionCancelled =>
      'Start the task again if you still need it.';

  @override
  String get usageErrorNextActionOther =>
      'Open the task details or Agent logs for the original reason.';

  @override
  String get usageTrendMetricCalls => 'Calls';

  @override
  String get usageTrendMetricSuccessRate => 'Success rate';

  @override
  String get usageTrendMetricTotalTokens => 'Token usage';

  @override
  String get usageTrendMetricAverageResponse => 'Average response time';

  @override
  String get usageTrendMetricAverageDuration => 'Task duration';

  @override
  String get usageRankSortCalls => 'Calls';

  @override
  String get usageRankSortTotalTokens => 'Token usage';

  @override
  String get usageRankSortFailures => 'Failures';

  @override
  String get usageRankSortAverageDuration => 'Task duration';

  @override
  String get usageUnknownProject => 'Unknown project';

  @override
  String usageLoadFailed(String error) {
    return 'Unable to load usage statistics: $error';
  }

  @override
  String get usageQuotaUnreadable => 'Plan quota is temporarily unavailable';

  @override
  String get usageAgentTemporarilyUnavailable =>
      'This Agent is temporarily unavailable';

  @override
  String get usageTokenHistoryUnavailable =>
      'Token history is temporarily unavailable';

  @override
  String get usageTokenSourceMismatch =>
      'Token history source configuration does not match';

  @override
  String get usageNoTokenHistory => 'No Token history';

  @override
  String get usageTodayTokensUnreadable =>
      'Today\'s Token usage is temporarily unavailable';

  @override
  String get usageIndexWriteFailed =>
      'The statistics index could not be saved. This result is still available.';

  @override
  String usageIndexReadRescanned(String providerName) {
    return '$providerName statistics index is temporarily unreadable. Local history was rescanned.';
  }

  @override
  String get usageAgentDisabledOrUnavailable =>
      'This Agent is disabled or unavailable';

  @override
  String get usageAgentUsageTemporarilyUnavailable =>
      'Agent usage is temporarily unavailable';

  @override
  String get usagePageTitle => 'Usage statistics';

  @override
  String get usagePageSubtitle =>
      'Analyze calls, performance, tokens, projects, and plan quota';

  @override
  String get usageLoadFailedTitle => 'Failed to load statistics';

  @override
  String get usagePartialUnavailable => 'Some data is unavailable';

  @override
  String get usageReload => 'Reload';

  @override
  String get usageTimeRangeLabel => 'Time range';

  @override
  String get usageAllAgents => 'All Agents';

  @override
  String get usageModelLabel => 'Model';

  @override
  String get usageAllModels => 'All models';

  @override
  String usageLastUpdated(String time) {
    return 'Last updated: $time';
  }

  @override
  String get usageRefresh => 'Refresh';

  @override
  String usageTokenBreakdownLine(
    String input,
    String output,
    String reasoning,
  ) {
    return 'Input $input · Output $output · Reasoning $reasoning';
  }

  @override
  String get usageNoTokenStats => 'No Token statistics for the current filters';

  @override
  String get usageTokenUsageLabel => 'Token usage';

  @override
  String usageTokenUsageAmount(String amount) {
    return 'Token usage $amount';
  }

  @override
  String get usageCallCount => 'Calls';

  @override
  String usageCallCountSemantic(String count) {
    return 'Calls $count';
  }

  @override
  String get usageTrendTitle => 'Usage trend';

  @override
  String get usageTrendSubtitle =>
      'Token usage · granularity follows the selected range';

  @override
  String usageTrendSemantic(String metric, String count) {
    return '$metric trend, $count time points';
  }

  @override
  String get usageDetailTabsSemantic => 'Usage statistics detail categories';

  @override
  String get usageAgentStats => 'Agent statistics';

  @override
  String get usageModelStats => 'Model statistics';

  @override
  String get usageProjectList => 'Project list';

  @override
  String get usageTaskList => 'Task list';

  @override
  String get usageRankSummary => 'Summarized for the current filters';

  @override
  String get usageUnsupported => 'Unsupported';

  @override
  String get usageHeaderCalls => 'Calls';

  @override
  String get usageHeaderSuccessRate => 'Success rate';

  @override
  String get usageHeaderToken => 'Token';

  @override
  String get usageHeaderFailures => 'Failures';

  @override
  String get usageHeaderAverageDuration => 'Avg. duration';

  @override
  String get usageModelTokenShare => 'Model Token usage and share';

  @override
  String get usageNoModelStats => 'No model statistics for the current filters';

  @override
  String get usageTokenTotal => 'Total';

  @override
  String get usageTokenInput => 'Input';

  @override
  String get usageTokenCachedInput => 'Cached input';

  @override
  String get usageTokenOutput => 'Output';

  @override
  String get usageTokenReasoning => 'Reasoning';

  @override
  String get usageHeaderModel => 'Model';

  @override
  String get usageHeaderShare => 'Share';

  @override
  String get usageProjectSummary =>
      'Summarized for the current filters · click a project to focus it';

  @override
  String get usageHeaderProject => 'Project';

  @override
  String get usageHeaderLastUsed => 'Last used';

  @override
  String usageTaskListSummary(String count, String pageSize) {
    return '$count items · $pageSize per page · metadata only';
  }

  @override
  String get usageHeaderTime => 'Time';

  @override
  String get usageHeaderDuration => 'Duration';

  @override
  String get usageHeaderStatus => 'Status';

  @override
  String get usageUnknownModel => 'Unknown model';

  @override
  String usageOpenDetail(String name) {
    return 'Open $name details';
  }

  @override
  String get usageTaskDetail => 'Task details';

  @override
  String get usageFieldProject => 'Project';

  @override
  String get usageFieldProjectPath => 'Project path';

  @override
  String get usageFieldSource => 'Source';

  @override
  String get usageFieldStartTime => 'Start time';

  @override
  String get usageFieldDuration => 'Duration';

  @override
  String get usageFieldFirstResponse => 'First response';

  @override
  String get usageTokenNotSupported =>
      'This record does not support Token statistics';

  @override
  String usageTokenFullDetail(
    String total,
    String input,
    String cached,
    String output,
    String reasoning,
  ) {
    return '$total (Input $input / Cached $cached / Output $output / Reasoning $reasoning)';
  }

  @override
  String usageTokenDetail(String cached, String output, String reasoning) {
    return 'Cached $cached / Output $output / Reasoning $reasoning)';
  }

  @override
  String get usageFieldStatus => 'Status';

  @override
  String get usageFieldErrorCategory => 'Error category';

  @override
  String get usageFieldReason => 'Reason';

  @override
  String get usageNoReason => 'No detailed reason provided';

  @override
  String get usageFieldNextStep => 'Next step';

  @override
  String get usageSourceKindCli => 'Local record';

  @override
  String get usageEmptyTitle => 'No usage records yet';

  @override
  String get usageEmptyBody =>
      'After you start using an Agent, call counts, performance, and resource usage appear here.';

  @override
  String get usageOpenAgentManagement => 'Open Agent management';

  @override
  String get usageLoading => 'Loading usage statistics';

  @override
  String get usageQuickShortcuts => 'Shortcuts';

  @override
  String get usageRefreshUsage => 'Refresh usage';

  @override
  String get usageNoEnabledAgent => 'No enabled Agent';

  @override
  String get usageNoStats => 'No statistics';

  @override
  String get usageCollapseAgentStats => 'Collapse Agent statistics';

  @override
  String get usageExpandAgentStats => 'Expand Agent statistics';

  @override
  String get usageTodayToken => 'Today\'s Token';

  @override
  String get usageReadingAgentUsage => 'Reading Agent usage';

  @override
  String get usageRetryReadAgentUsage => 'Retry reading Agent usage';

  @override
  String get usageSelectAgentUsage => 'Select Agent usage';

  @override
  String get usageAvailableResetCards => 'Available reset cards';

  @override
  String usageResetCardCount(String count) {
    return '$count cards';
  }

  @override
  String get usageAgentStatsSummary => 'Agent statistics summary';

  @override
  String get usagePlanBusinessUsageBased => 'ChatGPT Business (usage-based)';

  @override
  String get usagePlanEnterpriseUsageBased =>
      'ChatGPT Enterprise (usage-based)';

  @override
  String get usageRetry => 'Retry';

  @override
  String get usagePrevWindow => 'Previous window';

  @override
  String get usageNextWindow => 'Next window';

  @override
  String mgmtLocating(String name) {
    return 'Locating $name';
  }

  @override
  String get mgmtLocatingClaudeCodeCli => 'Checking Claude Code CLI';

  @override
  String mgmtNotFound(String name) {
    return '$name was not found';
  }

  @override
  String get mgmtNotFoundClaudeCodeCli => 'Claude Code CLI was not found';

  @override
  String mgmtInstallAndAddToPath(String name) {
    return 'Install $name first and make sure the executable is on PATH.';
  }

  @override
  String get mgmtInstallClaudeCodeAndAddToPath =>
      'Install Claude Code first and make sure claude is on PATH.';

  @override
  String mgmtFound(String name) {
    return 'Found $name';
  }

  @override
  String get mgmtConfirmExecutableThenRedetect =>
      'Confirm the detected executable can run, then detect again.';

  @override
  String get mgmtConfirmClaudeVersionCommand =>
      'Confirm Claude Code CLI can run `claude --version`.';

  @override
  String get mgmtVersionDetected => 'Current version detected';

  @override
  String get mgmtClaudeVersionDetected => 'Claude Code version detected';

  @override
  String get mgmtAccountDetected => 'Account status detected';

  @override
  String get mgmtClaudeAuthDetected => 'Claude Code sign-in status detected';

  @override
  String get mgmtConfigStatusRead => 'Configuration file status read';

  @override
  String mgmtLogsLocated(String name) {
    return '$name logs located';
  }

  @override
  String get mgmtLatestVersionChecked => 'Latest version checked';

  @override
  String get mgmtHandshakeComplete => 'Protocol handshake completed';

  @override
  String mgmtDetectionComplete(String name) {
    return '$name detection finished';
  }

  @override
  String mgmtRetestAfterCheckingConfig(String name) {
    return 'Check $name configuration and account status, then test the connection again.';
  }

  @override
  String get mgmtRetestAfterCheckingGrokAuth =>
      'Check the Grok sign-in state and configuration, then test the connection again.';

  @override
  String get mgmtConfirmClaudeAuthStatusJson =>
      'Confirm `claude auth status --json` can run; you can also run a connection test to verify the current CLI auth path.';

  @override
  String get mgmtNoClaudeLoginEvidenceSuggestion =>
      'No Claude.ai sign-in evidence found. Run `claude auth login` if needed, or run a connection test to confirm the current CLI auth path.';

  @override
  String mgmtCannotIdentifyVersion(String name) {
    return 'Could not identify the $name version.';
  }

  @override
  String get mgmtLatestVersionCheckFailed => 'Latest version check failed.';

  @override
  String get mgmtCannotParseVersionCheck =>
      'Could not parse the version check result.';

  @override
  String get mgmtVersionServiceUnknownFormat =>
      'The version service returned an unknown format.';

  @override
  String get mgmtVersionServiceMissingVersion =>
      'The version service did not return a latest version.';

  @override
  String mgmtCannotGetLatestVersion(String name) {
    return 'Could not get the latest $name version.';
  }

  @override
  String get mgmtAccountLoggedIn => 'Signed in';

  @override
  String get mgmtRunCodexLogin =>
      'Run codex login in a terminal, then detect again.';

  @override
  String get mgmtRunGrokLogin =>
      'Run grok login in a terminal, then detect again.';

  @override
  String get mgmtRerunGrokLogin => 'Run grok login again.';

  @override
  String get mgmtRunCodexLoginStatus =>
      'Run codex login status in a terminal for details.';

  @override
  String get mgmtFixConfigTomlThenRedetect =>
      'Fix the fields reported in config.toml, then detect again.';

  @override
  String get mgmtCodexConfigUnparseable =>
      'The Codex configuration file could not be parsed.';

  @override
  String get mgmtCannotDetectAccount => 'Could not detect account status.';

  @override
  String get mgmtAccountCheckFailed => 'Account status check failed.';

  @override
  String mgmtConfirmCliRuns(String name) {
    return 'Confirm $name can run in a terminal.';
  }

  @override
  String get mgmtCannotParseGrokLoginCache =>
      'Could not parse the Grok login cache.';

  @override
  String get mgmtNoClaudeLoginEvidenceLabel =>
      'No Claude.ai OAuth or API key sign-in evidence found';

  @override
  String get mgmtCannotCheckClaudeAuth =>
      'Could not check sign-in status through the Claude CLI.';

  @override
  String get mgmtCannotStartClaudeInitialize =>
      'Could not start the Claude Code initialize probe.';

  @override
  String get mgmtClaudeAuthViaApiKey =>
      'Authenticated with an Anthropic API key';

  @override
  String get mgmtClaudeAuthViaApiKeyHelper =>
      'Authenticated with an API key helper';

  @override
  String get mgmtClaudeAuthViaOauthToken => 'Authenticated with an OAuth token';

  @override
  String get mgmtClaudeAuthPathDetected =>
      'A Claude Code authentication path was detected';

  @override
  String get mgmtThirdPartyApiProviderConfigured =>
      'A third-party API Provider is configured';

  @override
  String mgmtConfiguredProvider(String provider) {
    return '$provider is configured';
  }

  @override
  String get mgmtPathNotRegularFile =>
      'That path does not exist or is not a regular file';

  @override
  String get mgmtRefuseSymlinkConfig =>
      'Refusing to write a symlink configuration file';

  @override
  String get mgmtConfigExternallyModified =>
      'The configuration file was modified externally.';

  @override
  String get mgmtCompatSupported => 'Verified as supported';

  @override
  String get mgmtCompatLimited => 'Runs with limited capabilities';

  @override
  String get mgmtCompatNewerUntested => 'Newer version, not fully verified';

  @override
  String get mgmtCompatOlderUnsupported => 'Too old to be supported';

  @override
  String get mgmtCompatProtocolMismatch => 'Protocol incompatible';

  @override
  String mgmtCannotEnable(String name, String error) {
    return 'Could not enable $name: $error';
  }

  @override
  String mgmtCannotDisable(String name, String error) {
    return 'Could not disable $name: $error';
  }

  @override
  String mgmtAccountDataEnrichmentSaveFailed(String error) {
    return 'Could not save usage-detail enrichment: $error';
  }

  @override
  String mgmtConnectionTestFailed(String error) {
    return 'Connection test failed: $error';
  }

  @override
  String mgmtConfigurationReadFailed(String error) {
    return 'Could not read the configuration file: $error';
  }

  @override
  String get mgmtConfigurationNotLoaded =>
      'The configuration file has not been loaded';

  @override
  String mgmtLogsReadFailed(String error) {
    return 'Could not read runtime logs: $error';
  }

  @override
  String get mgmtOperationIncomplete => 'The operation did not finish';

  @override
  String get mgmtFilterInstalled => 'Installed';

  @override
  String get mgmtFilterAllSupported => 'All supported';

  @override
  String get mgmtSearchPlaceholder => 'Search Agents or vendors';

  @override
  String get mgmtDetecting => 'Detecting…';

  @override
  String get mgmtAutoDetect => 'Auto-detect Agents';

  @override
  String get mgmtEmptyInstalledTitle => 'No installed Agent detected';

  @override
  String get mgmtEmptyInstalledBody =>
      'You can auto-detect this machine, or open All supported to see Agents this app supports.';

  @override
  String get mgmtViewAllSupported => 'View all supported';

  @override
  String get mgmtNoMatchTitle => 'No matching Agent';

  @override
  String get mgmtNoMatchBody => 'Try changing the search.';

  @override
  String get mgmtClearSearch => 'Clear search';

  @override
  String mgmtVersionWithValue(String version) {
    return 'Version $version';
  }

  @override
  String get mgmtUnknown => 'Unknown';

  @override
  String get mgmtTesting => 'Testing…';

  @override
  String get mgmtTestConnection => 'Test connection';

  @override
  String get mgmtViewLogs => 'View runtime logs';

  @override
  String get mgmtDisableAgent => 'Disable Agent';

  @override
  String get mgmtEnableAgent => 'Enable Agent';

  @override
  String get mgmtTabBasics => 'Basics';

  @override
  String get mgmtTabModels => 'Models';

  @override
  String get mgmtTabConfig => 'Configuration';

  @override
  String get mgmtCopiedCommand => 'Launch command copied.';

  @override
  String get mgmtCannotLoadModels => 'Could not load the model list';

  @override
  String get mgmtModelsNeedLogin =>
      'This account is not signed in. Sign in to Codex and reload.';

  @override
  String get mgmtReload => 'Reload';

  @override
  String mgmtModelSourceUpdated(String source, String updated) {
    return 'Source: $source · Updated: $updated';
  }

  @override
  String get mgmtDisableWarning =>
      'Disabling stops the current task. Existing sessions become read-only.';

  @override
  String get mgmtStopAndDisable => 'Stop and disable';

  @override
  String get mgmtTestClaudeTitle => 'Test the Claude Code connection';

  @override
  String get mgmtTestClaudeBody =>
      'Sends a prompt-free initialize control request only and does not call the model; the Claude CLI may still maintain its own auth or bootstrap cache.';

  @override
  String get mgmtContinueTest => 'Continue test';

  @override
  String mgmtConnectionTestSuccess(String ms) {
    return 'Connection test succeeded. Response took $ms ms.';
  }

  @override
  String mgmtConnectionTestFailedMessage(String message) {
    return 'Connection test failed: $message';
  }

  @override
  String get mgmtUnknownError => 'Unknown error';

  @override
  String mgmtCannotOpenExecutableDir(String error) {
    return 'Could not open the executable directory: $error';
  }

  @override
  String mgmtViewDetails(String name) {
    return 'View $name details';
  }

  @override
  String get mgmtVersionUnknown => 'Version unknown';

  @override
  String get mgmtNotInstalled => 'Not installed';

  @override
  String get mgmtConnectionAvailable => 'Connection available';

  @override
  String get mgmtUpdateAvailable => 'Update available';

  @override
  String get mgmtDetectingShort => 'Detecting';

  @override
  String get mgmtRunning => 'Running';

  @override
  String get mgmtEnabled => 'Enabled';

  @override
  String get mgmtInstalled => 'Installed';

  @override
  String get mgmtSectionBasics => 'Basics';

  @override
  String get mgmtBasicAttributes => 'Basic attributes';

  @override
  String get mgmtName => 'Name';

  @override
  String get mgmtVendor => 'Vendor';

  @override
  String get mgmtProtocol => 'Protocol';

  @override
  String get mgmtTransport => 'Transport';

  @override
  String get mgmtSectionVersion => 'Version';

  @override
  String get mgmtCurrentVersion => 'Current version';

  @override
  String get mgmtLatestVersion => 'Latest version';

  @override
  String get mgmtPathsAndCommands => 'Paths and commands';

  @override
  String get mgmtLaunchCommand => 'Launch command';

  @override
  String get mgmtExecutablePath => 'Executable path';

  @override
  String get mgmtNotDetected => 'Not detected';

  @override
  String get mgmtExecutableNotDetectedHint =>
      'No executable detected yet. Install it and make sure it is on PATH';

  @override
  String get mgmtAutoDetectShort => 'Auto-detect';

  @override
  String get mgmtOpenDirectory => 'Open folder';

  @override
  String get mgmtProgram => 'Program';

  @override
  String get mgmtExecutablePresent => 'Executable exists and can be invoked';

  @override
  String get mgmtExecutableMissing => 'Executable not found';

  @override
  String get mgmtAuthEvidence => 'Auth evidence';

  @override
  String get mgmtCommunication => 'Communication';

  @override
  String get mgmtConnectionProbeOk => 'Connection probe succeeded';

  @override
  String get mgmtHandshakeOk => 'Basic handshake succeeded';

  @override
  String get mgmtNotConfirmed => 'Not confirmed yet';

  @override
  String get mgmtLastDetected => 'Last detection';

  @override
  String get mgmtLastTestDuration => 'Last test duration';

  @override
  String get mgmtHandshakeIdentity => 'Handshake identity';

  @override
  String get mgmtNegotiatedCapabilities => 'Negotiated capabilities';

  @override
  String get mgmtCompatibility => 'Compatibility';

  @override
  String get mgmtExitReason => 'Exit reason';

  @override
  String get mgmtFailureStage => 'Failure stage';

  @override
  String get mgmtDiagnostics => 'Diagnostics';

  @override
  String get mgmtConnectionHealthy => 'Connection healthy';

  @override
  String mgmtSuggestedAction(String suggestion) {
    return 'Suggested action: $suggestion';
  }

  @override
  String get mgmtHidden => 'Hidden';

  @override
  String get mgmtAvailable => 'Available';

  @override
  String get mgmtChipText => 'Text';

  @override
  String get mgmtChipImage => 'Images';

  @override
  String get mgmtChipCode => 'Code';

  @override
  String get mgmtChipFiles => 'File operations';

  @override
  String get mgmtChipTools => 'Tool calls';

  @override
  String get mgmtChipTerminal => 'Terminal';

  @override
  String get mgmtChipStreaming => 'Streaming';

  @override
  String get mgmtReasoningUnknown => 'Reasoning: unknown';

  @override
  String mgmtReasoningAdjustable(String efforts) {
    return 'Reasoning: adjustable ($efforts)';
  }

  @override
  String get mgmtQuotaEnrichmentTitle => 'Usage-detail enrichment';

  @override
  String get mgmtQuotaEnrichmentLabel => 'Read Claude Code usage details';

  @override
  String get mgmtQuotaEnrichmentBody =>
      'This switch only controls whether Zeta briefly reads Claude Code OAuth credentials and calls the usage REST API. Model lists and plan names always come from the Claude CLI; Zeta does not refresh, write back, or persist credentials.';

  @override
  String get mgmtOnboardingTitle => 'Setup guide';

  @override
  String get mgmtOnboardingSubtitle => 'Install · Sign in · Docs';

  @override
  String get mgmtAccountUnknown => 'Could not detect';

  @override
  String get mgmtAccountChecking => 'Checking';

  @override
  String get mgmtAccountLoggedInShort => 'Signed in';

  @override
  String get mgmtAccountLoggedOut => 'Signed out';

  @override
  String get mgmtAccountExpired => 'Sign-in expired';

  @override
  String get mgmtAccountNotRequired => 'Sign-in not required';

  @override
  String get mgmtRuntimeNotRunning => 'Not running';

  @override
  String get mgmtRuntimeIdle => 'Idle';

  @override
  String get mgmtRuntimeStarting => 'Starting';

  @override
  String get mgmtRuntimeStopping => 'Stopping';

  @override
  String get mgmtRuntimeError => 'Error';

  @override
  String get mgmtRuntimeUnavailable => 'Unavailable';

  @override
  String get mgmtRuntimeDisabled => 'Disabled';

  @override
  String get mgmtStageFileDetection => 'File detection';

  @override
  String get mgmtStageCliStartup => 'Process startup';

  @override
  String get mgmtStageVersionDetection => 'Version detection';

  @override
  String get mgmtStageAccountAuthentication => 'Account authentication';

  @override
  String get mgmtStageProtocolHandshake => 'Protocol handshake';

  @override
  String get mgmtStageModelLoading => 'Model loading';

  @override
  String get mgmtStageConfigurationRead => 'Configuration read';

  @override
  String get mgmtStageTestRequest => 'Test request';

  @override
  String get mgmtStageProcessExit => 'Process exit';

  @override
  String get mgmtListScope => 'Agent list scope';

  @override
  String get mgmtDetailTabs => 'Agent details';

  @override
  String get mgmtModelsHandshakeFailed =>
      'The app-server did not return models, or the current configuration could not complete the handshake.';

  @override
  String mgmtAgentCurrentlyRunning(String name) {
    return '$name is currently running';
  }

  @override
  String get mgmtStatusNeedsCheck => 'Status needs attention';

  @override
  String mgmtRuntimeLogsTitle(String name) {
    return '$name runtime logs';
  }

  @override
  String mgmtLogSourcesLoaded(String sources, String lines) {
    return '$sources diagnostic sources · $lines lines loaded';
  }

  @override
  String get mgmtNotUpdated => 'Not updated yet';

  @override
  String get mgmtUnsavedTitle => 'Configuration is not saved';

  @override
  String get mgmtUnsavedBody => 'Leaving now discards these changes.';

  @override
  String get mgmtKeepEditing => 'Keep editing';

  @override
  String get mgmtDiscardChanges => 'Discard changes';

  @override
  String get mgmtLoadingConfig => 'Loading the configuration file';

  @override
  String get mgmtConfigNotLoadedYet =>
      'The configuration file has not been loaded.';

  @override
  String get mgmtSensitiveMaskedTitle => 'Sensitive values are hidden';

  @override
  String get mgmtSensitiveMaskedBody =>
      'Shown read-only by default so credentials are not exposed. Click Show sensitive values to edit the full configuration.';

  @override
  String get mgmtConfigFile => 'Configuration file';

  @override
  String get mgmtConfigExists => 'exists';

  @override
  String get mgmtConfigMissing => 'not created yet';

  @override
  String mgmtLastLoaded(String time) {
    return 'Last loaded $time';
  }

  @override
  String get mgmtReloadConfig => 'Reload';

  @override
  String get mgmtOpenContainingFolder => 'Open containing folder';

  @override
  String get mgmtHideSensitive => 'Hide sensitive values';

  @override
  String get mgmtShowSensitive => 'Show sensitive values';

  @override
  String get mgmtSearchInConfig => 'Search in configuration';

  @override
  String get mgmtFindNext => 'Find next';

  @override
  String get mgmtConfigValid => 'Configuration format is valid';

  @override
  String get mgmtCancelEdits => 'Cancel edits';

  @override
  String get mgmtSaving => 'Saving…';

  @override
  String get mgmtSaveConfig => 'Save configuration';

  @override
  String get mgmtConfigSavedRestart =>
      'Configuration saved. Restart Codex to apply it.';

  @override
  String get mgmtConfigSavedBackup =>
      'Configuration saved, and a backup of the original file was created.';

  @override
  String get mgmtConfigExternalTitle =>
      'The configuration file was modified externally';

  @override
  String get mgmtConfigExternalBody =>
      'Continuing will overwrite the external changes.';

  @override
  String get mgmtSaveAnyway => 'Save anyway';

  @override
  String mgmtConfigSaveFailed(String error) {
    return 'Could not save the configuration: $error';
  }

  @override
  String mgmtQueryNotFound(String query) {
    return 'No matches for \"$query\".';
  }

  @override
  String mgmtCannotOpenConfigDir(String error) {
    return 'Could not open the configuration directory: $error';
  }

  @override
  String get mgmtRefreshing => 'Refreshing…';

  @override
  String get mgmtRefresh => 'Refresh';

  @override
  String get mgmtCopyLogs => 'Copy logs';

  @override
  String get mgmtSearchLogKeywords => 'Search log keywords';

  @override
  String get mgmtLogLevel => 'Log level';

  @override
  String get mgmtAll => 'All';

  @override
  String get mgmtReadingLogs => 'Reading Agent logs';

  @override
  String get mgmtNoMatchingLogs => 'No logs match the current filters.';

  @override
  String mgmtCopiedLogs(String count) {
    return 'Copied $count redacted log lines.';
  }

  @override
  String get agentReadonlyTitle => 'This session is read-only';

  @override
  String get agentReadonlyBody =>
      'The Agent for this session has been disabled. You can still view history, but you cannot send more messages.';

  @override
  String get agentMessagePlaceholder => 'Message Agent';

  @override
  String get agentSend => 'Send';

  @override
  String get agentCancel => 'Cancel';

  @override
  String get agentCancelAction => 'Cancel';

  @override
  String get agentCancelTurn => 'Cancel turn';

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
  String get agentPermissionMode => 'Permission mode';

  @override
  String get agentPlanReadOnlyHint => 'Read-only planning; cannot change files';

  @override
  String get agentTokenUsage => 'Token usage';

  @override
  String get agentContextWindowUsage => 'Context window token usage';

  @override
  String get agentRename => 'Rename';

  @override
  String get agentForkSession => 'Fork this session';

  @override
  String get agentArchive => 'Archive';

  @override
  String get agentContext => 'Context';

  @override
  String get agentMore => 'More';

  @override
  String agentProjectName(String name) {
    return 'Project $name';
  }

  @override
  String get agentReadonlyPlanMode => 'Read-only Plan mode';

  @override
  String get agentLoadingSession => 'Loading session…';

  @override
  String get agentAcceptPlan => 'Accept plan';

  @override
  String get agentAcceptPlanHint =>
      'Accepting the plan only confirms the proposal. Commands, files, and network still need separate permission.';

  @override
  String get agentCommandGroup => 'Command group';

  @override
  String get agentFileEditGroup => 'File edit group';

  @override
  String get agentToolCall => 'Tool call';

  @override
  String get agentThinking => 'Thinking';

  @override
  String get agentRunning => 'Running';

  @override
  String agentRunningPrefix(String title) {
    return 'Running · $title';
  }

  @override
  String get agentExecute => 'Execute';

  @override
  String get agentSteps => 'Steps';

  @override
  String get agentRevisePlanHint => 'Add to or revise the plan…';

  @override
  String get agentRevise => 'Revise';

  @override
  String get agentAbandon => 'Abandon';

  @override
  String get agentExecPermission => 'Execution permission';

  @override
  String get agentChooseExecPermission => 'Choose execution permission';

  @override
  String get agentPermCatalogDefault => 'Conservative default';

  @override
  String get agentPermUserOverride => 'This time only';

  @override
  String get agentPermNeedsChoice => 'Selection required';

  @override
  String agentPermissionRequest(String kind, String title) {
    return 'Permission request: $kind · $title';
  }

  @override
  String get agentDeny => 'Deny';

  @override
  String get agentAllowSession => 'Allow this session';

  @override
  String get agentAlwaysAllow => 'Always allow';

  @override
  String get agentOverrideGuard => 'Override guard';

  @override
  String get agentAllow => 'Allow';

  @override
  String get agentPermKindCommand => 'Run command';

  @override
  String get agentPermKindFile => 'Apply file changes';

  @override
  String get agentPermKindPermissions => 'Grant permissions';

  @override
  String get agentPermKindOther => 'Request confirmation';

  @override
  String get agentPermShortCommand => 'Command';

  @override
  String get agentPermShortFile => 'File';

  @override
  String get agentPermShortPermissions => 'Permission';

  @override
  String get agentPermShortOther => 'Confirm';

  @override
  String get agentCloseQuestion => 'Close question';

  @override
  String get agentNoAnswerableQuestions =>
      'This request has no questions to answer.';

  @override
  String get agentSubmitAnswers => 'Submit answers';

  @override
  String get agentConfirmNextQuestion => 'Confirm and go to the next question';

  @override
  String get agentSkip => 'Skip';

  @override
  String get agentSubmit => 'Submit';

  @override
  String get agentNext => 'Next';

  @override
  String get agentMultiSelect => 'Multiple options can be selected';

  @override
  String get agentPreviousQuestion => 'Previous question';

  @override
  String get agentNextQuestion => 'Next question';

  @override
  String get agentCustomSolutionHint => 'Enter your solution…';

  @override
  String get agentOtherCustomSolution => 'Other, enter a custom solution';

  @override
  String get agentWaitingApproval => 'Waiting for approval';

  @override
  String get agentWaitingInput => 'Waiting for input';

  @override
  String get agentSystemError => 'System error';

  @override
  String get agentToolRead => 'Read';

  @override
  String get agentToolEdit => 'Edit';

  @override
  String get agentToolDelete => 'Delete';

  @override
  String get agentToolMove => 'Move';

  @override
  String get agentToolSearch => 'Search';

  @override
  String get agentToolExecute => 'Execute';

  @override
  String get agentToolThink => 'Think';

  @override
  String get agentToolFetch => 'Fetch';

  @override
  String get agentToolOther => 'Action';

  @override
  String get agentTurnChanges => 'Changes in this turn';

  @override
  String agentFileCount(String count) {
    return '$count files';
  }

  @override
  String get agentNavConversation => 'Conversation navigation';

  @override
  String agentTurnOrdinal(String n) {
    return 'Turn $n';
  }

  @override
  String agentTurnOrdinalWithLabel(String n, String label) {
    return 'Turn $n: $label';
  }

  @override
  String get agentStatusStreaming => 'Generating';

  @override
  String get agentStatusCompleted => 'Completed';

  @override
  String get agentStatusFailed => 'Failed';

  @override
  String get agentStatusInterrupted => 'Interrupted';

  @override
  String get agentStatusUnknown => 'Unknown';

  @override
  String get agentCreateBranchHere => 'Create a branch from here';

  @override
  String get agentCreateBranchRetry => 'Create a branch and retry';

  @override
  String get agentCreateBranchBody =>
      'The original session is kept, and a new branch starts after the previous turn. Workspace files are not rolled back; earlier Agent writes remain.';

  @override
  String get agentEditMessage => 'Edit message…';

  @override
  String get agentCreateBranchSend => 'Create branch and send';

  @override
  String get agentPlan => 'Plan';

  @override
  String get agentCollapsePlan => 'Collapse plan';

  @override
  String get agentExpandPlan => 'Expand plan';

  @override
  String get agentCollapseCurrentPlan => 'Collapse current plan';

  @override
  String get agentExpandCurrentPlan => 'Expand current plan';

  @override
  String agentCurrentPlanProgress(String progress) {
    return 'Current plan progress $progress';
  }

  @override
  String agentCurrentStep(String content) {
    return 'Current step: $content';
  }

  @override
  String get agentCurrent => 'Current';

  @override
  String get agentPlanCompleted => 'Completed';

  @override
  String get agentPlanInProgress => 'In progress';

  @override
  String get agentPlanPending => 'Pending';

  @override
  String get agentPlanUnknown => 'Unknown status';

  @override
  String get agentNoExecPermission =>
      'No execution permission is available. Choose one first. Execution does not pre-authorize commands, files, or the network.';

  @override
  String agentDefaultExecPermission(String label) {
    return 'Default is “$label”. Execution starts a new Default turn. Commands, files, and network still follow that mode.';
  }

  @override
  String get agentSlashCommands => 'Commands';

  @override
  String get agentModel => 'Model';

  @override
  String get agentModelLoadFailed => 'Failed to load models';

  @override
  String get agentModelConfig => 'Model configuration';

  @override
  String get agentLoadingModels => 'Loading models…';

  @override
  String get agentNoModels => 'No models available';

  @override
  String get agentConfigNextTurn => 'Configuration applies on the next turn';

  @override
  String get agentModelUnavailable => 'This model is currently unavailable';

  @override
  String get agentNoReasoningConfig =>
      'This model does not provide configurable reasoning effort';

  @override
  String get agentRetry => 'Retry';

  @override
  String get agentReasoningEffort => 'Reasoning effort';

  @override
  String get agentFastOn => 'On';

  @override
  String get agentFastOff => 'Off';

  @override
  String get agentClose => 'Close';

  @override
  String get agentSessionName => 'Session name';

  @override
  String get agentSessionId => 'Session ID';

  @override
  String get agentMessageCount => 'Messages';

  @override
  String get agentProvider => 'Provider';

  @override
  String get agentContextLimit => 'Context limit';

  @override
  String get agentTotalTokens => 'Total tokens';

  @override
  String get agentInputTokens => 'Input tokens';

  @override
  String get agentOutputTokens => 'Output tokens';

  @override
  String get agentCachedTokens => 'Cached tokens';

  @override
  String get agentCreatedAt => 'Created';

  @override
  String get agentLastActive => 'Last active';

  @override
  String get agentRawMessages => 'Raw messages';

  @override
  String get agentChatOnly => 'Chat only';

  @override
  String get agentAll => 'All';

  @override
  String get agentShowChatOnly =>
      'Showing chat messages only. Tap to show all.';

  @override
  String get agentShowAllMessages =>
      'Showing all messages. Tap to show chat only.';

  @override
  String get agentNoChatMessages => 'No chat messages';

  @override
  String get agentNoRawMessages => 'No raw messages';

  @override
  String get agentCopyOriginal => 'Copy original';

  @override
  String get agentCopiedOriginal => 'Original copied.';

  @override
  String get agentKindApproval => 'Approval';

  @override
  String get agentKindQuestion => 'Question';

  @override
  String get agentKindPlanApproval => 'Plan approval';

  @override
  String get agentKindFileChange => 'File change';

  @override
  String get agentRoleUser => 'User';

  @override
  String get agentRoleAgent => 'Assistant';

  @override
  String get agentRoleSystem => 'System';

  @override
  String get agentEvidenceReplaceBefore => 'Before replacement';

  @override
  String get agentEvidenceReplaceAfter => 'After replacement';

  @override
  String get agentEvidenceEmptySnippet =>
      'Empty snippet (explicitly provided by the Provider)';

  @override
  String get agentEvidenceEmptyContent =>
      'Empty content (explicitly provided by the Provider)';

  @override
  String get agentEvidenceEmptyDiff =>
      'Empty diff (explicitly provided by the Provider)';

  @override
  String get agentEvidenceAdd => 'Added';

  @override
  String get agentEvidenceRemove => 'Removed';

  @override
  String get agentEvidenceWrite => 'Write';

  @override
  String get agentWrittenContent => 'Written content';

  @override
  String agentWrittenContentWithStatus(String title, String status) {
    return '$title · $status';
  }

  @override
  String get agentUnifiedDiff => 'Unified diff';

  @override
  String get agentDiffMetadata => 'Diff metadata';

  @override
  String get agentDiffHunkTitle => 'Diff hunk title';

  @override
  String get agentEmptyLine => 'Empty line';

  @override
  String get agentLiveSummary => 'Live summary for this turn';

  @override
  String get agentLiveSummaryHint =>
      'Live summary for this turn; cannot be restored from history';

  @override
  String get agentTurnSummary => 'Summary for this turn';

  @override
  String get agentReplaceSnippet => 'Replacement snippet';

  @override
  String get agentReplaceSnippetAll => 'Replacement snippet · all matches';

  @override
  String get agentFileCreated => 'Created';

  @override
  String get agentFileModified => 'Modified';

  @override
  String get agentFileDeleted => 'Deleted';

  @override
  String get agentFileMoved => 'Moved';

  @override
  String get agentFileChanged => 'File change';

  @override
  String get agentToolPending => 'Pending';

  @override
  String get agentToolInProgress => 'In progress';

  @override
  String get agentToolCompleted => 'Completed';

  @override
  String get agentToolFailed => 'Failed';

  @override
  String get agentToolCancelled => 'Cancelled';

  @override
  String get agentConversationModeIcon => 'Conversation mode icon';

  @override
  String get agentConversationModeOptions => 'Conversation mode options';

  @override
  String get agentModeSelected => 'Selected';

  @override
  String get agentModeSelectable => 'Selectable';

  @override
  String get agentModeNotSelectable => 'Not selectable';

  @override
  String get agentLoadingModes => 'Loading conversation modes';

  @override
  String get agentCannotLoadModes =>
      'The current Provider cannot load conversation modes';

  @override
  String get agentStarting => 'Starting';

  @override
  String get agentResponding => 'Responding';

  @override
  String get agentPlanReady => 'Plan ready';

  @override
  String get agentModelRerouted => 'Model rerouted';

  @override
  String agentModelReroutedTo(String model) {
    return 'Rerouted to $model';
  }

  @override
  String get agentDeprecationNotice => 'Adapter deprecation notice';

  @override
  String get agentDeprecationUpgradeHint =>
      'Please upgrade the Codex adapter to stay compatible with protocol changes.';

  @override
  String get agentRerouteReasonHighRisk =>
      'Reason: high-risk cyber activity policy';

  @override
  String agentRerouteReasonUnknown(String reason) {
    return 'Reason: $reason';
  }

  @override
  String get agentTurnFailedPrefix => 'Turn failed: ';

  @override
  String get agentUnknownProviderError => 'Unknown provider error';

  @override
  String get agentServerWillRetry => ' (the server will retry automatically)';

  @override
  String get agentErrorGuidanceServerOverloaded =>
      '. The selected model is at capacity. Switch models or try again later.';

  @override
  String get agentErrorGuidanceUsageLimit =>
      '. Usage or rate limit reached. Check your quota or try again later.';

  @override
  String get agentErrorGuidanceSessionBudget =>
      '. Session budget is exhausted. Start a new session or adjust the budget.';

  @override
  String get agentErrorGuidanceUnauthorized =>
      '. Authentication failed. Check sign-in or API credentials and retry.';

  @override
  String get agentErrorGuidanceInternalServer =>
      '. The server reported an internal error. Retry later or switch models.';

  @override
  String get agentErrorGuidanceNetwork =>
      '. Network connection failed. Check the network and retry.';

  @override
  String get agentErrorGuidanceTooManyAttempts =>
      '. Too many failed retries. Try again later or switch models.';

  @override
  String get agentWebSearch => 'Web search';

  @override
  String get agentViewImage => 'View image';

  @override
  String get agentGenerateImage => 'Generate image';

  @override
  String get agentCollaboratePrefix => 'Collaborate';

  @override
  String get agentToolCallFallback => 'Tool call';

  @override
  String get agentReviewModeEntered => 'Entered review mode';

  @override
  String get agentReviewModeExited => 'Exited review mode';

  @override
  String get agentContextCompacted => 'Context compacted';

  @override
  String get agentContextCompactedDescription =>
      'Session context was compacted to free window space.';

  @override
  String get agentHookPrompt => 'Hook prompt';

  @override
  String get agentWaiting => 'Waiting';

  @override
  String agentSleepMinutes(String minutes) {
    return 'Slept $minutes minutes';
  }

  @override
  String agentSleepMinutesSeconds(String minutes, String seconds) {
    return 'Slept $minutes min $seconds s';
  }

  @override
  String agentSleepSeconds(String seconds) {
    return 'Slept $seconds seconds';
  }

  @override
  String get agentSubAgentActivity => 'Sub-agent activity';

  @override
  String get agentSubAgentStarted => 'Started';

  @override
  String get agentSubAgentInteracted => 'Interacted';

  @override
  String get agentSubAgentInterrupted => 'Interrupted';

  @override
  String get agentSubAgentUpdated => 'Updated';

  @override
  String get agentUserCancelled => 'Cancelled by user';

  @override
  String get agentPermissionAskDescription => 'Ask before every high-risk tool';

  @override
  String get agentPermissionAcceptEditsDescription =>
      'Allow edit tools automatically; still ask for others';

  @override
  String get agentPermissionPlanDescription =>
      'Read-only planning; no side effects';

  @override
  String get agentPermissionBypassDescription =>
      'Skip permission checks (high risk)';

  @override
  String get agentPlanQuota => 'Plan quota';

  @override
  String get agentOnDemandQuota => 'On-demand quota';

  @override
  String get agentPrimaryQuota => 'Primary quota';

  @override
  String get agentExtraQuota => 'Extra quota';

  @override
  String get desktopAttentionTurnCompleted => 'Task completed';

  @override
  String get desktopAttentionTurnFailed => 'Task failed';

  @override
  String get desktopAttentionTurnInterrupted => 'Task interrupted';

  @override
  String get desktopAttentionPermissionRequired => 'Permission required';

  @override
  String get desktopAttentionQuestionRequired => 'Question required';

  @override
  String get desktopAttentionPlanApprovalRequired => 'Plan approval required';

  @override
  String get desktopAttentionPlanExecutionRequired => 'Plan ready to execute';

  @override
  String get desktopAttentionCurrentProject => 'Current project';

  @override
  String desktopAttentionSessionBody(String project) {
    return '$project · Agent session';
  }

  @override
  String get desktopAttentionLinuxAction => 'Open Zeta';

  @override
  String get timelineScrollToEnd => 'Scroll to the end of the conversation';

  @override
  String get relativeTimeJustNow => 'Just now';

  @override
  String relativeTimeMinutesAgo(String count) {
    return '$count minutes ago';
  }

  @override
  String relativeTimeHoursAgo(String count) {
    return '$count hours ago';
  }

  @override
  String relativeTimeDaysAgo(String count) {
    return '$count days ago';
  }

  @override
  String get contextRoleUser => 'User';

  @override
  String get contextRoleAssistant => 'Assistant';

  @override
  String get contextRoleSystem => 'System';

  @override
  String get contextRolePlan => 'Plan';

  @override
  String get contextEventPermission => 'Approval';

  @override
  String get contextEventWarning => 'Warning';

  @override
  String get usageNoData => 'No data';

  @override
  String get usageUnknownPlan => 'Unknown plan';

  @override
  String get mgmtCapText => 'Text';

  @override
  String get mgmtCapImage => 'Image';

  @override
  String get mgmtCapCode => 'Code';

  @override
  String get mgmtCapFileOps => 'File operations';

  @override
  String get mgmtCapToolCall => 'Tool calls';

  @override
  String get mgmtCapTerminal => 'Terminal';

  @override
  String get mgmtCapStreaming => 'Streaming';

  @override
  String get mgmtQuotaEnrichmentSubtitle => 'OAuth credentials · Usage REST';

  @override
  String get mgmtSetupGuideTitle => 'Setup guide';

  @override
  String get mgmtSetupGuideSubtitle => 'Install · Sign in · Docs';

  @override
  String get mgmtSetupInstallTitle => '1. Install the Claude Code CLI';

  @override
  String get mgmtSetupInstallBody =>
      'Run npm install -g @anthropic-ai/claude-code in a terminal, and make sure claude is on PATH.';

  @override
  String get mgmtSetupLoginTitle => '2. Sign in';

  @override
  String get mgmtSetupLoginBody =>
      'Run claude auth login to sign in to your Anthropic account. Auto-detect never reads credential contents; quota enrichment only does the read-only query described above and never writes the credential file.';

  @override
  String get mgmtSetupDocsTitle => '3. Official docs';

  @override
  String mgmtSetupDocsBody(String url) {
    return 'See the Anthropic Claude Code docs for full capabilities and protocol details: $url';
  }

  @override
  String get fontGeistBundled => 'Geist (built-in default)';

  @override
  String get fontSystemDefaultAlias => 'System default';

  @override
  String get fontJetBrainsBundled => 'JetBrainsMono (built-in default)';

  @override
  String get agentModeLoadFailed =>
      'Could not load conversation modes. Please retry.';

  @override
  String agentFastIncompatible(String effort) {
    return 'Fast is incompatible with “$effort”';
  }

  @override
  String agentFastDisableAndSwitch(String effort) {
    return 'Turn off Fast and switch to $effort';
  }

  @override
  String agentFastSwitchAndEnable(String effort) {
    return 'Switch to $effort and turn on Fast';
  }

  @override
  String get agentModelSaveFailed =>
      'Could not save the configuration. The last valid settings were restored.';

  @override
  String agentModelUnavailableSwitched(String previous, String current) {
    return 'Model “$previous” is unavailable. Switched to $current.';
  }

  @override
  String get agentPermNextSession => 'Applies to the next session';

  @override
  String get agentPermCurrentTurn => 'Applies to this turn';

  @override
  String get agentPermUnsupported =>
      'The current Provider does not support permission selection';

  @override
  String get agentPermNextSend => 'Applies the next time you send';

  @override
  String get agentPermSavedButPersistFailed =>
      'Permission preference updated, but saving failed. You can retry.';

  @override
  String get agentPermAppliedButPersistFailed =>
      'Permission preference applied, but saving failed. You can retry.';

  @override
  String get agentPermRuntimeStale =>
      'The Provider runtime is no longer valid. Please retry.';

  @override
  String get agentPermSwitchFailed => 'Could not switch the permission mode';

  @override
  String get agentProviderDefaultPermission => 'Provider default permission';

  @override
  String agentThreadDisabled(String name) {
    return '$name is disabled or unavailable; the session cannot be modified.';
  }

  @override
  String get agentNoRawPayload => '(No raw data)';

  @override
  String get agentTurnRunning => 'Turn running';

  @override
  String get agentToolRunning => 'Tool running';

  @override
  String get agentNoPromptSummary => '(No prompt summary)';

  @override
  String agentStatusWithValue(String status) {
    return 'Status: $status';
  }

  @override
  String agentTimeWithValue(String time) {
    return 'Time: $time';
  }

  @override
  String get agentLoadingHistory => 'Loading thread history';

  @override
  String get agentNoSkills => 'No skills found';

  @override
  String get agentNoMatches => 'No matches';

  @override
  String agentCountTimes(String count, String kind) {
    return '$count×$kind';
  }

  @override
  String agentElapsedTotal(String duration) {
    return 'Total $duration';
  }

  @override
  String get agentCurrentlyViewing => ', currently viewing';

  @override
  String agentLineCount(String count) {
    return '$count lines';
  }

  @override
  String agentAddedRemovedLines(String added, String removed) {
    return 'Added $added lines, removed $removed lines';
  }

  @override
  String get agentNoContentEvidence =>
      'The Provider did not supply content evidence';

  @override
  String get agentBeforePlan => 'Before Plan';

  @override
  String get agentAsk => 'Agent question';

  @override
  String get agentReadOnlyCustomMode =>
      'This is a read-only custom mode. You can override it with a built-in mode.';

  @override
  String get agentModeLoadingSemantic => 'Mode…, conversation mode, loading';

  @override
  String agentModeErrorSemantic(String detail) {
    return 'Mode unavailable, conversation mode, $detail';
  }

  @override
  String agentNextTurnShort(String label) {
    return '$label · next turn';
  }

  @override
  String get agentModeReadOnlySuffix => ', current mode is read-only';

  @override
  String get agentNextTurnSuffix => ', applies on the next turn';

  @override
  String get agentModeProviderSet =>
      'The current mode comes from the Provider. You can override it with a built-in mode.';

  @override
  String agentNextTurnAppliesTooltip(String label) {
    return '$label\nApplies on the next turn';
  }

  @override
  String agentConversationModeSemantic(String label, String suffix) {
    return '$label, conversation mode$suffix';
  }

  @override
  String agentModeOptionSemantic(String label, String state) {
    return '$label, $state';
  }

  @override
  String agentReasoningEffortValue(String value) {
    return 'Reasoning effort: $value';
  }

  @override
  String agentFastValue(String value) {
    return 'Fast: $value';
  }

  @override
  String agentModelConfigSemantic(String label) {
    return '$label, model configuration';
  }

  @override
  String agentModelConfigErrorSemantic(String label, String error) {
    return '$label, $error';
  }

  @override
  String get agentPlanModeClearNextTurn =>
      'Plan, conversation mode, applies next turn, tap to clear';

  @override
  String get agentPlanModeClear => 'Plan, conversation mode, tap to clear';

  @override
  String get agentPlanNextTurnTooltip => 'Plan\nApplies on the next turn';

  @override
  String get agentLoadingModesStatus => 'Loading conversation modes…';

  @override
  String get agentModeNotSelectableNow =>
      'The current mode cannot be selected directly';

  @override
  String get agentModelCatalogRefreshFailed =>
      'Model catalog refresh failed. Using the local cache.';

  @override
  String get agentModelListRefreshFailed =>
      'Model list refresh failed. The current configuration was kept.';

  @override
  String get agentCannotSwitchPermissionDuringTurn =>
      'A turn is running. Wait until it finishes before changing the permission mode.';

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
  String agentEvidenceReplaceSemantics(String before, String after) {
    return 'Replacement snippet, $before lines before, $after lines after';
  }

  @override
  String agentWrittenContentSemantics(String status, String count) {
    return 'Written content, $status, $count lines';
  }

  @override
  String agentUnifiedDiffSemantics(String count) {
    return 'Unified diff, $count lines';
  }

  @override
  String agentScrollableLines(String title, String count) {
    return '$title, scrollable, $count lines';
  }

  @override
  String get agentKeyboardScrollHint =>
      'Use arrow keys, Page Up, Page Down, Home, or End to scroll';

  @override
  String agentLineAt(String kind, String n, String text) {
    return '$kind, line $n: $text';
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
    return '$label, permission mode, $hint';
  }

  @override
  String agentPermissionModeOnly(String label) {
    return '$label, permission mode';
  }

  @override
  String agentFastSemantic(String model, String state) {
    return '$model, Fast, $state';
  }

  @override
  String get agentModelUnavailableNow => 'This model is currently unavailable';

  @override
  String get agentOptionSelectedSuffix => ', selected';

  @override
  String agentLabeledValue(String label, String value) {
    return '$label: $value';
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
    return '$name App Server connection closed';
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
  String get agentDefaultThreadTitle => 'New conversation';

  @override
  String agentUsageWindowWeeks(String count) {
    return '$count weeks';
  }

  @override
  String agentUsageWindowDays(String count) {
    return '$count days';
  }

  @override
  String agentUsageWindowHours(String count) {
    return '$count hours';
  }

  @override
  String agentUsageWindowHoursMinutes(String hours, String minutes) {
    return '$hours hours $minutes minutes';
  }

  @override
  String agentUsageWindowMinutes(String count) {
    return '$count minutes';
  }

  @override
  String get agentUsageWindowOneWeek => '1 week';

  @override
  String get agentUsageWindowOneDay => '1 day';

  @override
  String get agentQuotaFiveHours => '5h';

  @override
  String get agentQuotaOneWeek => '1 week';

  @override
  String get agentQuotaSonnetOneWeek => 'Sonnet 1 week';

  @override
  String get agentQuotaOpusOneWeek => 'Opus 1 week';

  @override
  String get agentClaudeCodeSubscriptionQuota =>
      'Claude Code subscription quota';

  @override
  String get agentCouldNotLoadThreads => 'Could not load threads';

  @override
  String get agentNoEnabledProviders => 'No enabled Agent providers';

  @override
  String get mgmtClaudeInitializeSuccess =>
      'Claude Code initialize succeeded. The CLI and current auth path are available.';

  @override
  String get mgmtClaudeInitializeTimeout =>
      'Claude Code initialize did not finish within 20 seconds.';

  @override
  String get mgmtClaudeInitializeFailed =>
      'Claude Code initialize probe failed.';

  @override
  String mgmtVersionDetectFailed(String name) {
    return '$name version detection failed.';
  }

  @override
  String get mgmtClaudeLoginEvidenceUnavailable =>
      'Claude Code login evidence is unavailable';

  @override
  String get mgmtClaudeInitializeProcessExited =>
      'The Claude Code process exited before initialize finished.';

  @override
  String get mgmtClaudeInitializeRejected =>
      'Claude Code rejected the initialize request.';

  @override
  String get mgmtClaudeInitializeInvalidResponse =>
      'Claude Code returned an invalid initialize response.';

  @override
  String get mgmtClaudeInitializeInvalidStream =>
      'Claude Code returned invalid stream-json data.';

  @override
  String get mgmtClaudeInitializeCommunicationFailed =>
      'Claude Code initialize communication failed.';

  @override
  String get mgmtClaudeAiLoggedIn => 'Signed in to Claude.ai';

  @override
  String mgmtClaudeAiLoggedInAs(String plan) {
    return 'Signed in to Claude.ai · $plan';
  }

  @override
  String mgmtNotLoggedIn(String name) {
    return '$name is not signed in.';
  }

  @override
  String get mgmtGrokLoginCacheEmpty => 'The Grok login cache is empty.';

  @override
  String get mgmtGrokAcpOk => 'Grok ACP connection is healthy';

  @override
  String get mgmtGrokAcpFailed => 'Grok ACP connection failed.';

  @override
  String get mgmtGrokLatestVersionNetworkHint =>
      'Check the network and detect again, or run grok update --check in a terminal.';

  @override
  String get mgmtCodexAppServerFailed => 'Codex app-server connection failed.';

  @override
  String mgmtDetectionIncomplete(String error) {
    return 'Agent detection did not finish: $error';
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
    return 'The $name session directory could not be fully enumerated. Readable data is shown.';
  }

  @override
  String usageSessionFilesUnreadable(String count, String name) {
    return '$count $name session files could not be read. Other data is shown.';
  }

  @override
  String usageHistoryRowsCorrupt(String count, String name) {
    return '$count $name history lines were corrupt and skipped.';
  }
}

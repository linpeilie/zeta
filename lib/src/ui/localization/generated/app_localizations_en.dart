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
      'Continue recent work, or open a project to start.';

  @override
  String get homeOpenProjectFolder => 'Open project folder';

  @override
  String get homeOpenProject => 'Open project';

  @override
  String get homeRecentProjects => 'Recent projects';

  @override
  String get homeReadingRecentProjects => 'Reading recent projects…';

  @override
  String get homeNoRecentProjects => 'No recent projects';

  @override
  String get homeRecentProjectsAfterRestore =>
      'Recent projects will appear here after restore finishes.';

  @override
  String get homeRecentProjectsAfterOpen =>
      'After you open a project, it will appear here.';

  @override
  String get homeRecentSessions => 'Recent sessions';

  @override
  String get homeRefreshFailed => 'Refresh failed';

  @override
  String get homeCannotRefreshSessions => 'Could not refresh recent sessions';

  @override
  String get homeLoadingRecentSessions => 'Loading recent sessions…';

  @override
  String get homeNoRecentSessions => 'No recent sessions';

  @override
  String get homeSessionsCacheHint =>
      'Cached sessions show first; newer ones fill in in the background.';

  @override
  String get homeSessionsEmptyHint =>
      'After you create a session, it appears by last activity.';

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
  String homeOpenRecentProject(String name) {
    return 'Open recent project $name';
  }

  @override
  String homeOpenRecentSession(String title) {
    return 'Open recent session $title';
  }

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
  String get homeProviderUpdateAvailable => 'Update available';

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
  String get usageRetry => 'Retry';

  @override
  String get usagePrevWindow => 'Previous window';

  @override
  String get usageNextWindow => 'Next window';
}

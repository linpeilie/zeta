/// IDE 布局与密度 Token。
///
/// 与间距不同，这些值描述稳定的组件尺寸和响应式阈值。
abstract final class IdeMetrics {
  static const double titleBarHeight = 28;
  static const double pageHeaderHeight = 44;
  static const double paneHeaderHeight = 38;
  static const double toolbarHeight = 34;

  static const double compactRowHeight = 28;
  static const double listRowHeight = 32;
  static const double settingsRowMinHeight = 52;
  static const double iconButtonHitSize = 28;
  static const double activityRailWidth = 36;

  static const double navigationPaneWidth = 240;
  static const double sidePaneDefaultWidth = 280;
  static const double sidePaneMinWidth = 220;
  static const double sidePaneMaxWidth = 400;
  static const double inspectorPaneWidth = 300;

  static const double contentMaxWidth = 920;
  static const double settingsContentMaxWidth = 960;
  static const double analyticsContentMaxWidth = 1440;
  static const double mainEditorMinWidth = 480;

  static const double composerMinHeight = 88;
  static const double composerMaxHeight = 240;

  static const double wideBreakpoint = 1180;
  static const double mediumBreakpoint = 820;
  static const double stackedRowBreakpoint = 640;
}

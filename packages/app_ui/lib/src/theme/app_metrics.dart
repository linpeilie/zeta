import 'dart:math' as math;
import 'dart:ui';

import 'package:app_ui/src/theme/app_control_size.dart';
import 'package:flutter/material.dart';

/// Stable component dimensions and responsive breakpoints.
@immutable
class AppMetrics extends ThemeExtension<AppMetrics> {
  /// Creates the desktop metric scale.
  const AppMetrics({
    this.titleBarHeight = 32,
    this.pageHeaderHeight = 44,
    this.paneHeaderHeight = 32,
    this.macOSTrafficLightGutter = 76,
    this.toolbarHeight = 34,
    this.controlPaddingYRegular = 10,
    this.controlPaddingYCompact = 6,
    this.controlMinHeightRegular = 28,
    this.controlMinHeightCompact = 24,
    this.compactRowHeight = 28,
    this.listRowHeight = 32,
    this.settingsRowMinHeight = 52,
    this.keyValueLabelWidth = 92,
    this.minimumInteractiveTarget = 24,
    this.preferredInteractiveTarget = 48,
    this.iconButtonHitSize = 28,
    this.switchTrackWidth = 36,
    this.switchTrackHeight = 20,
    this.switchThumbSize = 16,
    this.switchTrackPadding = 2,
    this.messageThumbnailSize = 120,
    this.activityRailWidth = 36,
    this.activityRailIconSize = 19,
    this.navigationPaneWidth = 240,
    this.sidePaneDefaultWidth = 280,
    this.sidePaneMinWidth = 220,
    this.sidePaneMaxWidth = 400,
    this.inspectorPaneWidth = 300,
    this.projectsPaneMinHeight = 160,
    this.contentMaxWidth = 920,
    this.settingsContentMaxWidth = 960,
    this.analyticsContentMaxWidth = 1440,
    this.mainEditorMinWidth = 480,
    this.metricBarEqualWidthBreakpoint = 900,
    this.metricBarItemWidth = 180,
    this.metricBarDividerHeight = 36,
    this.wideBreakpoint = 1180,
    this.mediumBreakpoint = 820,
    this.stackedRowBreakpoint = 640,
  });

  /// Custom title-bar minimum height.
  final double titleBarHeight;

  /// Page-header height.
  final double pageHeaderHeight;

  /// Pane-header height.
  final double paneHeaderHeight;

  /// macOS traffic-light reserved width.
  final double macOSTrafficLightGutter;

  /// Toolbar minimum height.
  final double toolbarHeight;

  /// Per-side vertical padding for regular controls.
  final double controlPaddingYRegular;

  /// Per-side vertical padding for compact controls.
  final double controlPaddingYCompact;

  /// Minimum regular-control height.
  final double controlMinHeightRegular;

  /// Minimum compact-control height.
  final double controlMinHeightCompact;

  /// Compact data-row minimum height.
  final double compactRowHeight;

  /// Standard list-row minimum height.
  final double listRowHeight;

  /// Settings-row minimum height.
  final double settingsRowMinHeight;

  /// Dense key/value label width.
  final double keyValueLabelWidth;

  /// WCAG 2.2 AA interactive-target floor.
  final double minimumInteractiveTarget;

  /// Preferred VGV interactive-target size.
  final double preferredInteractiveTarget;

  /// Dense desktop icon-button hit size.
  final double iconButtonHitSize;

  /// Switch track width.
  final double switchTrackWidth;

  /// Switch track height.
  final double switchTrackHeight;

  /// Switch thumb size.
  final double switchThumbSize;

  /// Switch track inset.
  final double switchTrackPadding;

  /// Inline message-thumbnail size.
  final double messageThumbnailSize;

  /// Activity-rail width.
  final double activityRailWidth;

  /// Activity-rail icon size.
  final double activityRailIconSize;

  /// Fixed navigation-pane width.
  final double navigationPaneWidth;

  /// Default resizable side-pane width.
  final double sidePaneDefaultWidth;

  /// Minimum resizable side-pane width.
  final double sidePaneMinWidth;

  /// Maximum resizable side-pane width.
  final double sidePaneMaxWidth;

  /// Default inspector width.
  final double inspectorPaneWidth;

  /// Minimum retained projects-pane height.
  final double projectsPaneMinHeight;

  /// Readable-content maximum width.
  final double contentMaxWidth;

  /// Settings-content maximum width.
  final double settingsContentMaxWidth;

  /// Analytics-content maximum width.
  final double analyticsContentMaxWidth;

  /// Minimum central-editor width.
  final double mainEditorMinWidth;

  /// Metric-bar equal-width breakpoint.
  final double metricBarEqualWidthBreakpoint;

  /// Metric-bar item width below its breakpoint.
  final double metricBarItemWidth;

  /// Metric-bar divider height.
  final double metricBarDividerHeight;

  /// Three-column workbench breakpoint.
  final double wideBreakpoint;

  /// Two-column workbench breakpoint.
  final double mediumBreakpoint;

  /// Row-to-column breakpoint.
  final double stackedRowBreakpoint;

  /// Returns vertical padding for [size].
  double controlPaddingYFor(AppControlSize size) => switch (size) {
    AppControlSize.compact => controlPaddingYCompact,
    AppControlSize.regular => controlPaddingYRegular,
  };

  /// Returns minimum control height for [size].
  double controlMinHeightFor(AppControlSize size) => switch (size) {
    AppControlSize.compact => controlMinHeightCompact,
    AppControlSize.regular => controlMinHeightRegular,
  };

  /// Returns a square icon box aligned to [textStyle]'s line box.
  double controlIconBoxFor(TextStyle textStyle) {
    final fontSize = textStyle.fontSize ?? 0;
    return (fontSize * (textStyle.height ?? 1)).roundToDouble();
  }

  /// Estimates the natural outer height of a control.
  double controlNaturalHeightFor(
    TextStyle textStyle, {
    required AppControlSize size,
  }) {
    return math.max(
      controlMinHeightFor(size),
      2 * controlPaddingYFor(size) + controlIconBoxFor(textStyle),
    );
  }

  @override
  AppMetrics copyWith({
    double? titleBarHeight,
    double? pageHeaderHeight,
    double? paneHeaderHeight,
    double? macOSTrafficLightGutter,
    double? toolbarHeight,
    double? controlPaddingYRegular,
    double? controlPaddingYCompact,
    double? controlMinHeightRegular,
    double? controlMinHeightCompact,
    double? compactRowHeight,
    double? listRowHeight,
    double? settingsRowMinHeight,
    double? keyValueLabelWidth,
    double? minimumInteractiveTarget,
    double? preferredInteractiveTarget,
    double? iconButtonHitSize,
    double? switchTrackWidth,
    double? switchTrackHeight,
    double? switchThumbSize,
    double? switchTrackPadding,
    double? messageThumbnailSize,
    double? activityRailWidth,
    double? activityRailIconSize,
    double? navigationPaneWidth,
    double? sidePaneDefaultWidth,
    double? sidePaneMinWidth,
    double? sidePaneMaxWidth,
    double? inspectorPaneWidth,
    double? projectsPaneMinHeight,
    double? contentMaxWidth,
    double? settingsContentMaxWidth,
    double? analyticsContentMaxWidth,
    double? mainEditorMinWidth,
    double? metricBarEqualWidthBreakpoint,
    double? metricBarItemWidth,
    double? metricBarDividerHeight,
    double? wideBreakpoint,
    double? mediumBreakpoint,
    double? stackedRowBreakpoint,
  }) {
    return AppMetrics(
      titleBarHeight: titleBarHeight ?? this.titleBarHeight,
      pageHeaderHeight: pageHeaderHeight ?? this.pageHeaderHeight,
      paneHeaderHeight: paneHeaderHeight ?? this.paneHeaderHeight,
      macOSTrafficLightGutter:
          macOSTrafficLightGutter ?? this.macOSTrafficLightGutter,
      toolbarHeight: toolbarHeight ?? this.toolbarHeight,
      controlPaddingYRegular:
          controlPaddingYRegular ?? this.controlPaddingYRegular,
      controlPaddingYCompact:
          controlPaddingYCompact ?? this.controlPaddingYCompact,
      controlMinHeightRegular:
          controlMinHeightRegular ?? this.controlMinHeightRegular,
      controlMinHeightCompact:
          controlMinHeightCompact ?? this.controlMinHeightCompact,
      compactRowHeight: compactRowHeight ?? this.compactRowHeight,
      listRowHeight: listRowHeight ?? this.listRowHeight,
      settingsRowMinHeight: settingsRowMinHeight ?? this.settingsRowMinHeight,
      keyValueLabelWidth: keyValueLabelWidth ?? this.keyValueLabelWidth,
      minimumInteractiveTarget:
          minimumInteractiveTarget ?? this.minimumInteractiveTarget,
      preferredInteractiveTarget:
          preferredInteractiveTarget ?? this.preferredInteractiveTarget,
      iconButtonHitSize: iconButtonHitSize ?? this.iconButtonHitSize,
      switchTrackWidth: switchTrackWidth ?? this.switchTrackWidth,
      switchTrackHeight: switchTrackHeight ?? this.switchTrackHeight,
      switchThumbSize: switchThumbSize ?? this.switchThumbSize,
      switchTrackPadding: switchTrackPadding ?? this.switchTrackPadding,
      messageThumbnailSize: messageThumbnailSize ?? this.messageThumbnailSize,
      activityRailWidth: activityRailWidth ?? this.activityRailWidth,
      activityRailIconSize: activityRailIconSize ?? this.activityRailIconSize,
      navigationPaneWidth: navigationPaneWidth ?? this.navigationPaneWidth,
      sidePaneDefaultWidth: sidePaneDefaultWidth ?? this.sidePaneDefaultWidth,
      sidePaneMinWidth: sidePaneMinWidth ?? this.sidePaneMinWidth,
      sidePaneMaxWidth: sidePaneMaxWidth ?? this.sidePaneMaxWidth,
      inspectorPaneWidth: inspectorPaneWidth ?? this.inspectorPaneWidth,
      projectsPaneMinHeight:
          projectsPaneMinHeight ?? this.projectsPaneMinHeight,
      contentMaxWidth: contentMaxWidth ?? this.contentMaxWidth,
      settingsContentMaxWidth:
          settingsContentMaxWidth ?? this.settingsContentMaxWidth,
      analyticsContentMaxWidth:
          analyticsContentMaxWidth ?? this.analyticsContentMaxWidth,
      mainEditorMinWidth: mainEditorMinWidth ?? this.mainEditorMinWidth,
      metricBarEqualWidthBreakpoint:
          metricBarEqualWidthBreakpoint ?? this.metricBarEqualWidthBreakpoint,
      metricBarItemWidth: metricBarItemWidth ?? this.metricBarItemWidth,
      metricBarDividerHeight:
          metricBarDividerHeight ?? this.metricBarDividerHeight,
      wideBreakpoint: wideBreakpoint ?? this.wideBreakpoint,
      mediumBreakpoint: mediumBreakpoint ?? this.mediumBreakpoint,
      stackedRowBreakpoint: stackedRowBreakpoint ?? this.stackedRowBreakpoint,
    );
  }

  @override
  AppMetrics lerp(covariant AppMetrics? other, double t) {
    if (other == null) return this;
    return AppMetrics(
      titleBarHeight: lerpDouble(titleBarHeight, other.titleBarHeight, t)!,
      pageHeaderHeight: lerpDouble(
        pageHeaderHeight,
        other.pageHeaderHeight,
        t,
      )!,
      paneHeaderHeight: lerpDouble(
        paneHeaderHeight,
        other.paneHeaderHeight,
        t,
      )!,
      macOSTrafficLightGutter: lerpDouble(
        macOSTrafficLightGutter,
        other.macOSTrafficLightGutter,
        t,
      )!,
      toolbarHeight: lerpDouble(toolbarHeight, other.toolbarHeight, t)!,
      controlPaddingYRegular: lerpDouble(
        controlPaddingYRegular,
        other.controlPaddingYRegular,
        t,
      )!,
      controlPaddingYCompact: lerpDouble(
        controlPaddingYCompact,
        other.controlPaddingYCompact,
        t,
      )!,
      controlMinHeightRegular: lerpDouble(
        controlMinHeightRegular,
        other.controlMinHeightRegular,
        t,
      )!,
      controlMinHeightCompact: lerpDouble(
        controlMinHeightCompact,
        other.controlMinHeightCompact,
        t,
      )!,
      compactRowHeight: lerpDouble(
        compactRowHeight,
        other.compactRowHeight,
        t,
      )!,
      listRowHeight: lerpDouble(listRowHeight, other.listRowHeight, t)!,
      settingsRowMinHeight: lerpDouble(
        settingsRowMinHeight,
        other.settingsRowMinHeight,
        t,
      )!,
      keyValueLabelWidth: lerpDouble(
        keyValueLabelWidth,
        other.keyValueLabelWidth,
        t,
      )!,
      minimumInteractiveTarget: lerpDouble(
        minimumInteractiveTarget,
        other.minimumInteractiveTarget,
        t,
      )!,
      preferredInteractiveTarget: lerpDouble(
        preferredInteractiveTarget,
        other.preferredInteractiveTarget,
        t,
      )!,
      iconButtonHitSize: lerpDouble(
        iconButtonHitSize,
        other.iconButtonHitSize,
        t,
      )!,
      switchTrackWidth: lerpDouble(
        switchTrackWidth,
        other.switchTrackWidth,
        t,
      )!,
      switchTrackHeight: lerpDouble(
        switchTrackHeight,
        other.switchTrackHeight,
        t,
      )!,
      switchThumbSize: lerpDouble(switchThumbSize, other.switchThumbSize, t)!,
      switchTrackPadding: lerpDouble(
        switchTrackPadding,
        other.switchTrackPadding,
        t,
      )!,
      messageThumbnailSize: lerpDouble(
        messageThumbnailSize,
        other.messageThumbnailSize,
        t,
      )!,
      activityRailWidth: lerpDouble(
        activityRailWidth,
        other.activityRailWidth,
        t,
      )!,
      activityRailIconSize: lerpDouble(
        activityRailIconSize,
        other.activityRailIconSize,
        t,
      )!,
      navigationPaneWidth: lerpDouble(
        navigationPaneWidth,
        other.navigationPaneWidth,
        t,
      )!,
      sidePaneDefaultWidth: lerpDouble(
        sidePaneDefaultWidth,
        other.sidePaneDefaultWidth,
        t,
      )!,
      sidePaneMinWidth: lerpDouble(
        sidePaneMinWidth,
        other.sidePaneMinWidth,
        t,
      )!,
      sidePaneMaxWidth: lerpDouble(
        sidePaneMaxWidth,
        other.sidePaneMaxWidth,
        t,
      )!,
      inspectorPaneWidth: lerpDouble(
        inspectorPaneWidth,
        other.inspectorPaneWidth,
        t,
      )!,
      projectsPaneMinHeight: lerpDouble(
        projectsPaneMinHeight,
        other.projectsPaneMinHeight,
        t,
      )!,
      contentMaxWidth: lerpDouble(contentMaxWidth, other.contentMaxWidth, t)!,
      settingsContentMaxWidth: lerpDouble(
        settingsContentMaxWidth,
        other.settingsContentMaxWidth,
        t,
      )!,
      analyticsContentMaxWidth: lerpDouble(
        analyticsContentMaxWidth,
        other.analyticsContentMaxWidth,
        t,
      )!,
      mainEditorMinWidth: lerpDouble(
        mainEditorMinWidth,
        other.mainEditorMinWidth,
        t,
      )!,
      metricBarEqualWidthBreakpoint: lerpDouble(
        metricBarEqualWidthBreakpoint,
        other.metricBarEqualWidthBreakpoint,
        t,
      )!,
      metricBarItemWidth: lerpDouble(
        metricBarItemWidth,
        other.metricBarItemWidth,
        t,
      )!,
      metricBarDividerHeight: lerpDouble(
        metricBarDividerHeight,
        other.metricBarDividerHeight,
        t,
      )!,
      wideBreakpoint: lerpDouble(wideBreakpoint, other.wideBreakpoint, t)!,
      mediumBreakpoint: lerpDouble(
        mediumBreakpoint,
        other.mediumBreakpoint,
        t,
      )!,
      stackedRowBreakpoint: lerpDouble(
        stackedRowBreakpoint,
        other.stackedRowBreakpoint,
        t,
      )!,
    );
  }
}

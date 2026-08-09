import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/usage_statistics/application/usage_statistics_controller.dart';
import 'package:zeta/src/features/usage_statistics/domain/usage_statistics_models.dart';
import 'package:zeta/src/features/usage_statistics/presentation/usage_statistics_formatters.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 使用统计条件栏的时间范围触发器：点击后弹出「快捷项 + 日期区间」Popover。
class UsageTimeRangeFilter extends StatefulWidget {
  const UsageTimeRangeFilter({
    required this.controller,
    required this.width,
    super.key,
  });

  final UsageStatisticsController controller;
  final double width;

  @override
  State<UsageTimeRangeFilter> createState() => _UsageTimeRangeFilterState();
}

class _UsageTimeRangeFilterState extends State<UsageTimeRangeFilter> {
  IdePopoverHandle<void>? _popover;

  @override
  void dispose() {
    _popover?.dismiss();
    _popover = null;
    super.dispose();
  }

  String get _triggerLabel {
    final controller = widget.controller;
    if (controller.timePreset == UsageTimeRangePreset.custom) {
      final window = controller.window;
      final endInclusive = window.endExclusive.subtract(
        const Duration(milliseconds: 1),
      );
      return formatUsageDateRange(window.start, endInclusive);
    }
    return controller.timePreset.compactLabel;
  }

  Future<void> _togglePopover() async {
    final existing = _popover;
    if (existing != null && !existing.isCompleted) {
      existing.dismiss();
      return;
    }

    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : IdeMotion.durationFast;
    final handle = showIdePopover<void>(
      context: context,
      alignment: Alignment.topLeft,
      anchorAlignment: Alignment.bottomLeft,
      widthConstraint: IdePopoverConstraint.intrinsic,
      heightConstraint: IdePopoverConstraint.intrinsic,
      offset: const Offset(0, IdeSpacing.space6),
      margin: const EdgeInsets.all(IdeSpacing.space12),
      showDuration: duration,
      dismissDuration: duration,
      key: const ValueKey('usage-time-range-popover'),
      builder: (popoverContext) => _UsageTimeRangePopover(
        controller: widget.controller,
        onPresetSelected: (preset) {
          unawaited(widget.controller.selectTimePreset(preset));
          sf.closeOverlay(popoverContext);
        },
        onCustomRangeSelected: (start, endInclusive) {
          unawaited(widget.controller.selectCustomRange(start, endInclusive));
          sf.closeOverlay(popoverContext);
        },
      ),
    );
    _popover = handle;
    setState(() {});
    await handle.future;
    if (mounted && identical(_popover, handle)) {
      setState(() {
        _popover = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOpen = _popover != null && !_popover!.isCompleted;

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        return IdeButton.toolbar(
          key: const ValueKey('usage-time-range-filter'),
          label: _triggerLabel,
          width: widget.width,
          onPressed: _togglePopover,
          leadingIcon: Icons.calendar_month_rounded,
          trailingIcon: isOpen
              ? Icons.keyboard_arrow_up_rounded
              : Icons.keyboard_arrow_down_rounded,
        );
      },
    );
  }
}

class _UsageTimeRangePopover extends StatefulWidget {
  const _UsageTimeRangePopover({
    required this.controller,
    required this.onPresetSelected,
    required this.onCustomRangeSelected,
  });

  final UsageStatisticsController controller;
  final ValueChanged<UsageTimeRangePreset> onPresetSelected;
  final void Function(DateTime start, DateTime endInclusive)
  onCustomRangeSelected;

  @override
  State<_UsageTimeRangePopover> createState() => _UsageTimeRangePopoverState();
}

class _UsageTimeRangePopoverState extends State<_UsageTimeRangePopover> {
  late sf.CalendarValue? _calendarValue;
  bool _awaitingRangeEnd = false;

  @override
  void initState() {
    super.initState();
    _calendarValue = _calendarValueFromController();
  }

  sf.CalendarValue? _calendarValueFromController() {
    final window = widget.controller.window;
    final start = DateTime(
      window.start.year,
      window.start.month,
      window.start.day,
    );
    final endInclusive = window.endExclusive.subtract(
      const Duration(milliseconds: 1),
    );
    final end = DateTime(
      endInclusive.year,
      endInclusive.month,
      endInclusive.day,
    );
    if (start.year == end.year &&
        start.month == end.month &&
        start.day == end.day) {
      return sf.CalendarValue.single(start);
    }
    return sf.CalendarValue.range(start, end);
  }

  DateTime get _today {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  sf.DateState _dateState(DateTime date) {
    final day = DateTime(date.year, date.month, date.day);
    if (day.isAfter(_today)) {
      return sf.DateState.disabled;
    }
    return sf.DateState.enabled;
  }

  void _onCalendarChanged(sf.CalendarValue? value) {
    setState(() {
      _calendarValue = value;
    });
    if (value == null) {
      _awaitingRangeEnd = false;
      return;
    }
    // 第一次点击仅标记起点，等第二次完成区间后再提交。
    if (value is sf.SingleCalendarValue) {
      _awaitingRangeEnd = true;
      return;
    }
    if (value is sf.RangeCalendarValue) {
      _awaitingRangeEnd = false;
      final start = DateTime(
        value.start.year,
        value.start.month,
        value.start.day,
      );
      final end = DateTime(value.end.year, value.end.month, value.end.day);
      widget.onCustomRangeSelected(start, end);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final brightness = sf.Theme.of(context).brightness;
    final selectedPreset = widget.controller.timePreset;
    final mediaWidth = MediaQuery.sizeOf(context).width;
    final narrow = mediaWidth < 640;
    // 窄屏只显示单月，宽屏用双月 range 视图。
    final calendarViewMode = narrow
        ? sf.CalendarSelectionMode.single
        : sf.CalendarSelectionMode.range;

    final shortcuts = Column(
      key: const ValueKey('usage-time-range-shortcuts'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            IdeSpacing.space8,
            IdeSpacing.space4,
            IdeSpacing.space8,
            IdeSpacing.space6,
          ),
          child: Text(
            '快捷',
            style: textStyles.caption.copyWith(color: colors.textSecondary),
          ),
        ),
        for (final preset in kUsageTimeRangeQuickOptions)
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space4,
              vertical: IdeSpacing.space2,
            ),
            child: PaneInteractiveSurface(
              key: ValueKey<String>('usage-time-range-preset-${preset.name}'),
              semanticLabel: preset.label,
              selected:
                  selectedPreset == preset &&
                  !_awaitingRangeEnd &&
                  selectedPreset != UsageTimeRangePreset.custom,
              onPressed: () => widget.onPresetSelected(preset),
              padding: const EdgeInsets.symmetric(
                horizontal: IdeSpacing.space8,
                vertical: IdeSpacing.space6,
              ),
              alignment: Alignment.centerLeft,
              child: Text(
                preset.compactLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall.copyWith(
                  color: selectedPreset == preset && !_awaitingRangeEnd
                      ? colors.accent
                      : colors.textPrimary,
                  fontWeight: selectedPreset == preset && !_awaitingRangeEnd
                      ? FontWeight.w600
                      : FontWeight.w500,
                ),
              ),
            ),
          ),
      ],
    );

    final calendar = sf.DatePickerDialog(
      key: const ValueKey('usage-time-range-calendar'),
      initialViewType: sf.CalendarViewType.date,
      initialView: _calendarValue?.view ?? sf.CalendarView.now(),
      selectionMode: sf.CalendarSelectionMode.range,
      viewMode: calendarViewMode,
      initialValue: _calendarValue,
      stateBuilder: _dateState,
      onChanged: _onCalendarChanged,
    );

    final body = narrow
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: IdeSpacing.space8,
                  horizontal: IdeSpacing.space4,
                ),
                child: shortcuts,
              ),
              const IdeRowDivider(),
              Padding(padding: IdeSpacing.all12, child: calendar),
            ],
          )
        : IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 112,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: IdeSpacing.space8,
                      horizontal: IdeSpacing.space4,
                    ),
                    child: shortcuts,
                  ),
                ),
                const IdeColumnDivider(),
                Padding(padding: IdeSpacing.all12, child: calendar),
              ],
            ),
          );

    return PanelCard(
      color: colors.popoverSurface,
      borderRadius: IdeRadius.allLarge,
      boxShadow: IdeEffects.overlayShadow(brightness),
      child: body,
    );
  }
}

import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Immutable option for one [IdeTabs] destination.
@immutable
class IdeTabItem<T> {
  /// Creates a tab option with caller-supplied copy.
  const IdeTabItem({
    required this.value,
    required this.label,
    this.key,
    this.leadingIcon,
    this.semanticLabel,
    this.loading = false,
    this.loadingSemanticLabel,
  }) : assert(
         !loading || loadingSemanticLabel != null,
         'A loading tab requires loadingSemanticLabel.',
       );

  /// Domain value selected by this option.
  final T value;

  /// Visible short label.
  final String label;

  /// Stable element key.
  final Key? key;

  /// Optional leading glyph.
  final IconData? leadingIcon;

  /// Optional accessible name while idle.
  final String? semanticLabel;

  /// Whether the label shows a loading pulse.
  final bool loading;

  /// Required caller-supplied accessible name while [loading].
  final String? loadingSemanticLabel;
}

/// A controlled compact single-selection desktop tab group.
class IdeTabs<T> extends StatelessWidget {
  /// Creates a tab group.
  const IdeTabs({
    required this.value,
    required this.items,
    required this.onChanged,
    this.expand = false,
    this.controlSize = AppControlSize.regular,
    this.semanticLabel,
    this.scrollContentAlignment = AlignmentDirectional.centerStart,
    super.key,
  }) : assert(items.length > 0, 'IdeTabs requires at least one item.');

  /// Current domain value.
  final T value;

  /// Available destinations.
  final List<IdeTabItem<T>> items;

  /// Reports user selection.
  final ValueChanged<T> onChanged;

  /// Whether options share all available width.
  final bool expand;

  /// Control density.
  final AppControlSize controlSize;

  /// Optional accessible group name.
  final String? semanticLabel;

  /// Alignment when scrollable content is shorter than its viewport.
  final AlignmentGeometry scrollContentAlignment;

  @override
  Widget build(BuildContext context) {
    final selectedIndex = items.indexWhere((item) => item.value == value);
    if (selectedIndex < 0) {
      throw FlutterError('IdeTabs.value must match one item.');
    }

    final colors = context.appColors;
    final spacing = context.appSpacing;
    const containerPaddingY = 4.0;
    final tabPaddingY = math.max<double>(
      0,
      context.appMetrics.controlPaddingYFor(controlSize) - containerPaddingY,
    );
    final tabs = DecoratedBox(
      decoration: BoxDecoration(
        border: Border.all(color: colors.borderSubtle),
        borderRadius: context.appRadii.allMedium,
      ),
      child: sf.ComponentTheme(
        data: sf.TabsTheme(
          containerPadding: const EdgeInsets.all(containerPaddingY),
          tabPadding: EdgeInsets.symmetric(
            horizontal: spacing.sm,
            vertical: tabPaddingY,
          ),
          backgroundColor: colors.surfaceElevated,
          borderRadius: context.appRadii.allSmall,
        ),
        child: sf.Tabs(
          index: selectedIndex,
          expand: expand,
          onChanged: (index) => onChanged(items[index].value),
          children: <sf.TabChild>[
            for (var index = 0; index < items.length; index++)
              sf.TabItem(
                key: items[index].key,
                child: _IdeTabContent(
                  label: items[index].label,
                  leadingIcon: items[index].leadingIcon,
                  selected: index == selectedIndex,
                  loading: items[index].loading,
                  semanticLabel: items[index].loading
                      ? items[index].loadingSemanticLabel
                      : items[index].semanticLabel ?? items[index].label,
                ),
              ),
          ],
        ),
      ),
    );

    return Semantics(
      container: true,
      explicitChildNodes: true,
      label: semanticLabel,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.appMetrics.controlMinHeightFor(controlSize),
        ),
        child: expand
            ? tabs
            : LayoutBuilder(
                builder: (context, constraints) {
                  final minWidth = constraints.hasBoundedWidth
                      ? constraints.maxWidth
                      : 0.0;
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: ConstrainedBox(
                      constraints: BoxConstraints(minWidth: minWidth),
                      child: Align(
                        alignment: scrollContentAlignment,
                        heightFactor: 1,
                        child: tabs,
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}

class _IdeTabContent extends StatelessWidget {
  const _IdeTabContent({
    required this.label,
    required this.selected,
    this.leadingIcon,
    this.semanticLabel,
    this.loading = false,
  });

  final String label;
  final IconData? leadingIcon;
  final bool selected;
  final String? semanticLabel;
  final bool loading;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final foreground = selected ? colors.textPrimary : colors.textSecondary;
    final content = AnimatedDefaultTextStyle(
      duration: context.appMotion.resolveFor(
        context,
        context.appMotion.normal,
      ),
      curve: context.appMotion.defaultCurve,
      style: context.appTypography.bodySmall.copyWith(
        color: foreground,
        fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          if (leadingIcon case final icon?) ...<Widget>[
            IdeIconBox(icon, color: foreground),
            SizedBox(width: context.appSpacing.xxs),
          ],
          IdePulsingLabel(label: label, active: loading),
        ],
      ),
    );
    return Semantics(
      selected: selected,
      label: semanticLabel,
      excludeSemantics: true,
      child: AnimatedOpacity(
        opacity: selected ? 1 : 0.82,
        duration: context.appMotion.resolveFor(
          context,
          context.appMotion.normal,
        ),
        curve: context.appMotion.defaultCurve,
        child: content,
      ),
    );
  }
}

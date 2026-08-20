import 'package:app_ui/app_ui.dart';

/// A project-level scrollbar bound to the virtual list's real scroll metrics.
class IdeVirtualScrollbar extends StatelessWidget {
  /// Creates a virtual-list scrollbar.
  const IdeVirtualScrollbar({
    required this.controller,
    required this.child,
    required this.semanticLabel,
    this.thickness = 8,
    this.minThumbLength = 32,
    this.padding = EdgeInsets.zero,
    super.key,
  }) : assert(semanticLabel != '', 'semanticLabel must not be empty');

  /// Controller shared with the wrapped scroll view.
  final ScrollController controller;

  /// Scrollable content with its automatic scrollbar disabled by this widget.
  final Widget child;

  /// Localized accessible name for the scrollbar.
  final String semanticLabel;

  /// Visible thumb thickness in logical pixels.
  final double thickness;

  /// Minimum thumb length.
  final double minThumbLength;

  /// Scrollbar inset.
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final thumbColor = context.appColors.textTertiary.withValues(alpha: 0.22);
    return Semantics(
      container: true,
      label: semanticLabel,
      child: RawScrollbar(
        controller: controller,
        thumbVisibility: true,
        trackVisibility: false,
        interactive: true,
        thickness: thickness,
        radius: Radius.circular(context.appRadii.small),
        minThumbLength: minThumbLength,
        padding: padding,
        thumbColor: thumbColor,
        trackColor: Colors.transparent,
        trackBorderColor: Colors.transparent,
        child: ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            scrollbars: false,
          ),
          child: child,
        ),
      ),
    );
  }
}

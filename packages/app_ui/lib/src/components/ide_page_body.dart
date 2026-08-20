import 'package:app_ui/app_ui.dart';

/// Provides responsive page insets, scrolling, and readable content width.
class IdePageBody extends StatelessWidget {
  /// Creates a workbench page body.
  const IdePageBody({required this.child, this.maxWidth, super.key});

  /// Page content.
  final Widget child;

  /// Optional readable-width override.
  final double? maxWidth;

  @override
  Widget build(BuildContext context) {
    final metrics = context.appMetrics;
    final spacing = context.appSpacing;
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < metrics.mediumBreakpoint;
        return SingleChildScrollView(
          padding: compact ? spacing.pagePaddingCompact : spacing.pagePadding,
          child: Align(
            alignment: AlignmentDirectional.topCenter,
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxWidth ?? metrics.settingsContentMaxWidth,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}

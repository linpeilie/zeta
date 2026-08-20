import 'package:app_ui/app_ui.dart';

/// A continuous workbench toolbar for search, filtering, and compact actions.
class IdeToolbar extends StatelessWidget {
  /// Creates a toolbar.
  const IdeToolbar({required this.child, super.key});

  /// Toolbar content.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        border: Border.symmetric(
          horizontal: BorderSide(color: colors.borderSubtle),
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          minHeight: context.appMetrics.toolbarHeight,
        ),
        child: Padding(
          padding: context.appSpacing.toolbarPadding,
          child: child,
        ),
      ),
    );
  }
}

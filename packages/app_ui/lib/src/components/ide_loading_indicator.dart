import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// A compact linear loading indicator with caller-supplied copy.
class IdeLoadingIndicator extends StatelessWidget {
  /// Creates a loading indicator.
  const IdeLoadingIndicator({
    required this.semanticsLabel,
    this.width = 20,
    this.height = 10,
    this.barHeight = 3,
    super.key,
  });

  /// Indicator width.
  final double width;

  /// Indicator hit-box height.
  final double height;

  /// Painted bar height.
  final double barHeight;

  /// Live-region loading announcement.
  final String semanticsLabel;

  @override
  Widget build(BuildContext context) {
    final theme = sf.Theme.of(context);
    return Semantics(
      label: semanticsLabel,
      liveRegion: true,
      child: SizedBox(
        width: width,
        height: height,
        child: Center(
          child: sf.ComponentTheme<sf.ProgressTheme>(
            data: sf.ProgressTheme(
              minHeight: barHeight,
              borderRadius: BorderRadius.circular(barHeight),
              color: theme.colorScheme.primary,
              backgroundColor: theme.colorScheme.secondary.withValues(
                alpha: 0.78,
              ),
            ),
            child: const sf.Progress(),
          ),
        ),
      ),
    );
  }
}

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// A decorator that wraps every use case with a consistent background.
class UseCaseDecorator extends StatelessWidget {
  /// Creates a [UseCaseDecorator].
  const UseCaseDecorator({required this.child, super.key});

  /// The use case widget to wrap.
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final shadcnTheme = Theme.of(context).brightness == Brightness.dark
        ? AppTheme.shadcnDark
        : AppTheme.shadcnLight;
    return sf.Theme(
      data: shadcnTheme,
      child: ColoredBox(
        color: colorScheme.surfaceContainerHighest,
        child: SizedBox.expand(child: Material(child: child)),
      ),
    );
  }
}

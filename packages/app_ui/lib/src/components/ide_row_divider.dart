import 'package:app_ui/app_ui.dart';

/// A one-pixel horizontal divider with directional insets.
class IdeRowDivider extends StatelessWidget {
  /// Creates a row divider.
  const IdeRowDivider({this.indent = 0, this.endIndent = 0, super.key});

  /// Leading inset in the current text direction.
  final double indent;

  /// Trailing inset in the current text direction.
  final double endIndent;

  @override
  Widget build(BuildContext context) {
    final line = ExcludeSemantics(
      child: ColoredBox(
        color: context.appColors.borderSubtle,
        child: const SizedBox(height: 1),
      ),
    );
    if (indent == 0 && endIndent == 0) return line;
    return Padding(
      padding: EdgeInsetsDirectional.only(start: indent, end: endIndent),
      child: line,
    );
  }
}

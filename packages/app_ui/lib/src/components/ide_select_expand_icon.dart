import 'package:app_ui/app_ui.dart';

/// A select expand glyph constrained to the active control line box.
class IdeSelectExpandIcon extends StatelessWidget {
  /// Creates an expand glyph.
  const IdeSelectExpandIcon({this.color, super.key});

  /// Optional glyph color.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return IdeIconBox(Icons.unfold_more, color: color);
  }
}

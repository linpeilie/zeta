import 'package:app_ui/app_ui.dart';

/// A one-pixel vertical divider between adjacent columns.
class IdeColumnDivider extends StatelessWidget {
  /// Creates a column divider.
  const IdeColumnDivider({super.key});

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: ColoredBox(
        color: context.appColors.borderSubtle,
        child: const SizedBox(width: 1),
      ),
    );
  }
}

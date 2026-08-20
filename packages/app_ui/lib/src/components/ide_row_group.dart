import 'package:app_ui/app_ui.dart';

/// Groups flat rows beneath a compact semantic heading.
class IdeRowGroup extends StatelessWidget {
  /// Creates a row group.
  const IdeRowGroup({
    required this.title,
    required this.children,
    this.dividers = true,
    super.key,
  });

  /// Group heading.
  final String title;

  /// Rows in display order.
  final List<Widget> children;

  /// Whether to place dividers between rows.
  final bool dividers;

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Padding(
          padding: spacing.settingsGroupTitlePadding,
          child: Semantics(
            header: true,
            child: Text(title, style: context.appTypography.groupTitle),
          ),
        ),
        for (var index = 0; index < children.length; index++) ...<Widget>[
          if (dividers && index > 0) const IdeRowDivider(),
          children[index],
        ],
      ],
    );
  }
}

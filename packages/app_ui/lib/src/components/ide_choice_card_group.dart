import 'package:app_ui/app_ui.dart';

/// Immutable description of one [IdeChoiceCardGroup] option.
class IdeChoiceCardOption<T> {
  /// Creates a choice-card option.
  const IdeChoiceCardOption({
    required this.value,
    required this.label,
    required this.icon,
    this.semanticLabel,
    this.key,
  });

  /// Domain value.
  final T value;

  /// Visible copy.
  final String label;

  /// Choice icon.
  final IconData icon;

  /// Optional accessible name.
  final String? semanticLabel;

  /// Stable widget key.
  final Key? key;
}

/// A wrapping, equal-width single-choice card group.
class IdeChoiceCardGroup<T> extends StatelessWidget {
  /// Creates a choice-card group.
  const IdeChoiceCardGroup({
    required this.options,
    required this.value,
    required this.onChanged,
    this.cardWidth = 150,
    this.enabled = true,
    super.key,
  });

  /// Available options.
  final List<IdeChoiceCardOption<T>> options;

  /// Current value.
  final T value;

  /// Value-change callback.
  final ValueChanged<T> onChanged;

  /// Equal card width.
  final double cardWidth;

  /// Whether all choices are enabled.
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: context.appSpacing.xs,
      runSpacing: context.appSpacing.xs,
      children: <Widget>[
        for (final option in options)
          SizedBox(
            width: cardWidth,
            child: IdeChoiceCard(
              key: option.key,
              label: option.label,
              icon: option.icon,
              selected: option.value == value,
              enabled: enabled,
              semanticLabel: option.semanticLabel,
              onPressed: () => onChanged(option.value),
            ),
          ),
      ],
    );
  }
}

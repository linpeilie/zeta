import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Immutable value and caller-supplied copy for one [IdeSelect] option.
@immutable
class IdeSelectOption<T> {
  /// Creates an option.
  const IdeSelectOption(
    this.value,
    this.label, {
    this.enabled = true,
    this.key,
  });

  /// Domain value.
  final T value;

  /// Visible option copy.
  final String label;

  /// Whether the option is selectable.
  final bool enabled;

  /// Stable widget key.
  final Key? key;
}

/// Popup width policies for [IdeSelect].
enum IdeSelectPopupWidthPolicy {
  /// Match the trigger width.
  matchTrigger,

  /// Fit option content.
  fitContent,
}

/// A controlled compact shadcn select.
class IdeSelect<T> extends StatelessWidget {
  /// Creates a select.
  const IdeSelect({
    required this.value,
    required this.options,
    required this.onChanged,
    this.width,
    this.controlSize = AppControlSize.regular,
    this.popupMaxHeight = 320,
    this.popupMinWidth,
    this.popupWidthPolicy = IdeSelectPopupWidthPolicy.matchTrigger,
    this.enabled = true,
    this.placeholder,
    super.key,
  }) : assert(
         popupMinWidth == null || popupMinWidth >= 0,
         'popupMinWidth must be non-negative.',
       );

  /// Current value.
  final T value;

  /// Available options.
  final List<IdeSelectOption<T>> options;

  /// Value-change callback; null disables the select.
  final ValueChanged<T?>? onChanged;

  /// Optional trigger width.
  final double? width;

  /// Control density.
  final AppControlSize controlSize;

  /// Popup maximum height.
  final double popupMaxHeight;

  /// Popup minimum width.
  final double? popupMinWidth;

  /// Popup width policy.
  final IdeSelectPopupWidthPolicy popupWidthPolicy;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Optional copy used when no option matches.
  final String? placeholder;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final isEnabled = enabled && onChanged != null && options.isNotEmpty;
    final labelStyle = context.appTypography.bodySmall.copyWith(
      color: isEnabled ? colors.textPrimary : colors.textTertiary,
    );
    final selected =
        _findOption(value) ?? (options.isEmpty ? null : options.first);
    final minWidth = math.max(width ?? 0, popupMinWidth ?? 0);
    return sf.Select<T>(
      value: selected?.value ?? value,
      enabled: isEnabled,
      expandIcon: IdeSelectExpandIcon(
        color: isEnabled ? colors.textSecondary : colors.textTertiary,
      ),
      constraints: BoxConstraints(
        minWidth: width ?? 0,
        maxWidth: width ?? double.infinity,
        minHeight: context.appMetrics.controlMinHeightFor(controlSize),
      ),
      padding: EdgeInsets.symmetric(
        horizontal: context.appSpacing.xs,
        vertical: context.appMetrics.controlPaddingYFor(controlSize),
      ),
      popupConstraints: BoxConstraints(
        maxHeight: popupMaxHeight,
        minWidth: minWidth,
      ),
      popupWidthConstraint: switch (popupWidthPolicy) {
        IdeSelectPopupWidthPolicy.matchTrigger =>
          sf.PopoverConstraint.anchorFixedSize,
        IdeSelectPopupWidthPolicy.fitContent => sf.PopoverConstraint.intrinsic,
      },
      itemBuilder: (context, selectedValue) {
        final option = _findOption(selectedValue) ?? selected;
        return Text(
          option?.label ?? placeholder ?? '$selectedValue',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: labelStyle,
        );
      },
      onChanged: isEnabled ? onChanged : null,
      popup: sf.SelectPopup<T>.noVirtualization(
        items: sf.SelectItemList(
          children: <Widget>[
            for (final option in options)
              sf.SelectItemButton(
                key: option.key,
                value: option.value,
                enabled: option.enabled ? null : false,
                child: Text(
                  option.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: labelStyle.copyWith(
                    color: option.enabled
                        ? labelStyle.color
                        : colors.textTertiary,
                  ),
                ),
              ),
          ],
        ),
      ).call,
    );
  }

  IdeSelectOption<T>? _findOption(T candidate) {
    for (final option in options) {
      if (option.value == candidate) return option;
    }
    return null;
  }
}

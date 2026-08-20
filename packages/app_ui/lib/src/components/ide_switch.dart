import 'dart:math' as math;

import 'package:app_ui/app_ui.dart';
import 'package:flutter/services.dart';

/// A keyboard-operable square-thumb desktop switch.
class IdeSwitch extends StatefulWidget {
  /// Creates a switch.
  const IdeSwitch({
    required this.value,
    required this.onChanged,
    this.enabled = true,
    this.semanticLabel,
    super.key,
  });

  /// Current toggle value.
  final bool value;

  /// Value-change callback; null also disables the switch.
  final ValueChanged<bool>? onChanged;

  /// Whether interaction is enabled.
  final bool enabled;

  /// Optional accessible name.
  final String? semanticLabel;

  @override
  State<IdeSwitch> createState() => _IdeSwitchState();
}

class _IdeSwitchState extends State<IdeSwitch> {
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onChanged != null;

  void _toggle() {
    if (_enabled) widget.onChanged?.call(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final metrics = context.appMetrics;
    final motion = context.appMotion;
    final duration = motion.resolveFor(context, motion.fast);
    final trackColor = widget.value
        ? _enabled
              ? colors.accent
              : colors.primaryMuted
        : colors.controlSurface;
    final borderColor = widget.value
        ? null
        : _enabled
        ? colors.border
        : colors.borderSubtle;
    final thumbColor = widget.value
        ? colors.onAccent
        : _enabled
        ? colors.textTertiary
        : colors.border;
    final track = AnimatedContainer(
      duration: duration,
      curve: motion.defaultCurve,
      width: metrics.switchTrackWidth,
      height: metrics.switchTrackHeight,
      padding: EdgeInsets.all(metrics.switchTrackPadding),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: context.appRadii.allSmall,
        border: borderColor == null ? null : Border.all(color: borderColor),
        boxShadow: _focused && _enabled
            ? context.appEffects.focusRing(
                Theme.of(context).brightness,
                accent: colors.focusRing,
              )
            : const <BoxShadow>[],
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: motion.defaultCurve,
        alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: duration,
          curve: motion.defaultCurve,
          width: metrics.switchThumbSize,
          height: metrics.switchThumbSize,
          decoration: BoxDecoration(
            color: thumbColor,
            borderRadius: context.appRadii.allMicro,
          ),
        ),
      ),
    );

    return Semantics(
      toggled: widget.value,
      enabled: _enabled,
      label: widget.semanticLabel,
      excludeSemantics: widget.semanticLabel != null,
      child: FocusableActionDetector(
        enabled: _enabled,
        mouseCursor: _enabled
            ? SystemMouseCursors.click
            : SystemMouseCursors.forbidden,
        onShowFocusHighlight: (value) {
          if (value != _focused) setState(() => _focused = value);
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _toggle : null,
          child: SizedBox(
            width: math.max(
              metrics.switchTrackWidth,
              metrics.minimumInteractiveTarget,
            ),
            height: math.max(
              metrics.switchTrackHeight,
              metrics.minimumInteractiveTarget,
            ),
            child: Center(child: track),
          ),
        ),
      ),
    );
  }
}

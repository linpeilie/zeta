import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_colors.dart';
import 'ide_effects.dart';
import 'ide_metrics.dart';
import 'ide_motion.dart';

/// IDE 开关控件。
///
/// **为什么不用 `sf.Switch`**：它的滑块圆角写死为 `theme.radiusLg` 的全圆形，
/// `SwitchTheme` 只暴露轨道 `borderRadius`，无法把滑块收成方角。设计系统要求
/// 轨道（[IdeRadius.small]）与滑块（[IdeRadius.micro]）共用「小圆角」语言，
/// 并保持严格递减的圆角嵌套，因此在这里自绘。
///
/// 四种状态都必须可读：禁用态**不会**抹掉 on/off 的区别——设置页里
/// 「任务结束 / 需要确认」在主开关关闭时是禁用但保留各自开关值的。
class IdeSwitch extends StatefulWidget {
  const IdeSwitch({
    required this.value,
    required this.onChanged,
    super.key,
    this.enabled = true,
    this.semanticLabel,
  });

  final bool value;

  /// 为 null 时控件同样按禁用处理，与 `sf.Switch` 的行为保持一致。
  final ValueChanged<bool>? onChanged;

  final bool enabled;
  final String? semanticLabel;

  @override
  State<IdeSwitch> createState() => _IdeSwitchState();
}

class _IdeSwitchState extends State<IdeSwitch> {
  bool _focused = false;

  bool get _enabled => widget.enabled && widget.onChanged != null;

  void _toggle() {
    if (!_enabled) {
      return;
    }
    widget.onChanged?.call(!widget.value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final brightness = sf.Theme.of(context).brightness;
    // reduce-motion 下直接跳到终态，避免辅助功能场景出现滑动动画。
    final duration = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : IdeMotion.durationFast;

    final trackColor = widget.value
        ? (_enabled ? colors.accent : colors.primaryMuted)
        : colors.controlSurface;
    // 打开态靠填充色本身立住，不再叠描边；关闭态需要描边把轨道从
    // controlSurface 背景里勾出来。
    final trackBorderColor = widget.value
        ? null
        : (_enabled ? colors.border : colors.borderSubtle);
    final thumbColor = widget.value
        ? colors.onAccent
        : (_enabled ? colors.textTertiary : colors.border);

    final track = AnimatedContainer(
      duration: duration,
      curve: IdeMotion.curveDefault,
      width: IdeMetrics.switchTrackWidth,
      height: IdeMetrics.switchTrackHeight,
      padding: const EdgeInsets.all(IdeMetrics.switchTrackPadding),
      decoration: BoxDecoration(
        color: trackColor,
        borderRadius: IdeRadius.allSmall,
        border: trackBorderColor == null
            ? null
            : Border.all(color: trackBorderColor),
        boxShadow: _focused && _enabled
            ? IdeEffects.focusRing(brightness, accent: colors.focusRing)
            : const <BoxShadow>[],
      ),
      child: AnimatedAlign(
        duration: duration,
        curve: IdeMotion.curveDefault,
        alignment: widget.value ? Alignment.centerRight : Alignment.centerLeft,
        child: AnimatedContainer(
          duration: duration,
          curve: IdeMotion.curveDefault,
          width: IdeMetrics.switchThumbSize,
          height: IdeMetrics.switchThumbSize,
          decoration: BoxDecoration(
            color: thumbColor,
            borderRadius: IdeRadius.allMicro,
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
          if (value == _focused) {
            return;
          }
          setState(() => _focused = value);
        },
        actions: <Type, Action<Intent>>{
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              _toggle();
              return null;
            },
          ),
        },
        shortcuts: const <ShortcutActivator, Intent>{
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _enabled ? _toggle : null,
          child: track,
        ),
      ),
    );
  }
}

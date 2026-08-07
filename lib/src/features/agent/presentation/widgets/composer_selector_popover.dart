part of '../agent_pane.dart';

/// Composer 选择器弹层在当前视口中的定位结果。
@immutable
class _ComposerSelectorPopoverLayout {
  const _ComposerSelectorPopoverLayout({
    required this.openAbove,
    required this.width,
    required this.maxHeight,
  });

  /// 是否在 trigger 上方展开。
  final bool openAbove;

  /// 扣除视口边距后的建议宽度。
  final double width;

  /// 当前展开方向可用的最大高度。
  final double maxHeight;
}

typedef _ComposerSelectorPopoverBuilder =
    Widget Function(
      BuildContext context,
      _ComposerSelectorPopoverLayout layout,
    );

/// 通过 [showIdePopover] 打开 Composer 紧凑选择器。
///
/// helper 统一按 trigger 上下空间选择展开方向，并将常规动画时长收口到
/// [IdeMotion]；reduce-motion 下直接使用零时长，避免 overlay 延迟残留。
IdePopoverHandle<void> _showComposerSelectorPopover({
  required BuildContext context,
  required double preferredWidth,
  required double preferredMaxHeight,
  required _ComposerSelectorPopoverBuilder builder,
  double minimumSpaceBelow = 180,
  Key? key,
}) {
  final mediaQuery = MediaQuery.of(context);
  final viewport = mediaQuery.size;
  final renderObject = context.findRenderObject();
  final renderBox = renderObject is RenderBox && renderObject.hasSize
      ? renderObject
      : null;
  final origin = renderBox?.localToGlobal(Offset.zero) ?? Offset.zero;
  final triggerHeight = renderBox?.size.height ?? 28;
  final viewportTop = mediaQuery.padding.top;
  final viewportBottom = viewport.height - mediaQuery.padding.bottom;
  final spaceAbove = math.max(0.0, origin.dy - viewportTop);
  final spaceBelow = math.max(0.0, viewportBottom - origin.dy - triggerHeight);
  final openAbove = spaceAbove > spaceBelow && spaceBelow < minimumSpaceBelow;
  final availableHeight =
      (openAbove ? spaceAbove : spaceBelow) -
      IdeSpacing.space6 -
      IdeSpacing.space12;
  final width = math.max(
    1.0,
    math.min(preferredWidth, viewport.width - IdeSpacing.space12 * 2),
  );
  final maxHeight = math.max(
    1.0,
    math.min(preferredMaxHeight, availableHeight),
  );
  final layout = _ComposerSelectorPopoverLayout(
    openAbove: openAbove,
    width: width,
    maxHeight: maxHeight,
  );
  final duration = MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : IdeMotion.durationFast;

  return showIdePopover<void>(
    context: context,
    alignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
    anchorAlignment: openAbove ? Alignment.topLeft : Alignment.bottomLeft,
    widthConstraint: IdePopoverConstraint.intrinsic,
    heightConstraint: IdePopoverConstraint.flexible,
    key: key,
    offset: Offset(0, openAbove ? -IdeSpacing.space6 : IdeSpacing.space6),
    transitionAlignment: openAbove ? Alignment.bottomLeft : Alignment.topLeft,
    margin: const EdgeInsets.all(IdeSpacing.space12),
    allowInvertVertical: false,
    showDuration: duration,
    dismissDuration: duration,
    builder: (context) => builder(context, layout),
  );
}

/// 管理单个 Composer 选择器的 handle、toggle 与关闭回焦。
///
/// owner 只需持有 controller；点击外部、Esc、选中或主动 dismiss 最终都会从
/// 同一 future 清理 handle。owner dispose 后异步回调不会再 setState 或请求焦点。
class _ComposerSelectorPopoverController {
  _ComposerSelectorPopoverController({
    required this.triggerFocusNode,
    required this.onOpenChanged,
  });

  final FocusNode triggerFocusNode;
  final VoidCallback onOpenChanged;

  IdePopoverHandle<void>? _handle;
  bool _disposed = false;

  bool get isOpen => _handle != null;

  IdePopoverHandle<void>? get handle => _handle;

  void toggle({
    required BuildContext context,
    required double preferredWidth,
    required double preferredMaxHeight,
    required _ComposerSelectorPopoverBuilder builder,
    double minimumSpaceBelow = 180,
    Key? key,
  }) {
    final current = _handle;
    if (current != null) {
      dismiss(current);
      return;
    }
    show(
      context: context,
      preferredWidth: preferredWidth,
      preferredMaxHeight: preferredMaxHeight,
      minimumSpaceBelow: minimumSpaceBelow,
      key: key,
      builder: builder,
    );
  }

  void show({
    required BuildContext context,
    required double preferredWidth,
    required double preferredMaxHeight,
    required _ComposerSelectorPopoverBuilder builder,
    double minimumSpaceBelow = 180,
    Key? key,
  }) {
    if (_disposed || _handle != null) {
      return;
    }
    final entry = _showComposerSelectorPopover(
      context: context,
      preferredWidth: preferredWidth,
      preferredMaxHeight: preferredMaxHeight,
      minimumSpaceBelow: minimumSpaceBelow,
      key: key,
      builder: builder,
    );
    _handle = entry;
    onOpenChanged();
    unawaited(
      entry.future.whenComplete(() {
        entry.dispose();
        if (_disposed || !identical(_handle, entry)) {
          return;
        }
        _handle = null;
        onOpenChanged();
        if (triggerFocusNode.canRequestFocus) {
          triggerFocusNode.requestFocus();
        }
      }),
    );
  }

  /// 仅关闭指定的当前 handle，避免延迟 owner 回调误关新层。
  void dismiss([IdePopoverHandle<void>? expected]) {
    final current = _handle;
    if (current == null ||
        (expected != null && !identical(current, expected))) {
      return;
    }
    current.dismiss();
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final current = _handle;
    _handle = null;
    current?.dismiss();
  }
}

/// Composer 简单单选列表的 shadcn 内容门面。
///
/// 调用方只提供业务值与 item；键盘导航、选中态和 auto-close 统一交给
/// [sf.SelectPopup] / [sf.SelectItemButton]，不再各自拼装 [sf.SelectData]。
class _ComposerSelectPopup<T extends Object> extends StatelessWidget {
  _ComposerSelectPopup({
    required this.value,
    required List<Widget> items,
    required this.onChanged,
    super.key,
  }) : items = List<Widget>.unmodifiable(items);

  final T? value;
  final List<Widget> items;
  final bool Function(T value, bool selected) onChanged;

  @override
  Widget build(BuildContext context) {
    return sf.Data.inherit(
      data: sf.SelectData(
        autoClose: true,
        hasSelection: value != null,
        enabled: true,
        expandIcon: null,
        isSelected: (candidate) => candidate == value,
        onChanged: (candidate, selected) {
          if (candidate is! T) {
            return false;
          }
          return onChanged(candidate, selected);
        },
      ),
      child: sf.SelectPopup<T>.noVirtualization(
        autoClose: true,
        items: sf.SelectItemList(children: items),
      ),
    );
  }
}

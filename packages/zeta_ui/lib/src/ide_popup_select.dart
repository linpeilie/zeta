import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'ide_popover.dart';
import 'pane_widgets.dart';

/// [IdePopupSelect] 的一个值选项。
@immutable
class IdePopupSelectItem<T extends Object> {
  const IdePopupSelectItem({
    required this.value,
    required this.label,
    this.enabled = true,
    this.key,
  });

  final T value;
  final String label;
  final bool enabled;
  final Key? key;
}

/// 构造选择器触发器。
typedef IdePopupSelectTriggerBuilder =
    Widget Function(
      BuildContext context, {
      required String label,
      required bool isOpen,
      required bool enabled,
      required FocusNode focusNode,
      required VoidCallback? onPressed,
    });

/// 构造弹层中的一个选择项。
typedef IdePopupSelectItemBuilder<T extends Object> =
    Widget Function(
      BuildContext context,
      IdePopupSelectItem<T> item, {
      required bool selected,
    });

/// IDE 通用的同步单值弹层选择器。
///
/// 组件统一管理 overlay 生命周期、视口定位、选值后关闭、外部值变化时关闭，
/// 以及 Esc/关闭后的触发器焦点恢复。异步搜索、分页或多阶段配置面板不应伪装成
/// 本控件，应直接组合 [IdePopoverController]。
class IdePopupSelect<T extends Object> extends StatefulWidget {
  const IdePopupSelect({
    required this.value,
    required this.placeholder,
    required this.items,
    required this.triggerBuilder,
    required this.itemBuilder,
    required this.onChanged,
    this.tooltip,
    this.popoverWidth = 280,
    this.popoverMaxHeight = 320,
    this.focusNodeDebugLabel = 'ide-popup-select-trigger',
    super.key,
  });

  final T? value;
  final String placeholder;
  final List<IdePopupSelectItem<T>> items;
  final IdePopupSelectTriggerBuilder triggerBuilder;
  final IdePopupSelectItemBuilder<T> itemBuilder;
  final ValueChanged<T> onChanged;
  final String? tooltip;
  final double popoverWidth;
  final double popoverMaxHeight;
  final String focusNodeDebugLabel;

  @override
  State<IdePopupSelect<T>> createState() => _IdePopupSelectState<T>();
}

class _IdePopupSelectState<T extends Object> extends State<IdePopupSelect<T>> {
  late final FocusNode _triggerFocusNode;
  late final IdePopoverController _popoverController;

  @override
  void initState() {
    super.initState();
    _triggerFocusNode = FocusNode(debugLabel: widget.focusNodeDebugLabel);
    _popoverController = IdePopoverController(
      triggerFocusNode: _triggerFocusNode,
      onOpenChanged: () {
        if (mounted) {
          setState(() {});
        }
      },
    );
  }

  @override
  void didUpdateWidget(covariant IdePopupSelect<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_popoverController.isOpen &&
        (oldWidget.value != widget.value || widget.items.isEmpty)) {
      final entry = _popoverController.handle;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _popoverController.dismiss(entry);
        }
      });
    }
  }

  @override
  void dispose() {
    _popoverController.dispose();
    _triggerFocusNode.dispose();
    super.dispose();
  }

  void _toggleMenu() {
    if (!_popoverController.isOpen && widget.items.isEmpty) {
      return;
    }
    _popoverController.toggle(
      context: context,
      preferredWidth: widget.popoverWidth,
      preferredMaxHeight: widget.popoverMaxHeight,
      builder: (context, layout) => ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: layout.width,
          maxHeight: layout.maxHeight,
        ),
        child: IdePopupSelectList<T>(
          value: widget.value,
          items: <Widget>[
            for (final item in widget.items)
              sf.SelectItemButton<T>(
                key: item.key,
                value: item.value,
                enabled: item.enabled,
                child: widget.itemBuilder(
                  context,
                  item,
                  selected: item.value == widget.value,
                ),
              ),
          ],
          onChanged: (value, selected) {
            if (!selected) {
              return false;
            }
            widget.onChanged(value);
            return true;
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selectedItem = _selectedItem();
    final enabled = widget.items.isNotEmpty;
    final trigger = widget.triggerBuilder(
      context,
      label:
          selectedItem?.label ?? widget.value?.toString() ?? widget.placeholder,
      isOpen: _popoverController.isOpen,
      enabled: enabled,
      focusNode: _triggerFocusNode,
      onPressed: enabled ? _toggleMenu : null,
    );
    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return trigger;
    }
    return IdeTooltip(
      message: tooltip,
      enabled: !_popoverController.isOpen,
      child: trigger,
    );
  }

  IdePopupSelectItem<T>? _selectedItem() {
    for (final item in widget.items) {
      if (item.value == widget.value) {
        return item;
      }
    }
    return null;
  }
}

/// 已建立弹层约束时使用的选择列表表面。
///
/// 这是 [IdePopupSelect] 与需要自定义头部的复合选择器之间的低层共享机制。
class IdePopupSelectList<T extends Object> extends StatelessWidget {
  const IdePopupSelectList({
    required this.value,
    required this.items,
    required this.onChanged,
    super.key,
  });

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

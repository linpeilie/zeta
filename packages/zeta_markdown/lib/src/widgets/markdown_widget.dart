import 'package:flutter/material.dart';

import '../render/markdown_document_view.dart';
import '../selection/selection_controller.dart';
import '../selection/selection_registrar.dart';
import 'markdown_controller.dart';
import 'markdown_theme.dart';
import 'markdown_types.dart';

class MarkdownWidget extends StatefulWidget {
  const MarkdownWidget({
    super.key,
    this.data,
    this.controller,
    this.theme,
    this.scrollController,
    this.physics,
    this.shrinkWrap = false,
    this.useColumn = false,
    this.selectable = true,
    this.enableCopyFullDocumentShortcut = true,
    this.showCopyAllInContextMenu = true,
    this.enableContextMenu = true,
    this.contextMenuLabels = const MarkdownContextMenuLabels(),
    this.selectionController,
    this.padding,
    this.onTapLink,
    this.codeBlockToolbarBuilder,
    this.imageBuilder,
    this.codeBlockBuilder,
    this.bulletBuilder,
    this.contextMenuBuilder,
  }) : assert(
          (data == null) != (controller == null),
          'Provide exactly one of data or controller.',
        );

  final String? data;
  final MarkdownController? controller;
  final MarkdownThemeData? theme;
  final ScrollController? scrollController;
  final ScrollPhysics? physics;
  final bool shrinkWrap;
  final bool useColumn;
  final bool selectable;
  final bool enableCopyFullDocumentShortcut;
  final bool showCopyAllInContextMenu;

  /// 是否允许弹出右键菜单；false 时右键完全无反应（不必再用空组件 builder 抑制）。
  final bool enableContextMenu;

  /// 菜单里本包自造项（复制全文 / 清除选区）的文案。
  final MarkdownContextMenuLabels contextMenuLabels;
  final MarkdownSelectionController? selectionController;
  final EdgeInsetsGeometry? padding;
  final MarkdownTapLinkCallback? onTapLink;

  /// 自绘代码块工具栏；为空时保持包内默认的复制按钮。
  ///
  /// 与 `codeBlockBuilder` 一样要传稳定引用，别在 build 里现写闭包。
  final MarkdownCodeBlockToolbarBuilder? codeBlockToolbarBuilder;
  final MarkdownImageBuilder? imageBuilder;
  final MarkdownCodeBlockBuilder? codeBlockBuilder;
  final MarkdownBulletBuilder? bulletBuilder;
  final MarkdownContextMenuBuilder? contextMenuBuilder;

  @override
  State<MarkdownWidget> createState() => _MarkdownWidgetState();
}

class _MarkdownWidgetState extends State<MarkdownWidget> {
  MarkdownController? _ownedController;
  late final MarkdownSelectionController _fallbackSelectionController;

  MarkdownController get _effectiveController =>
      widget.controller ?? _ownedController!;

  @override
  void initState() {
    super.initState();
    _fallbackSelectionController = MarkdownSelectionController();
    if (widget.controller == null) {
      _ownedController = MarkdownController(data: widget.data ?? '');
    }
  }

  @override
  void didUpdateWidget(covariant MarkdownWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      if (oldWidget.controller == null && widget.controller != null) {
        _ownedController?.dispose();
        _ownedController = null;
      } else if (oldWidget.controller != null && widget.controller == null) {
        _ownedController = MarkdownController(data: widget.data ?? '');
      }
    }
    if (widget.controller == null && oldWidget.data != widget.data) {
      _ownedController?.setData(widget.data ?? '');
    }
  }

  @override
  void dispose() {
    _ownedController?.dispose();
    _fallbackSelectionController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final inheritedTheme = MarkdownTheme.of(context);
    final resolvedTheme = (widget.theme ?? inheritedTheme).copyWith(
      padding: widget.padding ?? (widget.theme ?? inheritedTheme).padding,
    );
    return MarkdownTheme(
      data: resolvedTheme,
      child: Builder(
        builder: (context) {
          final theme = MarkdownTheme.of(context);
          final selectionRegistrar = MixinSelectionRegistrar.maybeOf(context);
          final selectionController = widget.selectable
              ? (widget.selectionController ??
                  selectionRegistrar?.controller ??
                  _fallbackSelectionController)
              : null;
          final usesInheritedSelectionController = widget.selectable &&
              widget.selectionController == null &&
              selectionRegistrar != null;
          final animation = selectionController == null
              ? _effectiveController.documentListenable
              : Listenable.merge(
                  <Listenable>[
                    _effectiveController.documentListenable,
                    selectionController,
                  ],
                );
          return TextSelectionTheme(
            data: TextSelectionThemeData(selectionColor: theme.selectionColor),
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) {
                if (!usesInheritedSelectionController) {
                  selectionController
                      ?.attachDocument(_effectiveController.document);
                }
                return MarkdownDocumentView(
                  document: _effectiveController.document,
                  theme: theme,
                  scrollController: widget.scrollController,
                  physics: widget.physics,
                  shrinkWrap: widget.shrinkWrap,
                  useColumn: widget.useColumn,
                  selectable: widget.selectable,
                  selectionController: selectionController,
                  onCopyPlainText: () {
                    _effectiveController.copyPlainTextToClipboard();
                  },
                  enableCopyFullDocumentShortcut:
                      widget.enableCopyFullDocumentShortcut,
                  showCopyAllInContextMenu: widget.showCopyAllInContextMenu,
                  enableContextMenu: widget.enableContextMenu,
                  contextMenuLabels: widget.contextMenuLabels,
                  onTapLink: widget.onTapLink,
                  codeBlockToolbarBuilder: widget.codeBlockToolbarBuilder,
                  imageBuilder: widget.imageBuilder,
                  codeBlockBuilder: widget.codeBlockBuilder,
                  bulletBuilder: widget.bulletBuilder,
                  contextMenuBuilder: widget.contextMenuBuilder,
                );
              },
            ),
          );
        },
      ),
    );
  }
}

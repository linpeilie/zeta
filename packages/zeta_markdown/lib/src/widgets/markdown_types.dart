import 'package:flutter/widgets.dart';

import '../core/document.dart';
import '../selection/selection_controller.dart';
import 'markdown_theme.dart';

typedef MarkdownTapLinkCallback = void Function(
  String destination,
  String? title,
  String label,
);

typedef MarkdownImageBuilder = Widget Function(
  BuildContext context,
  ImageBlock block,
  MarkdownThemeData theme,
);
typedef MarkdownCodeBlockBuilder = Widget Function(
  BuildContext context,
  String code,
  String? language,
  MarkdownThemeData theme,
);

typedef MarkdownBulletBuilder = Widget Function(
  BuildContext context,
  int bulletIndex,
  bool isOrdered,
  int? orderedStart,
  MarkdownTaskListItemState? taskState,
  MarkdownThemeData theme,
);

typedef MarkdownContextMenuBuilder = Widget Function(
  BuildContext context,
  MarkdownSelectionController selectionController,
  List<ContextMenuButtonItem> buttonItems,
  TextSelectionToolbarAnchors anchors,
);

/// 代码块工具栏的输入。
///
/// [onCopy] 就是默认工具栏那颗复制按钮的回调（写剪贴板），宿主自绘时直接复用。
@immutable
final class MarkdownCodeBlockToolbarData {
  /// 创建工具栏输入。
  const MarkdownCodeBlockToolbarData({
    required this.language,
    required this.lineCount,
    required this.onCopy,
    required this.theme,
  });

  /// fence info string，未标注语言时为 null。
  final String? language;

  /// 代码行数。
  final int lineCount;

  /// 复制整段代码到剪贴板。
  final VoidCallback onCopy;

  /// 当前 markdown 主题。
  final MarkdownThemeData theme;
}

/// 自绘代码块工具栏。
///
/// 返回 null = 不渲染任何工具栏；不注入该 builder = 保持包内默认的复制按钮。
///
/// **传稳定引用**：与 `codeBlockBuilder` 一样，builder 会参与 widget 树构建，
/// 每帧新建闭包会让缓存的 block 行失去复用价值。
typedef MarkdownCodeBlockToolbarBuilder = Widget? Function(
  BuildContext context,
  MarkdownCodeBlockToolbarData data,
);

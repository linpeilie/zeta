import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart'
    show SelectedContent, SelectionRegistrar;

/// Whether [context] is inside a Flutter [SelectionArea] (or any
/// [SelectionContainer] that actually registers selectables).
///
/// [SelectionContainer.disabled] still inserts a [SelectionRegistrarScope]
/// but leaves `registrar` null, matching Flutter's own "not selectable"
/// signal.
bool joinsFlutterSelectionArea(BuildContext context) {
  final scope =
      context.dependOnInheritedWidgetOfExactType<SelectionRegistrarScope>();
  return scope?.registrar != null ||
      MarkdownSelectionRegistrarLeak.maybeOf(context) != null;
}

/// Holds a [SelectionRegistrar] without being a [SelectionRegistrarScope].
///
/// Flutter's [Scrollable] only auto-installs a selection handler when it
/// sees a [SelectionRegistrarScope]. A leak lets descendants restore the
/// registrar *after* the scrollable, so nested viewports (code fences,
/// virtualized timelines) do not run [EdgeDraggingAutoScroller] against
/// content larger than the clip.
class MarkdownSelectionRegistrarLeak extends InheritedWidget {
  const MarkdownSelectionRegistrarLeak({
    super.key,
    required this.registrar,
    required super.child,
  });

  final SelectionRegistrar registrar;

  static SelectionRegistrar? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<MarkdownSelectionRegistrarLeak>()
        ?.registrar;
  }

  @override
  bool updateShouldNotify(MarkdownSelectionRegistrarLeak oldWidget) {
    return oldWidget.registrar != registrar;
  }
}

/// Hides the nearest selection registrar from a descendant [Scrollable].
///
/// Pair with [MarkdownSelectionScrollRestore] on the scrollable's *items*
/// or *content* so paragraphs still join the outer [SelectionArea].
class MarkdownSelectionScrollIsolation extends StatelessWidget {
  const MarkdownSelectionScrollIsolation({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final registrar = SelectionContainer.maybeOf(context) ??
        MarkdownSelectionRegistrarLeak.maybeOf(context);
    if (registrar == null) {
      return child;
    }
    return SelectionContainer.disabled(
      child: MarkdownSelectionRegistrarLeak(
        registrar: registrar,
        child: child,
      ),
    );
  }
}

/// Re-inserts [SelectionRegistrarScope] after [MarkdownSelectionScrollIsolation].
class MarkdownSelectionScrollRestore extends StatelessWidget {
  const MarkdownSelectionScrollRestore({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (SelectionContainer.maybeOf(context) != null) {
      return child;
    }
    final registrar = MarkdownSelectionRegistrarLeak.maybeOf(context);
    if (registrar == null) {
      return child;
    }
    return SelectionRegistrarScope(
      registrar: registrar,
      child: child,
    );
  }
}

/// A [SingleChildScrollView] that does not become a selection auto-scroller.
///
/// Content still registers with the captured registrar, so copy/highlight
/// keep working. Used for code fences and wide tables whose contents are
/// larger than the clip.
Widget markdownIsolateNestedScrollable({
  required BuildContext context,
  required Widget content,
  Axis scrollDirection = Axis.vertical,
  ScrollController? controller,
  Key? key,
}) {
  final registrar = SelectionContainer.maybeOf(context) ??
      MarkdownSelectionRegistrarLeak.maybeOf(context);
  final inner = registrar == null
      ? content
      : SelectionRegistrarScope(registrar: registrar, child: content);
  final scroller = SingleChildScrollView(
    key: key,
    controller: controller,
    scrollDirection: scrollDirection,
    child: inner,
  );
  if (registrar == null) {
    return scroller;
  }
  return SelectionContainer.disabled(child: scroller);
}

/// One selectable block whose copied text ends in a newline when the
/// selection runs past its end.
///
/// Flutter concatenates adjacent [RenderParagraph]s with nothing between
/// them. Wrapping each markdown leaf (and each conversation message) in
/// this container restores paragraph breaks and a blank line between
/// turns. Inert when there is no ancestor selection container.
class MarkdownNativeSelectionBlock extends StatefulWidget {
  const MarkdownNativeSelectionBlock({
    super.key,
    required this.child,
  });

  final Widget child;

  @override
  State<MarkdownNativeSelectionBlock> createState() =>
      _MarkdownNativeSelectionBlockState();
}

class _MarkdownNativeSelectionBlockState
    extends State<MarkdownNativeSelectionBlock> {
  final _MarkdownNativeSelectionBlockDelegate _delegate =
      _MarkdownNativeSelectionBlockDelegate();

  @override
  void dispose() {
    _delegate.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (SelectionContainer.maybeOf(context) == null) {
      return widget.child;
    }
    return SelectionContainer(delegate: _delegate, child: widget.child);
  }
}

class _MarkdownNativeSelectionBlockDelegate
    extends StaticSelectionContainerDelegate {
  @override
  SelectedContent? getSelectedContent() {
    final content = super.getSelectedContent();
    final range = getSelection();
    if (content == null || range == null || content.plainText.isEmpty) {
      return content;
    }
    final end = math.max(range.startOffset, range.endOffset);
    if (end < contentLength) {
      return content;
    }
    return SelectedContent(plainText: '${content.plainText}\n');
  }
}

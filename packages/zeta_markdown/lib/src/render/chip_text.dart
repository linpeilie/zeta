import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../selection/native_selection.dart';
import '../widgets/markdown_theme.dart';

/// A text span whose glyph boxes get a chip painted behind them by
/// [MarkdownChipText]. Stays plain text so wrapping, baseline and native
/// selection all belong to the same [RenderParagraph].
class MarkdownChipSpan extends TextSpan {
  const MarkdownChipSpan({
    required String super.text,
    super.style,
    super.recognizer,
    super.mouseCursor,
    required this.fill,
  });

  final Color fill;

  @override
  RenderComparison compareTo(InlineSpan other) {
    final result = super.compareTo(other);
    if (result == RenderComparison.identical &&
        !identical(this, other) &&
        other is MarkdownChipSpan &&
        other.fill != fill) {
      return RenderComparison.paint;
    }
    return result;
  }

  @override
  bool operator ==(Object other) =>
      super == other && other is MarkdownChipSpan && other.fill == fill;

  @override
  int get hashCode => Object.hash(super.hashCode, fill);
}

/// `Text.rich` with inline-code chips painted from glyph boxes, then
/// wrapped as a [MarkdownNativeSelectionBlock] so copies keep newlines.
class MarkdownChipText extends StatelessWidget {
  const MarkdownChipText(
    this.span, {
    super.key,
    this.style,
    this.textAlign = TextAlign.start,
    this.textScaler,
    this.textDirection,
    this.textKey,
  });

  final InlineSpan span;
  final TextStyle? style;
  final TextAlign textAlign;
  final TextScaler? textScaler;
  final TextDirection? textDirection;
  final Key? textKey;

  @override
  Widget build(BuildContext context) {
    final defaults = DefaultTextStyle.of(context);
    final registrar = SelectionContainer.maybeOf(context);
    final selectionStyle = DefaultSelectionStyle.of(context);
    final theme = MarkdownTheme.of(context);
    Widget result = _MarkdownChipRichText(
      key: textKey,
      text: TextSpan(
          style: style ?? defaults.style, children: <InlineSpan>[span]),
      textAlign: textAlign,
      textScaler: textScaler ?? MediaQuery.textScalerOf(context),
      textDirection: textDirection ?? Directionality.of(context),
      locale: Localizations.maybeLocaleOf(context),
      selectionRegistrar: registrar,
      selectionColor:
          selectionStyle.selectionColor ?? DefaultSelectionStyle.defaultColor,
      chipRadius: theme.inlineCodeBorderRadius,
      chipPadding: theme.inlineCodePadding,
    );
    if (registrar != null) {
      result = MouseRegion(
        cursor: DefaultSelectionStyle.of(context).mouseCursor ??
            SystemMouseCursors.text,
        child: result,
      );
    }
    return MarkdownNativeSelectionBlock(child: result);
  }
}

class _MarkdownChipRichText extends RichText {
  _MarkdownChipRichText({
    super.key,
    required super.text,
    required super.textAlign,
    required super.textScaler,
    required super.textDirection,
    super.locale,
    super.selectionRegistrar,
    super.selectionColor,
    required this.chipRadius,
    required this.chipPadding,
  });

  final BorderRadius chipRadius;
  final EdgeInsets chipPadding;

  @override
  RenderParagraph createRenderObject(BuildContext context) {
    return _MarkdownChipRenderParagraph(
      text,
      textAlign: textAlign,
      textDirection: textDirection ?? Directionality.of(context),
      softWrap: softWrap,
      overflow: overflow,
      textScaler: textScaler,
      maxLines: maxLines,
      strutStyle: strutStyle,
      textWidthBasis: textWidthBasis,
      textHeightBehavior: textHeightBehavior,
      locale: locale ?? Localizations.maybeLocaleOf(context),
      registrar: selectionRegistrar,
      selectionColor: selectionColor,
      devicePixelRatio: MediaQuery.maybeDevicePixelRatioOf(context) ??
          View.maybeOf(context)?.devicePixelRatio ??
          1.0,
      chipRadius: chipRadius,
      chipPadding: chipPadding,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderParagraph renderObject,
  ) {
    super.updateRenderObject(context, renderObject);
    if (renderObject is _MarkdownChipRenderParagraph) {
      renderObject
        ..chipRadius = chipRadius
        ..chipPadding = chipPadding;
    }
  }
}

class _MarkdownChipRenderParagraph extends RenderParagraph {
  _MarkdownChipRenderParagraph(
    super.text, {
    required super.textAlign,
    required super.textDirection,
    required super.softWrap,
    required super.overflow,
    required super.textScaler,
    super.maxLines,
    super.strutStyle,
    required super.textWidthBasis,
    super.textHeightBehavior,
    super.locale,
    super.registrar,
    super.selectionColor,
    super.devicePixelRatio,
    required BorderRadius chipRadius,
    required EdgeInsets chipPadding,
  })  : _chipRadius = chipRadius,
        _chipPadding = chipPadding;

  BorderRadius _chipRadius;
  EdgeInsets _chipPadding;

  BorderRadius get chipRadius => _chipRadius;
  set chipRadius(BorderRadius value) {
    if (value == _chipRadius) {
      return;
    }
    _chipRadius = value;
    markNeedsPaint();
  }

  EdgeInsets get chipPadding => _chipPadding;
  set chipPadding(EdgeInsets value) {
    if (value == _chipPadding) {
      return;
    }
    _chipPadding = value;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    _paintChips(context.canvas, offset);
    super.paint(context, offset);
  }

  void _paintChips(Canvas canvas, Offset offset) {
    final ranges = <_ChipRange>[];
    var cursor = 0;
    void walk(InlineSpan span) {
      if (span is TextSpan) {
        final text = span.text;
        if (text != null && text.isNotEmpty) {
          if (span is MarkdownChipSpan) {
            final last = ranges.isEmpty ? null : ranges.last;
            if (last != null && last.end == cursor && last.fill == span.fill) {
              last.end = cursor + text.length;
            } else {
              ranges.add(_ChipRange(cursor, cursor + text.length, span.fill));
            }
          }
          cursor += text.length;
        }
        final children = span.children;
        if (children != null) {
          children.forEach(walk);
        }
      } else {
        cursor += 1;
      }
    }

    walk(text);
    if (ranges.isEmpty) {
      return;
    }

    final hPad = _chipPadding.horizontal / 2;
    for (final range in ranges) {
      final boxes = getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      if (boxes.isEmpty) {
        continue;
      }

      final fragments = <Rect>[];
      for (final box in boxes) {
        final rect = box.toRect();
        if (rect.width <= 0) {
          continue;
        }
        if (fragments.isNotEmpty &&
            rect.top < fragments.last.bottom &&
            rect.bottom > fragments.last.top) {
          fragments[fragments.length - 1] =
              fragments.last.expandToInclude(rect);
        } else {
          fragments.add(rect);
        }
      }
      if (fragments.isEmpty) {
        continue;
      }

      final rtl = boxes.first.direction == TextDirection.rtl;
      final paint = Paint()..color = range.fill;
      for (var i = 0; i < fragments.length; i++) {
        final rect = Rect.fromLTRB(
          fragments[i].left - hPad,
          fragments[i].top,
          fragments[i].right + hPad,
          fragments[i].bottom,
        ).shift(offset);
        final startRounded = i == 0;
        final endRounded = i == fragments.length - 1;
        final leftRounded = rtl ? endRounded : startRounded;
        final rightRounded = rtl ? startRounded : endRounded;
        canvas.drawRRect(
          RRect.fromRectAndCorners(
            rect,
            topLeft: leftRounded ? _chipRadius.topLeft : Radius.zero,
            bottomLeft: leftRounded ? _chipRadius.bottomLeft : Radius.zero,
            topRight: rightRounded ? _chipRadius.topRight : Radius.zero,
            bottomRight: rightRounded ? _chipRadius.bottomRight : Radius.zero,
          ),
          paint,
        );
      }
    }
  }
}

class _ChipRange {
  _ChipRange(this.start, this.end, this.fill);

  final int start;
  int end;
  final Color fill;
}

import 'dart:ui' show Color;

import 'package:flutter/foundation.dart';

/// 代码高亮的语义调色板。
///
/// 每个槽位都可为空：**空 = 回退到从 `linkStyle.color` 推导的上游默认色**，
/// 因此不注入调色板时渲染结果与上游 0.3.1 完全一致。
///
/// 槽位对应的 token 类别见各字段文档；token → 槽位的映射不因注入而改变。
@immutable
final class MarkdownCodeHighlightPalette {
  /// 创建调色板；不传的槽位沿用上游推导色。
  const MarkdownCodeHighlightPalette({
    this.comment,
    this.keyword,
    this.string,
    this.number,
    this.type,
    this.title,
    this.meta,
    this.link,
    this.punctuation,
  });

  /// `comment` / `quote` / `doctag`（默认还会叠斜体）。
  final Color? comment;

  /// `keyword` / `selector-tag` / `literal` / `operator`（默认还会叠 w700）。
  final Color? keyword;

  /// `string` / `regexp` / `subst`。
  final Color? string;

  /// `number` / `symbol` / `bullet`。
  final Color? number;

  /// `type` / `built_in` / `attr` / `attribute` / `variable` / `template-variable`。
  ///
  /// 上游把它与 [meta] 共用同一个推导色；拆成两槽是为了让宿主能分别上色，
  /// 都不传时行为不变。
  final Color? type;

  /// `title` / `title.function_` / `title.class_` / `function` / `section`
  ///（默认还会叠 w700）。
  final Color? title;

  /// `meta` / `meta-keyword`（默认还会叠 w600）。
  final Color? meta;

  /// `link`；为空时沿用 `linkStyle` 的颜色与下划线装饰。
  final Color? link;

  /// `punctuation`。
  final Color? punctuation;

  /// 是否所有槽位都为空（等价于不注入）。
  bool get isEmpty =>
      comment == null &&
      keyword == null &&
      string == null &&
      number == null &&
      type == null &&
      title == null &&
      meta == null &&
      link == null &&
      punctuation == null;

  /// 主题过渡插值；任一侧为空时按空槽位处理。
  static MarkdownCodeHighlightPalette? lerp(
    MarkdownCodeHighlightPalette? a,
    MarkdownCodeHighlightPalette? b,
    double t,
  ) {
    if (a == null && b == null) {
      return null;
    }
    return MarkdownCodeHighlightPalette(
      comment: Color.lerp(a?.comment, b?.comment, t),
      keyword: Color.lerp(a?.keyword, b?.keyword, t),
      string: Color.lerp(a?.string, b?.string, t),
      number: Color.lerp(a?.number, b?.number, t),
      type: Color.lerp(a?.type, b?.type, t),
      title: Color.lerp(a?.title, b?.title, t),
      meta: Color.lerp(a?.meta, b?.meta, t),
      link: Color.lerp(a?.link, b?.link, t),
      punctuation: Color.lerp(a?.punctuation, b?.punctuation, t),
    );
  }

  /// 值相等。
  ///
  /// **必须是值语义**：宿主通常在 build 里现算主题，`MarkdownDocumentView`
  /// 按 `theme !=` 决定要不要清空整份 block 行缓存——引用相等会让每帧都清。
  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }
    return other is MarkdownCodeHighlightPalette &&
        other.comment == comment &&
        other.keyword == keyword &&
        other.string == string &&
        other.number == number &&
        other.type == type &&
        other.title == title &&
        other.meta == meta &&
        other.link == link &&
        other.punctuation == punctuation;
  }

  @override
  int get hashCode => Object.hash(
        comment,
        keyword,
        string,
        number,
        type,
        title,
        meta,
        link,
        punctuation,
      );
}

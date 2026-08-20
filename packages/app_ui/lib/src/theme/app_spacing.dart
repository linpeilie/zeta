import 'dart:ui';

import 'package:flutter/material.dart';

/// Spacing tokens for Zeta's dense desktop layouts.
@immutable
class AppSpacing extends ThemeExtension<AppSpacing> {
  /// Creates a spacing scale.
  const AppSpacing({
    this.zero = 0,
    this.xxxs = 2,
    this.xxs = 4,
    this.s6 = 6,
    this.xs = 8,
    this.s10 = 10,
    this.sm = 12,
    this.md = 16,
    this.s20 = 20,
    this.lg = 24,
    this.xlg = 32,
    this.xxlg = 48,
  });

  /// No spacing.
  final double zero;

  /// Two logical pixels.
  final double xxxs;

  /// Four logical pixels.
  final double xxs;

  /// Six logical pixels.
  final double s6;

  /// Eight logical pixels.
  final double xs;

  /// Ten logical pixels.
  final double s10;

  /// Twelve logical pixels.
  final double sm;

  /// Sixteen logical pixels.
  final double md;

  /// Twenty logical pixels.
  final double s20;

  /// Twenty-four logical pixels.
  final double lg;

  /// Thirty-two logical pixels.
  final double xlg;

  /// Forty-eight logical pixels, the preferred interactive-target size.
  final double xxlg;

  /// Standard page inset.
  EdgeInsets get pagePadding => EdgeInsets.symmetric(
    horizontal: md,
    vertical: sm,
  );

  /// Compact page inset.
  EdgeInsets get pagePaddingCompact => EdgeInsets.all(sm);

  /// Section inset.
  EdgeInsets get sectionPadding => EdgeInsets.all(md);

  /// Pane inset.
  EdgeInsets get panelPadding => EdgeInsets.all(sm);

  /// Card inset.
  EdgeInsets get cardPadding => EdgeInsets.all(s10);

  /// Dialog inset.
  EdgeInsets get dialogPadding => EdgeInsets.all(md);

  /// Toolbar inset.
  EdgeInsets get toolbarPadding => EdgeInsets.symmetric(
    horizontal: xs,
    vertical: xxs,
  );

  /// Standard dense-row inset.
  EdgeInsets get rowPadding => EdgeInsets.symmetric(
    horizontal: s10,
    vertical: s6,
  );

  /// Settings-row inset inside a card.
  EdgeInsets get settingsRowPadding => EdgeInsets.symmetric(
    horizontal: sm,
    vertical: md,
  );

  /// Settings-row inset in a flat page.
  EdgeInsets get settingsRowPaddingFlat => EdgeInsets.symmetric(vertical: md);

  /// Settings-group heading inset.
  EdgeInsets get settingsGroupTitlePadding => EdgeInsets.only(
    top: xs,
    bottom: sm,
  );

  /// Composer inset that leaves room for its resize affordance.
  EdgeInsets get composerPadding => EdgeInsets.fromLTRB(sm, s10, xs, xs);

  /// Compact control inset.
  EdgeInsets get compactControlPadding => EdgeInsets.symmetric(
    horizontal: xs,
    vertical: xxs,
  );

  /// Text-input content inset.
  EdgeInsets get inputContentPadding => EdgeInsets.symmetric(
    horizontal: sm,
    vertical: xs,
  );

  @override
  AppSpacing copyWith({
    double? zero,
    double? xxxs,
    double? xxs,
    double? s6,
    double? xs,
    double? s10,
    double? sm,
    double? md,
    double? s20,
    double? lg,
    double? xlg,
    double? xxlg,
  }) {
    return AppSpacing(
      zero: zero ?? this.zero,
      xxxs: xxxs ?? this.xxxs,
      xxs: xxs ?? this.xxs,
      s6: s6 ?? this.s6,
      xs: xs ?? this.xs,
      s10: s10 ?? this.s10,
      sm: sm ?? this.sm,
      md: md ?? this.md,
      s20: s20 ?? this.s20,
      lg: lg ?? this.lg,
      xlg: xlg ?? this.xlg,
      xxlg: xxlg ?? this.xxlg,
    );
  }

  @override
  AppSpacing lerp(covariant AppSpacing? other, double t) {
    if (other == null) return this;
    return AppSpacing(
      zero: lerpDouble(zero, other.zero, t)!,
      xxxs: lerpDouble(xxxs, other.xxxs, t)!,
      xxs: lerpDouble(xxs, other.xxs, t)!,
      s6: lerpDouble(s6, other.s6, t)!,
      xs: lerpDouble(xs, other.xs, t)!,
      s10: lerpDouble(s10, other.s10, t)!,
      sm: lerpDouble(sm, other.sm, t)!,
      md: lerpDouble(md, other.md, t)!,
      s20: lerpDouble(s20, other.s20, t)!,
      lg: lerpDouble(lg, other.lg, t)!,
      xlg: lerpDouble(xlg, other.xlg, t)!,
      xxlg: lerpDouble(xxlg, other.xxlg, t)!,
    );
  }
}

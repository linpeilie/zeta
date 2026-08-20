import 'dart:ui';

import 'package:flutter/material.dart';

/// Radius tokens for nested desktop surfaces and controls.
@immutable
class AppRadii extends ThemeExtension<AppRadii> {
  /// Creates the radius scale.
  const AppRadii({
    this.micro = 4,
    this.small = 6,
    this.medium = 8,
    this.large = 12,
    this.pill = 999,
  });

  /// Inline and chip radius.
  final double micro;

  /// Control radius.
  final double small;

  /// Card radius.
  final double medium;

  /// Pane and overlay radius.
  final double large;

  /// Fully rounded radius.
  final double pill;

  /// Inline and chip border radius.
  BorderRadius get allMicro => BorderRadius.circular(micro);

  /// Control border radius.
  BorderRadius get allSmall => BorderRadius.circular(small);

  /// Card border radius.
  BorderRadius get allMedium => BorderRadius.circular(medium);

  /// Pane and overlay border radius.
  BorderRadius get allLarge => BorderRadius.circular(large);

  /// Fully rounded border radius.
  BorderRadius get allPill => BorderRadius.circular(pill);

  /// Builds a smooth panel shape.
  ShapeBorder panel({BorderSide side = BorderSide.none}) {
    return RoundedSuperellipseBorder(borderRadius: allLarge, side: side);
  }

  /// Builds a conventional rounded control shape.
  ShapeBorder control(
    BorderRadiusGeometry radius, {
    BorderSide side = BorderSide.none,
  }) {
    return RoundedRectangleBorder(borderRadius: radius, side: side);
  }

  /// Whether [radius] belongs to the panel tier.
  bool isPanelTier(BorderRadiusGeometry radius) => radius == allLarge;

  @override
  AppRadii copyWith({
    double? micro,
    double? small,
    double? medium,
    double? large,
    double? pill,
  }) {
    return AppRadii(
      micro: micro ?? this.micro,
      small: small ?? this.small,
      medium: medium ?? this.medium,
      large: large ?? this.large,
      pill: pill ?? this.pill,
    );
  }

  @override
  AppRadii lerp(covariant AppRadii? other, double t) {
    if (other == null) return this;
    return AppRadii(
      micro: lerpDouble(micro, other.micro, t)!,
      small: lerpDouble(small, other.small, t)!,
      medium: lerpDouble(medium, other.medium, t)!,
      large: lerpDouble(large, other.large, t)!,
      pill: lerpDouble(pill, other.pill, t)!,
    );
  }
}

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

/// Elevation, focus, and overlay effects for the desktop design system.
@immutable
class AppEffects extends ThemeExtension<AppEffects> {
  /// Creates the effect scale.
  const AppEffects({
    this.overlayBlurRadius = 16,
    this.overlayOffsetY = 4,
    this.focusRingWidth = 2,
  });

  /// Overlay-shadow blur radius.
  final double overlayBlurRadius;

  /// Overlay-shadow vertical offset.
  final double overlayOffsetY;

  /// Keyboard focus-ring width.
  final double focusRingWidth;

  /// Returns the only shadow allowed for detached overlays.
  List<BoxShadow> overlayShadow(Brightness brightness) => <BoxShadow>[
    BoxShadow(
      color: brightness == Brightness.dark
          ? sf.Colors.black.withValues(alpha: 0.28)
          : sf.Colors.zinc[900].withValues(alpha: 0.10),
      blurRadius: overlayBlurRadius,
      offset: Offset(0, overlayOffsetY),
    ),
  ];

  /// Returns the keyboard focus ring for [accent].
  List<BoxShadow> focusRing(
    Brightness brightness, {
    required Color accent,
  }) => <BoxShadow>[
    BoxShadow(
      color: accent.withValues(
        alpha: brightness == Brightness.dark ? 0.54 : 0.36,
      ),
      spreadRadius: focusRingWidth,
    ),
  ];

  /// Returns the modal workbench scrim.
  Color scrim(Brightness brightness) => brightness == Brightness.dark
      ? sf.Colors.black.withValues(alpha: 0.55)
      : sf.Colors.zinc[300].withValues(alpha: 0.24);

  @override
  AppEffects copyWith({
    double? overlayBlurRadius,
    double? overlayOffsetY,
    double? focusRingWidth,
  }) {
    return AppEffects(
      overlayBlurRadius: overlayBlurRadius ?? this.overlayBlurRadius,
      overlayOffsetY: overlayOffsetY ?? this.overlayOffsetY,
      focusRingWidth: focusRingWidth ?? this.focusRingWidth,
    );
  }

  @override
  AppEffects lerp(covariant AppEffects? other, double t) {
    if (other == null) return this;
    return AppEffects(
      overlayBlurRadius: lerpDouble(
        overlayBlurRadius,
        other.overlayBlurRadius,
        t,
      )!,
      overlayOffsetY: lerpDouble(overlayOffsetY, other.overlayOffsetY, t)!,
      focusRingWidth: lerpDouble(focusRingWidth, other.focusRingWidth, t)!,
    );
  }
}

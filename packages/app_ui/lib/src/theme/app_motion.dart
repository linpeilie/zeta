import 'package:flutter/material.dart';

/// Motion tokens with a single reduced-motion gate.
@immutable
class AppMotion extends ThemeExtension<AppMotion> {
  /// Creates the motion scale.
  const AppMotion({
    this.fast = const Duration(milliseconds: 100),
    this.normal = const Duration(milliseconds: 160),
    this.slow = const Duration(milliseconds: 260),
    this.loadingPulse = const Duration(milliseconds: 900),
    this.runningGlow = const Duration(milliseconds: 2400),
    this.intelligenceShimmer = const Duration(milliseconds: 1800),
    this.intelligenceImpact = const Duration(milliseconds: 320),
    this.defaultCurve = Curves.easeInOutCubic,
    this.scrollCurve = Curves.easeOutCubic,
    this.popupCurve = Curves.easeOutQuint,
  });

  /// Fast interaction duration.
  final Duration fast;

  /// Normal interaction duration.
  final Duration normal;

  /// Slow content-transition duration.
  final Duration slow;

  /// Loading pulse period.
  final Duration loadingPulse;

  /// Running-state glow period.
  final Duration runningGlow;

  /// Intelligence shimmer period.
  final Duration intelligenceShimmer;

  /// Intelligence impact duration.
  final Duration intelligenceImpact;

  /// Default interaction curve.
  final Curve defaultCurve;

  /// Smooth-scroll curve.
  final Curve scrollCurve;

  /// Popup curve.
  final Curve popupCurve;

  /// Returns zero when the platform requests reduced motion.
  Duration resolve(Duration duration, {required bool reduceMotion}) {
    return reduceMotion ? Duration.zero : duration;
  }

  /// Resolves [duration] against the current platform accessibility setting.
  Duration resolveFor(BuildContext context, Duration duration) {
    return resolve(
      duration,
      reduceMotion: MediaQuery.maybeDisableAnimationsOf(context) ?? false,
    );
  }

  @override
  AppMotion copyWith({
    Duration? fast,
    Duration? normal,
    Duration? slow,
    Duration? loadingPulse,
    Duration? runningGlow,
    Duration? intelligenceShimmer,
    Duration? intelligenceImpact,
    Curve? defaultCurve,
    Curve? scrollCurve,
    Curve? popupCurve,
  }) {
    return AppMotion(
      fast: fast ?? this.fast,
      normal: normal ?? this.normal,
      slow: slow ?? this.slow,
      loadingPulse: loadingPulse ?? this.loadingPulse,
      runningGlow: runningGlow ?? this.runningGlow,
      intelligenceShimmer: intelligenceShimmer ?? this.intelligenceShimmer,
      intelligenceImpact: intelligenceImpact ?? this.intelligenceImpact,
      defaultCurve: defaultCurve ?? this.defaultCurve,
      scrollCurve: scrollCurve ?? this.scrollCurve,
      popupCurve: popupCurve ?? this.popupCurve,
    );
  }

  @override
  AppMotion lerp(covariant AppMotion? other, double t) {
    if (other == null) return this;
    return AppMotion(
      fast: _lerpDuration(fast, other.fast, t),
      normal: _lerpDuration(normal, other.normal, t),
      slow: _lerpDuration(slow, other.slow, t),
      loadingPulse: _lerpDuration(loadingPulse, other.loadingPulse, t),
      runningGlow: _lerpDuration(runningGlow, other.runningGlow, t),
      intelligenceShimmer: _lerpDuration(
        intelligenceShimmer,
        other.intelligenceShimmer,
        t,
      ),
      intelligenceImpact: _lerpDuration(
        intelligenceImpact,
        other.intelligenceImpact,
        t,
      ),
      defaultCurve: t < 0.5 ? defaultCurve : other.defaultCurve,
      scrollCurve: t < 0.5 ? scrollCurve : other.scrollCurve,
      popupCurve: t < 0.5 ? popupCurve : other.popupCurve,
    );
  }
}

Duration _lerpDuration(Duration first, Duration second, double t) {
  return Duration(
    microseconds:
        (first.inMicroseconds +
                (second.inMicroseconds - first.inMicroseconds) * t)
            .round(),
  );
}

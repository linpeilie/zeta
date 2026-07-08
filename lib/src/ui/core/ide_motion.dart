import 'package:flutter/animation.dart';

/// IDE 动效 token。
abstract final class IdeMotion {
  static const Duration durationFast = Duration(milliseconds: 100);
  static const Duration durationNormal = Duration(milliseconds: 160);
  static const Duration durationSlow = Duration(milliseconds: 260);

  static const Duration fast = durationFast;
  static const Duration normal = durationNormal;
  static const Duration slow = durationSlow;

  static const Curve curveDefault = Curves.easeInOutCubic;
  static const Curve curvePopup = Curves.easeOutQuint;
}

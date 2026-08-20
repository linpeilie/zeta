import 'package:flutter/material.dart';

/// A semantic value displayed by a compact metric bar.
@immutable
class CompactMetricItem {
  /// Creates a compact metric item.
  const CompactMetricItem({
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    this.tone,
    this.onPressed,
    this.semanticLabel,
  });

  /// Human-readable metric name.
  final String label;

  /// Primary metric value.
  final String value;

  /// Optional supporting value.
  final String? detail;

  /// Optional leading icon.
  final IconData? icon;

  /// Optional semantic color override.
  final Color? tone;

  /// Optional activation callback.
  final VoidCallback? onPressed;

  /// Optional accessible name for an interactive item.
  final String? semanticLabel;
}

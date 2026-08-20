import 'package:flutter/widgets.dart';

/// A lazily built retained page with a stable identity.
class IdeRetainedPage {
  /// Creates a retained page.
  const IdeRetainedPage({required this.id, required this.child});

  /// Stable identity used for element matching.
  final String id;

  /// Page content.
  final Widget child;
}

import 'package:flutter/widgets.dart';
import 'package:zeta/l10n/l10n.dart';

/// Locale-dependent app services frozen before the first frame.
final class AppDependencies {
  /// Creates the locale-dependent app dependency bundle.
  const AppDependencies({
    required this.locale,
    required this.failureMessages,
    required this.desktopNotificationCopyResolver,
    required this.desktopChromeCopyResolver,
  });

  /// Display locale frozen for the lifetime of this process.
  final Locale locale;

  /// App-owned cross-layer failure mapping.
  final FailureMessages failureMessages;

  /// App-owned safe desktop notification copy mapping.
  final DesktopNotificationCopyResolver desktopNotificationCopyResolver;

  /// App-owned native window and menu copy mapping.
  final DesktopChromeCopyResolver desktopChromeCopyResolver;
}

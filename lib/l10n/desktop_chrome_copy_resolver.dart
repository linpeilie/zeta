import 'package:zeta/l10n/gen/app_localizations.dart';

/// Resolves already-localized native window and menu copy.
///
/// The composition root configures the native window title and application
/// menu before the first frame exists, so this resolver is created from the
/// locale frozen during bootstrap and never reads a build context.
final class DesktopChromeCopyResolver {
  /// Creates a resolver for one already-frozen localization instance.
  const DesktopChromeCopyResolver(this._l10n);

  final AppLocalizations _l10n;

  /// Native window title.
  String get windowTitle => _l10n.appTitle;

  /// Localized File menu label.
  String get fileMenuLabel => _l10n.workbenchMenuFile;

  /// Localized Open Project item label.
  String get openProjectLabel => _l10n.workbenchMenuOpenProject;
}

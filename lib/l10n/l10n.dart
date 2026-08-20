import 'package:flutter/widgets.dart';
import 'package:zeta/l10n/gen/app_localizations.dart';

export 'package:zeta/l10n/gen/app_localizations.dart';

export 'failure_messages.dart';
export 'zeta_shadcn_localizations.dart';

extension AppLocalizationsX on BuildContext {
  /// Returns the localization for a subtree with installed delegates.
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// Returns null for tests or subtrees without localization delegates.
  AppLocalizations? get l10nOrNull =>
      Localizations.of<AppLocalizations>(this, AppLocalizations);
}

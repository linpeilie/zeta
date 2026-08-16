import 'package:flutter/widgets.dart';

import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

export 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// Widget 树中读取当前进程 [AppLocalizations] 的统一入口。
extension AppLocalizationsX on BuildContext {
  AppLocalizations get l10n => AppLocalizations.of(this);

  /// 测试或未挂 delegate 的子树可读到 null。
  AppLocalizations? get l10nOrNull =>
      Localizations.of<AppLocalizations>(this, AppLocalizations);
}

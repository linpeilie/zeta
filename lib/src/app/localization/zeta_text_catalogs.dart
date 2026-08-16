import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 把同一份 [AppLocalizations] 拆成各 feature 文本目录的组合对象。
///
/// 步骤 6 只建立入口；具体目录适配器从步骤 7 起按 feature 补齐。
final class ZetaTextCatalogs {
  const ZetaTextCatalogs(this.l10n);

  final AppLocalizations l10n;
}

import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// 语言无关的相对时间算法；只翻译外围静态 token。
String formatLocalizedRelativeTime(
  DateTime value,
  DateTime now,
  AppLocalizations l10n,
) {
  final elapsed = now.difference(value);
  if (elapsed.isNegative || elapsed.inMinutes < 1) {
    return l10n.relativeTimeJustNow;
  }
  if (elapsed.inHours < 1) {
    return l10n.relativeTimeMinutesAgo('${elapsed.inMinutes}');
  }
  if (elapsed.inDays < 1) {
    return l10n.relativeTimeHoursAgo('${elapsed.inHours}');
  }
  return l10n.relativeTimeDaysAgo('${elapsed.inDays}');
}

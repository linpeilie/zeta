import 'package:zeta/src/ui/localization/generated/app_localizations.dart';
import 'package:zeta/src/ui/localization/relative_time.dart';

String formatUsageCount(num value) {
  final absolute = value.abs();
  if (absolute < 1000) {
    return value is int ? value.toString() : _trimDecimal(value.toDouble(), 1);
  }
  const suffixes = <String>['K', 'M', 'B', 'T'];
  var scaled = value.toDouble();
  var index = -1;
  while (scaled.abs() >= 1000 && index + 1 < suffixes.length) {
    scaled /= 1000;
    index += 1;
  }
  return '${_trimDecimal(scaled, scaled.abs() >= 100 ? 0 : 1)}${suffixes[index]}';
}

String formatUsagePercent(double? ratio, {required String empty}) {
  if (ratio == null) {
    return empty;
  }
  return '${_trimDecimal(ratio * 100, 1)}%';
}

String formatUsageDuration(
  Duration? duration, {
  bool compact = false,
  required String empty,
}) {
  if (duration == null) {
    return empty;
  }
  if (duration.inMinutes >= 1) {
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return seconds == 0 ? '${minutes}m' : '${minutes}m ${seconds}s';
  }
  if (duration.inSeconds >= 1) {
    final seconds = duration.inMilliseconds / 1000;
    return '${_trimDecimal(seconds, compact ? 0 : 1)}s';
  }
  return '${duration.inMilliseconds}ms';
}

String formatUsageDateTime(DateTime? value, {required String empty}) {
  if (value == null) {
    return empty;
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// 仅日期（本地时区），用于时间范围触发器与自定义区间摘要。
String formatUsageDate(DateTime? value, {required String empty}) {
  if (value == null) {
    return empty;
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String formatUsageDateRange(
  DateTime start,
  DateTime endInclusive, {
  required String empty,
}) {
  return '${formatUsageDate(start, empty: empty)} – ${formatUsageDate(endInclusive, empty: empty)}';
}

String formatUsageClock(DateTime? value) {
  if (value == null) {
    return '--:--';
  }
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// 套餐窗口重置时刻的精简本地时间，不含「重置」前缀。
///
/// - 距 [now] 不超过 7 天：`mm-dd HH:mm`
/// - 超过 7 天：`mm-dd`
String formatUsageResetAt(DateTime value, {DateTime? now}) {
  final local = value.toLocal();
  final reference = (now ?? DateTime.now()).toLocal();
  final delta = local.difference(reference).abs();
  final monthDay =
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
  if (delta > const Duration(days: 7)) {
    return monthDay;
  }
  final hour = local.hour.toString().padLeft(2, '0');
  final minute = local.minute.toString().padLeft(2, '0');
  return '$monthDay $hour:$minute';
}

String formatUsageRelativeTime(
  DateTime value,
  DateTime now, {
  required AppLocalizations l10n,
}) {
  final difference = now.difference(value);
  if (difference.inDays >= 30) {
    return formatUsageDateTime(value, empty: l10n.usageNoData);
  }
  return formatLocalizedRelativeTime(value, now, l10n);
}

String formatUsagePlanType(String? value, {required AppLocalizations l10n}) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return l10n.usageUnknownPlan;
  }
  return switch (cleaned.toLowerCase()) {
    'free' => 'ChatGPT Free',
    'go' => 'ChatGPT Go',
    'plus' => 'ChatGPT Plus',
    'pro' => 'ChatGPT Pro',
    'prolite' => 'ChatGPT Pro Lite',
    'team' => 'ChatGPT Team',
    'self_serve_business_usage_based' => l10n.usagePlanBusinessUsageBased,
    'business' => 'ChatGPT Business',
    'enterprise_cbp_usage_based' => l10n.usagePlanEnterpriseUsageBased,
    'enterprise' => 'ChatGPT Enterprise',
    'edu' => 'ChatGPT Edu',
    'supergrok' => 'SuperGrok',
    'supergrok heavy' ||
    'supergrokheavy' ||
    'super_grok_heavy' => 'SuperGrok Heavy',
    'x premium plus' || 'xpremiumplus' || 'x_premium_plus' => 'X Premium+',
    'basic' || 'x basic' || 'xbasic' => 'X Basic',
    _ => cleaned,
  };
}

String _trimDecimal(double value, int digits) {
  final formatted = value.toStringAsFixed(digits);
  return formatted.endsWith('.0')
      ? formatted.substring(0, formatted.length - 2)
      : formatted;
}

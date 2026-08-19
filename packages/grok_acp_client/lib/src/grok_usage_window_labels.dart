import 'package:grok_acp_client/src/grok_text_catalog.dart';

/// Builds a stable English label from a quota-window duration in minutes.
String? formatGrokUsageWindowLabelFromMinutes(
  int? minutes, {
  GrokTextCatalog catalog = const GrokTextCatalog(),
}) {
  if (minutes == null || minutes <= 0) {
    return null;
  }
  const weekMinutes = 7 * 24 * 60;
  const dayMinutes = 24 * 60;
  const hourMinutes = 60;
  if (minutes % weekMinutes == 0) {
    final weeks = minutes ~/ weekMinutes;
    return '$weeks ${weeks == 1 ? 'week' : 'weeks'}';
  }
  if (minutes % dayMinutes == 0) {
    final days = minutes ~/ dayMinutes;
    return '$days ${days == 1 ? 'day' : 'days'}';
  }
  if (minutes % hourMinutes == 0) {
    final hours = minutes ~/ hourMinutes;
    return '$hours ${hours == 1 ? 'hour' : 'hours'}';
  }
  if (minutes > hourMinutes) {
    final hours = minutes ~/ hourMinutes;
    final remaining = minutes % hourMinutes;
    return '$hours h $remaining min';
  }
  return '$minutes min';
}

/// Builds a fallback label from a Grok billing period type.
String? formatGrokUsageWindowLabelFromPeriodType(
  String? periodType, {
  GrokTextCatalog catalog = const GrokTextCatalog(),
}) => switch (periodType) {
  'USAGE_PERIOD_TYPE_WEEKLY' => '1 week',
  'USAGE_PERIOD_TYPE_DAILY' => '1 day',
  _ => null,
};

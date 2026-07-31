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

String formatUsagePercent(double? ratio) {
  if (ratio == null) {
    return '暂无数据';
  }
  return '${_trimDecimal(ratio * 100, 1)}%';
}

String formatUsageDuration(Duration? duration, {bool compact = false}) {
  if (duration == null) {
    return '暂无数据';
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

String formatUsageDateTime(DateTime? value) {
  if (value == null) {
    return '暂无数据';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')} '
      '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

/// 仅日期（本地时区），用于时间范围触发器与自定义区间摘要。
String formatUsageDate(DateTime? value) {
  if (value == null) {
    return '暂无数据';
  }
  final local = value.toLocal();
  return '${local.year.toString().padLeft(4, '0')}-'
      '${local.month.toString().padLeft(2, '0')}-'
      '${local.day.toString().padLeft(2, '0')}';
}

String formatUsageDateRange(DateTime start, DateTime endInclusive) {
  return '${formatUsageDate(start)} – ${formatUsageDate(endInclusive)}';
}

String formatUsageClock(DateTime? value) {
  if (value == null) {
    return '--:--';
  }
  final local = value.toLocal();
  return '${local.hour.toString().padLeft(2, '0')}:'
      '${local.minute.toString().padLeft(2, '0')}';
}

String formatUsageRelativeTime(DateTime value, DateTime now) {
  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return '刚刚';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} 分钟前';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours} 小时前';
  }
  if (difference.inDays < 30) {
    return '${difference.inDays} 天前';
  }
  return formatUsageDateTime(value);
}

String formatUsagePlanType(String? value) {
  final cleaned = value?.trim();
  if (cleaned == null || cleaned.isEmpty) {
    return '未知套餐';
  }
  return switch (cleaned.toLowerCase()) {
    'free' => 'ChatGPT Free',
    'go' => 'ChatGPT Go',
    'plus' => 'ChatGPT Plus',
    'pro' => 'ChatGPT Pro',
    'prolite' => 'ChatGPT Pro Lite',
    'team' => 'ChatGPT Team',
    'self_serve_business_usage_based' => 'ChatGPT Business（按量）',
    'business' => 'ChatGPT Business',
    'enterprise_cbp_usage_based' => 'ChatGPT Enterprise（按量）',
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

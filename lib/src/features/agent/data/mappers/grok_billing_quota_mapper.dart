import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';

/// 将 Grok ACP `_x.ai/billing` 响应映射为中立套餐快照。
///
/// 仅使用协议实际返回的字段；不推算绝对 Token 总额或未提供的窗口。
AgentUsageQuotaSnapshot? mapGrokBillingQuota(
  Object? raw, {
  required String providerId,
  required String providerName,
}) {
  final response = _asMap(raw);
  if (response == null) {
    return null;
  }

  final config = _asMap(response['config']) ?? const <String, Object?>{};
  final planType =
      _nonEmptyString(response['subscription_tier']) ??
      _nonEmptyString(config['subscription_tier']);

  final windows = <AgentUsageWindow>[];
  final primary = _primaryWindow(config);
  if (primary != null) {
    windows.add(primary);
  }
  final onDemand = _onDemandWindow(config);
  if (onDemand != null) {
    windows.add(onDemand);
  }

  final credits = _credits(config);
  if (windows.isEmpty && credits == null && planType == null) {
    return null;
  }

  return AgentUsageQuotaSnapshot(
    providerId: providerId,
    providerName: providerName,
    planType: planType,
    limitName: _limitName(config, planType),
    windows: List<AgentUsageWindow>.unmodifiable(windows),
    credits: credits,
  );
}

AgentUsageWindow? _primaryWindow(Map<String, Object?> config) {
  final usedPercent = _percent(config['creditUsagePercent']);
  if (usedPercent == null) {
    return null;
  }

  final period = _asMap(config['currentPeriod']) ?? const <String, Object?>{};
  final periodType = _nonEmptyString(period['type']);
  final start =
      _parseDateTime(period['start']) ??
      _parseDateTime(config['billingPeriodStart']);
  final end =
      _parseDateTime(period['end']) ??
      _parseDateTime(config['billingPeriodEnd']);

  return AgentUsageWindow(
    label: _periodLabel(periodType),
    usedPercent: usedPercent,
    resetsAt: end?.toLocal(),
    windowDuration: _durationBetween(start, end),
  );
}

AgentUsageWindow? _onDemandWindow(Map<String, Object?> config) {
  final cap = _moneyVal(config['onDemandCap']);
  if (cap == null || cap <= 0) {
    return null;
  }
  final used = _moneyVal(config['onDemandUsed']) ?? 0;
  final percent = ((used / cap) * 100).round().clamp(0, 100);
  return AgentUsageWindow(label: '按需额度', usedPercent: percent);
}

AgentUsageCredits? _credits(Map<String, Object?> config) {
  final prepaid = _moneyVal(config['prepaidBalance']);
  if (prepaid == null) {
    return null;
  }
  return AgentUsageCredits(
    hasCredits: prepaid > 0,
    unlimited: false,
    balance: _formatBalance(prepaid),
  );
}

String? _limitName(Map<String, Object?> config, String? planType) {
  final period = _asMap(config['currentPeriod']) ?? const <String, Object?>{};
  final periodType = _nonEmptyString(period['type']);
  final periodLabel = switch (periodType) {
    'USAGE_PERIOD_TYPE_WEEKLY' => '周额度',
    'USAGE_PERIOD_TYPE_MONTHLY' => '月额度',
    _ => null,
  };
  if (periodLabel != null) {
    return periodLabel;
  }
  return planType;
}

String _periodLabel(String? periodType) => switch (periodType) {
  'USAGE_PERIOD_TYPE_WEEKLY' => '周额度',
  'USAGE_PERIOD_TYPE_MONTHLY' => '月额度',
  'USAGE_PERIOD_TYPE_DAILY' => '日额度',
  _ => '套餐额度',
};

int? _percent(Object? value) {
  if (value is int) {
    return value.clamp(0, 100);
  }
  if (value is num) {
    return value.round().clamp(0, 100);
  }
  if (value is String) {
    final parsed = num.tryParse(value.trim());
    if (parsed != null) {
      return parsed.round().clamp(0, 100);
    }
  }
  return null;
}

/// Grok billing 金额字段常为 `{ "val": number }`。
double? _moneyVal(Object? value) {
  if (value is num) {
    return value.toDouble();
  }
  final map = _asMap(value);
  if (map == null) {
    return null;
  }
  final nested = map['val'];
  if (nested is num) {
    return nested.toDouble();
  }
  if (nested is String) {
    return double.tryParse(nested.trim());
  }
  return null;
}

String _formatBalance(double value) {
  if (value == value.roundToDouble()) {
    return value.toInt().toString();
  }
  final fixed = value.toStringAsFixed(2);
  if (fixed.endsWith('0')) {
    return value.toStringAsFixed(1);
  }
  return fixed;
}

DateTime? _parseDateTime(Object? value) {
  if (value is! String) {
    return null;
  }
  final cleaned = value.trim();
  if (cleaned.isEmpty) {
    return null;
  }
  return DateTime.tryParse(cleaned);
}

Duration? _durationBetween(DateTime? start, DateTime? end) {
  if (start == null || end == null) {
    return null;
  }
  final duration = end.difference(start);
  return duration.isNegative ? null : duration;
}

String? _nonEmptyString(Object? value) {
  final cleaned = value?.toString().trim();
  if (cleaned == null || cleaned.isEmpty) {
    return null;
  }
  return cleaned;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map((key, item) => MapEntry(key.toString(), item as Object?));
}

import 'package:agent_provider_contracts/agent_provider_contracts.dart';

/// 将 Grok ACP `_x.ai/billing` 响应映射为中立套餐快照。
///
/// 仅使用协议实际返回的字段；不推算绝对 Token 总额或未提供的窗口。
/// 窗口标签与 Codex 共用时长文案（「1 周」/「5 小时」），不用「周额度」。
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
    // 与 Codex 一致：limitName 不承载周期别名；周期展示只在 window.label。
    limitName: planType,
    windows: List<AgentUsageWindow>.unmodifiable(windows),
    credits: credits,
  );
}

AgentUsageWindow? _primaryWindow(Map<String, Object?> config) {
  final period = _asMap(config['currentPeriod']) ?? const <String, Object?>{};
  final periodType = _nonEmptyString(period['type']);
  final start =
      _parseDateTime(period['start']) ??
      _parseDateTime(config['billingPeriodStart']);
  // 优先 currentPeriod.end；旧字段 billingPeriodEnd 仅作回退。
  final end =
      _parseDateTime(period['end']) ??
      _parseDateTime(config['billingPeriodEnd']);
  final windowDuration = _durationBetween(start, end);

  final usedPercent = _percent(config['creditUsagePercent']);
  // proto3 在 0% 时常省略 creditUsagePercent。周/月额度刚重置时仍会带
  // currentPeriod（含 end）；此时按 0% 建窗口，否则 UI 会合成无 resetsAt 的占位条。
  final resolvedPercent =
      usedPercent ??
      (_isRecognizedUsagePeriod(periodType) && end != null ? 0 : null);
  if (resolvedPercent == null) {
    return null;
  }

  final labelCode = windowDuration != null && windowDuration > Duration.zero
      ? AgentUsageWindowLabelCode.duration
      : switch (periodType) {
          'USAGE_PERIOD_TYPE_WEEKLY' => AgentUsageWindowLabelCode.oneWeek,
          'USAGE_PERIOD_TYPE_DAILY' => AgentUsageWindowLabelCode.oneDay,
          _ => AgentUsageWindowLabelCode.planQuota,
        };

  return AgentUsageWindow(
    labelCode: labelCode,
    usedPercent: resolvedPercent,
    resetsAt: end?.toLocal(),
    windowDuration: windowDuration,
  );
}

bool _isRecognizedUsagePeriod(String? periodType) => switch (periodType) {
  'USAGE_PERIOD_TYPE_WEEKLY' ||
  'USAGE_PERIOD_TYPE_MONTHLY' ||
  'USAGE_PERIOD_TYPE_DAILY' => true,
  _ => false,
};

AgentUsageWindow? _onDemandWindow(Map<String, Object?> config) {
  final cap = _moneyVal(config['onDemandCap']);
  if (cap == null || cap <= 0) {
    return null;
  }
  final used = _moneyVal(config['onDemandUsed']) ?? 0;
  final percent = ((used / cap) * 100).round().clamp(0, 100);
  return AgentUsageWindow(
    labelCode: AgentUsageWindowLabelCode.onDemandQuota,
    usedPercent: percent,
  );
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

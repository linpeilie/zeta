import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';

/// 将 Claude Code OAuth usage 响应映射为中立套餐快照。
///
/// 仅消费已知字段；窗口缺失、字段损坏或未知余额单位时不补零、不推算币种。
AgentUsageQuotaSnapshot? mapClaudeCodeUsageQuota(
  Object? raw, {
  required String providerId,
  required String providerName,
  String? subscriptionType,
}) {
  final response = _asMap(raw);
  if (response == null) {
    return null;
  }

  final windows = <AgentUsageWindow>[
    ?_window(
      response['five_hour'],
      label: '五小时会话额度',
      duration: const Duration(hours: 5),
    ),
    ?_window(
      response['seven_day'],
      label: '1 周',
      duration: const Duration(days: 7),
    ),
  ];
  final planType = _nonEmptyString(subscriptionType);
  final credits = _credits(response['extra_usage']);
  if (windows.isEmpty && planType == null && credits == null) {
    return null;
  }

  return AgentUsageQuotaSnapshot(
    providerId: providerId,
    providerName: providerName,
    planType: planType,
    limitName: 'Claude Code 订阅额度',
    windows: List<AgentUsageWindow>.unmodifiable(windows),
    credits: credits,
  );
}

AgentUsageWindow? _window(
  Object? raw, {
  required String label,
  required Duration duration,
}) {
  final value = _asMap(raw);
  final usedPercent = _percent(value?['utilization']);
  if (usedPercent == null) {
    return null;
  }
  return AgentUsageWindow(
    label: label,
    usedPercent: usedPercent,
    resetsAt: _dateTime(value?['resets_at'])?.toLocal(),
    windowDuration: duration,
  );
}

AgentUsageCredits? _credits(Object? raw) {
  final value = _asMap(raw);
  if (value == null || value['is_enabled'] != true) {
    return null;
  }

  final balance = _balanceText(value['balance']);
  final explicitHasCredits = value['has_credits'];
  final monthlyLimit = _finiteNumber(value['monthly_limit']);
  final usedCredits = _finiteNumber(value['used_credits']);
  final utilization = _percent(value['utilization']);
  final bool hasCredits;
  if (explicitHasCredits is bool) {
    hasCredits = explicitHasCredits;
  } else if (monthlyLimit != null && usedCredits != null) {
    // 两个字段使用 Provider 自己的同一单位，只比较大小，不展示或猜测单位。
    hasCredits = usedCredits < monthlyLimit;
  } else if (utilization != null) {
    hasCredits = utilization < 100;
  } else {
    hasCredits = true;
  }

  return AgentUsageCredits(
    hasCredits: hasCredits,
    unlimited: false,
    balance: balance,
  );
}

int? _percent(Object? value) {
  final number = _finiteNumber(value);
  return number?.round().clamp(0, 100);
}

num? _finiteNumber(Object? value) {
  final parsed = switch (value) {
    num() => value,
    String() => num.tryParse(value.trim()),
    _ => null,
  };
  return parsed?.isFinite == true ? parsed : null;
}

String? _balanceText(Object? value) {
  if (value is String) {
    return _nonEmptyString(value);
  }
  final number = _finiteNumber(value);
  if (number == null) {
    return null;
  }
  return number == number.roundToDouble()
      ? number.toInt().toString()
      : number.toString();
}

DateTime? _dateTime(Object? value) {
  final normalized = _nonEmptyString(value);
  return normalized == null ? null : DateTime.tryParse(normalized);
}

String? _nonEmptyString(Object? value) {
  final normalized = value?.toString().trim();
  return normalized == null || normalized.isEmpty ? null : normalized;
}

Map<String, Object?>? _asMap(Object? value) {
  if (value is! Map) {
    return null;
  }
  return value.map<String, Object?>(
    (key, item) => MapEntry(key.toString(), item),
  );
}

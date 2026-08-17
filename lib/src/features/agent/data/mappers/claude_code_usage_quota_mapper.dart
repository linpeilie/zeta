import 'package:zeta/src/features/agent/domain/agent_ui_text_catalog.dart';
import 'package:zeta/src/features/agent/domain/agent_usage_models.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';

/// 将 Claude Code OAuth usage 响应映射为中立套餐快照。
///
/// 仅消费已知字段；窗口缺失、字段损坏或未知余额单位时不补零、不推算币种。
AgentUsageQuotaSnapshot? mapClaudeCodeUsageQuota(
  Object? raw, {
  required String providerId,
  required String providerName,
  String? subscriptionType,
  AgentUiTextCatalog textCatalog = const FallbackAgentUiTextCatalog(),
}) {
  final response = _asMap(raw) ?? const <String, Object?>{};

  final windows = <AgentUsageWindow>[
    ?_window(
      response['five_hour'],
      label: textCatalog.quotaFiveHours,
      duration: const Duration(hours: 5),
    ),
    ?_window(
      response['seven_day'],
      label: textCatalog.quotaOneWeek,
      duration: const Duration(days: 7),
    ),
    ?_window(
      response['seven_day_sonnet'],
      label: textCatalog.quotaSonnetOneWeek,
      duration: const Duration(days: 7),
    ),
    ?_window(
      response['seven_day_opus'],
      label: textCatalog.quotaOpusOneWeek,
      duration: const Duration(days: 7),
    ),
  ];
  final planType = _subscriptionDisplayName(subscriptionType);
  final credits = _credits(response['extra_usage']);
  if (windows.isEmpty && planType == null && credits == null) {
    return null;
  }

  return AgentUsageQuotaSnapshot(
    providerId: providerId,
    providerName: providerName,
    planType: planType,
    limitName: textCatalog.claudeCodeSubscriptionQuota,
    windows: List<AgentUsageWindow>.unmodifiable(windows),
    credits: credits,
  );
}

String? _subscriptionDisplayName(Object? value) {
  final normalized = _nonEmptyString(value);
  return switch (normalized?.toLowerCase()) {
    'pro' || 'claude pro' => 'Claude Pro',
    'max' || 'claude max' => 'Claude Max',
    'team' || 'claude team' => 'Claude Team',
    'enterprise' || 'claude enterprise' => 'Claude Enterprise',
    _ => normalized,
  };
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

  if (value.containsKey('monthly_limit') && value['monthly_limit'] == null) {
    // Claude Code 明确定义 null 为无限额；不据此推算币种或余额文本。
    return const AgentUsageCredits(hasCredits: true, unlimited: true);
  }

  final monthlyLimit = _finiteNumber(value['monthly_limit']);
  final usedCredits = _finiteNumber(value['used_credits']);
  final utilization = _percent(value['utilization']);
  final bool? hasCredits;
  if (monthlyLimit != null && usedCredits != null) {
    // 两个字段使用 Provider 自己的同一单位，只比较大小，不展示或猜测单位。
    hasCredits = usedCredits < monthlyLimit;
  } else if (utilization != null) {
    hasCredits = utilization < 100;
  } else {
    hasCredits = null;
  }
  if (hasCredits == null) {
    return null;
  }

  return AgentUsageCredits(hasCredits: hasCredits, unlimited: false);
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

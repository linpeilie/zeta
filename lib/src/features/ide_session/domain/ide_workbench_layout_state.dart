/// IDE Workbench 可持久化的布局偏好。
///
/// 该模型只保存与设备无关的应用级意图；具体宽度、高度最小值与响应式夹紧仍由
/// presentation 层的布局 token 决定。
final class IdeWorkbenchLayoutState {
  const IdeWorkbenchLayoutState({
    this.leftSidebarVisible = true,
    this.agentUsageExpanded = false,
    this.leftSidebarWidth,
    this.agentUsageHeightFraction,
    this.selectedAgentUsageProviderId,
  });

  /// Projects / Agent 统计合并栏是否可见。
  final bool leftSidebarVisible;

  /// Agent 统计是否展示完整内容。
  final bool agentUsageExpanded;

  /// 用户提交的左栏逻辑像素宽度；为空时由 UI 使用默认 token。
  final double? leftSidebarWidth;

  /// 展开统计区占左栏可用高度的比例；为空时由 UI 使用默认 token。
  final double? agentUsageHeightFraction;

  /// 统计面板关注的 Provider 配置 id；目录到达后再校验是否可用。
  final String? selectedAgentUsageProviderId;

  IdeWorkbenchLayoutState copyWith({
    bool? leftSidebarVisible,
    bool? agentUsageExpanded,
    Object? leftSidebarWidth = _unsetWorkbenchLayoutValue,
    Object? agentUsageHeightFraction = _unsetWorkbenchLayoutValue,
    Object? selectedAgentUsageProviderId = _unsetWorkbenchLayoutValue,
  }) {
    return IdeWorkbenchLayoutState(
      leftSidebarVisible: leftSidebarVisible ?? this.leftSidebarVisible,
      agentUsageExpanded: agentUsageExpanded ?? this.agentUsageExpanded,
      leftSidebarWidth: identical(leftSidebarWidth, _unsetWorkbenchLayoutValue)
          ? this.leftSidebarWidth
          : _positiveFiniteDouble(leftSidebarWidth),
      agentUsageHeightFraction:
          identical(agentUsageHeightFraction, _unsetWorkbenchLayoutValue)
          ? this.agentUsageHeightFraction
          : _fraction(agentUsageHeightFraction),
      selectedAgentUsageProviderId:
          identical(selectedAgentUsageProviderId, _unsetWorkbenchLayoutValue)
          ? this.selectedAgentUsageProviderId
          : _providerId(selectedAgentUsageProviderId),
    );
  }

  /// 投影为 `ide_session.json` 中的 `workbench` 白名单字段。
  Map<String, Object?> toJson() => <String, Object?>{
    'leftSidebarVisible': leftSidebarVisible,
    'agentUsageExpanded': agentUsageExpanded,
    'leftSidebarWidth': leftSidebarWidth,
    'agentUsageHeightFraction': agentUsageHeightFraction,
    'selectedAgentUsageProviderId': selectedAgentUsageProviderId,
  };

  /// 逐字段宽容读取持久化投影。
  ///
  /// 根节点、字段类型或数值损坏只让对应字段回退默认，不影响其余有效偏好。
  static IdeWorkbenchLayoutState tryDecode(Object? raw) {
    if (raw is! Map) {
      return const IdeWorkbenchLayoutState();
    }
    final map = Map<Object?, Object?>.from(raw);
    return IdeWorkbenchLayoutState(
      leftSidebarVisible: map['leftSidebarVisible'] is bool
          ? map['leftSidebarVisible']! as bool
          : true,
      agentUsageExpanded: map['agentUsageExpanded'] is bool
          ? map['agentUsageExpanded']! as bool
          : false,
      leftSidebarWidth: _positiveFiniteDouble(map['leftSidebarWidth']),
      agentUsageHeightFraction: _fraction(map['agentUsageHeightFraction']),
      selectedAgentUsageProviderId: _providerId(
        map['selectedAgentUsageProviderId'],
      ),
    );
  }

  @override
  bool operator ==(Object other) {
    return other is IdeWorkbenchLayoutState &&
        other.leftSidebarVisible == leftSidebarVisible &&
        other.agentUsageExpanded == agentUsageExpanded &&
        other.leftSidebarWidth == leftSidebarWidth &&
        other.agentUsageHeightFraction == agentUsageHeightFraction &&
        other.selectedAgentUsageProviderId == selectedAgentUsageProviderId;
  }

  @override
  int get hashCode => Object.hash(
    leftSidebarVisible,
    agentUsageExpanded,
    leftSidebarWidth,
    agentUsageHeightFraction,
    selectedAgentUsageProviderId,
  );
}

const Object _unsetWorkbenchLayoutValue = Object();

double? _positiveFiniteDouble(Object? raw) {
  if (raw is! num) {
    return null;
  }
  final value = raw.toDouble();
  return value.isFinite && value > 0 ? value : null;
}

double? _fraction(Object? raw) {
  final value = _positiveFiniteDouble(raw);
  return value != null && value < 1 ? value : null;
}

String? _providerId(Object? raw) {
  if (raw is! String) {
    return null;
  }
  final value = raw.trim();
  return value.isEmpty ? null : value;
}

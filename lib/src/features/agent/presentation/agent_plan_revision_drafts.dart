/// 计划卡底部输入框的草稿宿主。
///
/// 计划卡是对话流内的普通条目，会被虚拟列表回收；控制器若由卡片 State 自持，
/// 用户滚动离开再回来就会丢失已输入的修改意见。这里按请求 id 托管控制器与
/// 焦点节点，生命周期跟随 [AgentPane] 而非单个 Widget。
library;

import 'package:flutter/widgets.dart';

/// 按计划请求 id 托管修改输入的控制器与焦点节点。
final class AgentPlanRevisionDraftStore {
  final Map<String, TextEditingController> _controllers =
      <String, TextEditingController>{};
  final Map<String, FocusNode> _focusNodes = <String, FocusNode>{};

  /// 取得 [requestId] 的输入控制器，不存在时惰性创建。
  TextEditingController controllerFor(String requestId) {
    return _controllers.putIfAbsent(requestId, TextEditingController.new);
  }

  /// 取得 [requestId] 的焦点节点，不存在时惰性创建。
  FocusNode focusNodeFor(String requestId) {
    return _focusNodes.putIfAbsent(
      requestId,
      () => FocusNode(debugLabel: 'agent-plan-revision-$requestId'),
    );
  }

  /// 释放不在 [activeIds] 中的草稿，避免会话累积泄漏。
  void retainOnly(Set<String> activeIds) {
    _controllers.removeWhere((id, controller) {
      if (activeIds.contains(id)) {
        return false;
      }
      controller.dispose();
      return true;
    });
    _focusNodes.removeWhere((id, focusNode) {
      if (activeIds.contains(id)) {
        return false;
      }
      focusNode.dispose();
      return true;
    });
  }

  /// 释放全部草稿。
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final focusNode in _focusNodes.values) {
      focusNode.dispose();
    }
    _controllers.clear();
    _focusNodes.clear();
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 在单一卡片内编排 Projects 与底部 Agent 统计的合并左栏。
///
/// 本组件只处理父约束与上下区域编排，不读取两个业务区域的数据。
class ProjectAgentSidebar extends StatelessWidget {
  const ProjectAgentSidebar({
    required this.projects,
    required this.agentUsage,
    required this.agentUsageExpanded,
    super.key,
  });

  final Widget projects;
  final Widget agentUsage;
  final bool agentUsageExpanded;

  @override
  Widget build(BuildContext context) {
    return PanelCard(
      key: const ValueKey('projects-panel-card'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableHeight = constraints.maxHeight;
          if (!availableHeight.isFinite) {
            return _buildUnboundedFallback();
          }
          return agentUsageExpanded
              ? _buildExpanded()
              : _buildCollapsed(availableHeight);
        },
      ),
    );
  }

  Widget _buildCollapsed(double availableHeight) {
    final maxSummaryHeight =
        availableHeight >=
            IdeMetrics.projectsPaneMinHeight + IdeMetrics.paneHeaderHeight
        ? availableHeight - IdeMetrics.projectsPaneMinHeight
        : math.min(availableHeight, IdeMetrics.paneHeaderHeight);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('project-agent-sidebar-projects'),
            child: projects,
          ),
        ),
        ConstrainedBox(
          key: const ValueKey('project-agent-sidebar-usage'),
          constraints: BoxConstraints(
            maxHeight: math.max(0.0, maxSummaryHeight),
          ),
          child: SingleChildScrollView(child: agentUsage),
        ),
      ],
    );
  }

  Widget _buildExpanded() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('project-agent-sidebar-projects'),
            child: projects,
          ),
        ),
        KeyedSubtree(
          key: const ValueKey('project-agent-sidebar-usage'),
          child: agentUsage,
        ),
      ],
    );
  }

  Widget _buildUnboundedFallback() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        KeyedSubtree(
          key: const ValueKey('project-agent-sidebar-projects'),
          child: projects,
        ),
        KeyedSubtree(
          key: const ValueKey('project-agent-sidebar-usage'),
          child: agentUsage,
        ),
      ],
    );
  }
}

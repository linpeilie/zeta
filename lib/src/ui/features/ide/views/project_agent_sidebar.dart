import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_resize_handle.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 在单一卡片内编排 Projects 与底部 Agent 统计的合并左栏。
///
/// 本组件只处理父约束、展开高度与拖动预览，不读取两个业务区域的数据。
class ProjectAgentSidebar extends StatefulWidget {
  const ProjectAgentSidebar({
    required this.projects,
    required this.agentUsage,
    required this.agentUsageExpanded,
    required this.onAgentUsageHeightFractionChanged,
    super.key,
    this.agentUsageHeightFraction,
  });

  final Widget projects;
  final Widget agentUsage;
  final bool agentUsageExpanded;

  /// 展开区占整个左栏可用高度的保存比例；为空时使用设计 token 默认值。
  final double? agentUsageHeightFraction;

  /// 仅在一次拖动结束时提交最终比例；逐像素预览不会触发。
  final ValueChanged<double> onAgentUsageHeightFractionChanged;

  @override
  State<ProjectAgentSidebar> createState() => _ProjectAgentSidebarState();
}

class _ProjectAgentSidebarState extends State<ProjectAgentSidebar> {
  late double _previewFraction = _effectiveFraction;
  bool _dragging = false;

  double get _effectiveFraction =>
      widget.agentUsageHeightFraction ?? IdeMetrics.agentUsageDefaultFraction;

  @override
  void didUpdateWidget(covariant ProjectAgentSidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_dragging &&
        oldWidget.agentUsageHeightFraction != widget.agentUsageHeightFraction) {
      _previewFraction = _effectiveFraction;
    }
  }

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
          return widget.agentUsageExpanded
              ? _buildExpanded(availableHeight)
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
            child: widget.projects,
          ),
        ),
        ConstrainedBox(
          key: const ValueKey('project-agent-sidebar-usage'),
          constraints: BoxConstraints(
            maxHeight: math.max(0.0, maxSummaryHeight),
          ),
          child: SingleChildScrollView(child: widget.agentUsage),
        ),
      ],
    );
  }

  Widget _buildExpanded(double availableHeight) {
    final bounds = _usageHeightBounds(availableHeight);
    final usageHeight = _resolveUsageHeight(availableHeight, bounds);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: KeyedSubtree(
            key: const ValueKey('project-agent-sidebar-projects'),
            child: widget.projects,
          ),
        ),
        IdeResizeHandle(
          key: const ValueKey('agent-usage-resize-handle'),
          axis: IdeResizeHandleAxis.vertical,
          semanticLabel: '调整 Agent 统计高度',
          onDragStart: (_) {
            _dragging = true;
          },
          onDragUpdate: (details) {
            final currentHeight = (availableHeight * _previewFraction).clamp(
              bounds.min,
              bounds.max,
            );
            final nextHeight = (currentHeight - details.delta.dy).clamp(
              bounds.min,
              bounds.max,
            );
            setState(() {
              _previewFraction = availableHeight <= 0
                  ? IdeMetrics.agentUsageDefaultFraction
                  : nextHeight / availableHeight;
            });
          },
          onDragEnd: (_) {
            _dragging = false;
            widget.onAgentUsageHeightFractionChanged(_previewFraction);
          },
          onDragCancel: () {
            setState(() {
              _dragging = false;
              _previewFraction = _effectiveFraction;
            });
          },
        ),
        SizedBox(
          key: const ValueKey('project-agent-sidebar-usage'),
          height: usageHeight,
          child: widget.agentUsage,
        ),
      ],
    );
  }

  Widget _buildUnboundedFallback() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        widget.projects,
        if (widget.agentUsageExpanded)
          IdeResizeHandle(
            key: const ValueKey('agent-usage-resize-handle'),
            axis: IdeResizeHandleAxis.vertical,
            semanticLabel: '调整 Agent 统计高度',
            onDragUpdate: (_) {},
          ),
        widget.agentUsage,
      ],
    );
  }

  _UsageHeightBounds _usageHeightBounds(double availableHeight) {
    final usableHeight = math.max(0.0, availableHeight - IdeSpacing.space8);
    final maxWhilePreservingProjects = math.max(
      0.0,
      usableHeight - IdeMetrics.projectsPaneMinHeight,
    );
    if (maxWhilePreservingProjects >= IdeMetrics.paneHeaderHeight) {
      final minimum = math.min(
        IdeMetrics.agentUsageExpandedMinHeight,
        maxWhilePreservingProjects,
      );
      return _UsageHeightBounds(min: minimum, max: maxWhilePreservingProjects);
    }
    final operableHeaderHeight = math.min(
      IdeMetrics.paneHeaderHeight,
      usableHeight,
    );
    return _UsageHeightBounds(
      min: operableHeaderHeight,
      max: operableHeaderHeight,
    );
  }

  double _resolveUsageHeight(
    double availableHeight,
    _UsageHeightBounds bounds,
  ) {
    final target = availableHeight * _previewFraction;
    return target.clamp(bounds.min, bounds.max);
  }
}

class _UsageHeightBounds {
  const _UsageHeightBounds({required this.min, required this.max});

  final double min;
  final double max;
}

import 'package:flutter/material.dart';

import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';

/// 时间线折叠组的业务类型；只用于生成稳定的既有 Widget key。
enum AgentTimelineGroupKind {
  command,
  fileEdit;

  String get _keySegment => switch (this) {
    AgentTimelineGroupKind.command => 'command-group',
    AgentTimelineGroupKind.fileEdit => 'file-edit-group',
  };
}

/// 命令组与文件编辑组共用的折叠卡骨架。
///
/// 展开状态仍由调用方拥有；本组件只统一 key、标题排版、leading 图标、正文间距
/// 和 hover 表面，避免把 conversation slice 状态与 Widget 局部状态混为一谈。
class AgentTimelineGroupCard extends StatelessWidget {
  const AgentTimelineGroupCard({
    required this.kind,
    required this.groupId,
    required this.expanded,
    required this.onToggle,
    required this.titleSpan,
    required this.leadingIcon,
    required this.semanticLabel,
    required this.body,
    super.key,
  });

  final AgentTimelineGroupKind kind;
  final String groupId;
  final bool expanded;
  final VoidCallback onToggle;
  final InlineSpan titleSpan;
  final IconData leadingIcon;
  final String semanticLabel;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final keyStem = 'agent-${kind._keySegment}';
    return IdeCollapsibleCard(
      headerKey: ValueKey<String>('$keyStem-header-$groupId'),
      bodyKey: ValueKey<String>('$keyStem-body-$groupId'),
      expanded: expanded,
      onToggle: onToggle,
      titleWidget: Text.rich(
        key: ValueKey<String>('$keyStem-summary-$groupId'),
        titleSpan,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: agentSummaryTextStyle(context),
      ),
      leading: Icon(
        leadingIcon,
        size: 14,
        color: colors.textTertiary.withValues(alpha: 0.65),
      ),
      bodyPadding: const EdgeInsets.only(
        top: IdeSpacing.space8,
        left: IdeSpacing.space20,
      ),
      hoverBackgroundColor: agentHoverBackground(context),
      semanticLabel: semanticLabel,
      body: body,
    );
  }
}

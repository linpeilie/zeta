import 'package:flutter/material.dart';

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_views.dart';
import 'package:zeta/src/ui/core/ide_collapsible_card.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';

/// 只消费 typed projection 的文件变更卡；展开状态由时间线持有。
class AgentFileChangeEvidenceCard extends StatelessWidget {
  const AgentFileChangeEvidenceCard({
    required this.item,
    required this.status,
    required this.expanded,
    required this.onToggle,
    super.key,
  });

  final AgentFileChangeItemProjection item;
  final AgentToolStatus? status;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final detail = item.detail;
    final statusPresentation = status == null ? null : _status(status!, colors);
    final statusLabel = statusPresentation?.$1;
    final statusColor = statusPresentation?.$2;
    final action = _action(item.kind);
    final detailLabel = _detailLabel(detail);
    return RepaintBoundary(
      key: agentFileChangeEvidenceKey(item.ownerEntryId, item.changeId, 'card'),
      child: IdeCollapsibleCard(
        headerKey: agentFileChangeEvidenceKey(
          item.ownerEntryId,
          item.changeId,
          'header',
        ),
        toggleKey: agentFileChangeEvidenceKey(
          item.ownerEntryId,
          item.changeId,
          'toggle',
        ),
        bodyKey: agentFileChangeEvidenceKey(
          item.ownerEntryId,
          item.changeId,
          'body',
        ),
        expanded: detail != null && expanded,
        canExpand: detail != null,
        onToggle: detail == null ? _noop : onToggle,
        padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space2),
        bodyPadding: const EdgeInsets.only(top: IdeSpacing.space6),
        summaryPadding: const EdgeInsets.only(
          top: IdeSpacing.space4,
          left: IdeSpacing.space20,
        ),
        hoverBackgroundColor: colors.border.withValues(alpha: 0.12),
        semanticLabel: [
          '$action ${item.path}',
          detailLabel,
          ?statusLabel,
        ].join('，'),
        leading: Icon(
          _icon(item.kind),
          size: 14,
          color: statusColor ?? colors.textTertiary,
        ),
        titleWidget: _Title(
          item: item,
          action: action,
          statusLabel: statusLabel,
          statusColor: statusColor,
        ),
        summaryWidget: _Summary(item: item, detailLabel: detailLabel),
        body: detail == null
            ? null
            : KeyedSubtree(
                key: agentFileChangeEvidenceKey(
                  item.ownerEntryId,
                  item.changeId,
                  'detail',
                ),
                child: switch (detail) {
                  AgentTextReplacementDetailProjection() =>
                    AgentTextReplacementEvidenceView(
                      ownerEntryId: item.ownerEntryId,
                      changeId: item.changeId,
                      detail: detail,
                    ),
                  AgentWrittenContentDetailProjection() =>
                    AgentWrittenContentEvidenceView(
                      ownerEntryId: item.ownerEntryId,
                      changeId: item.changeId,
                      detail: detail,
                      statusLabel: statusLabel ?? '本回合汇总',
                    ),
                  AgentUnifiedPatchDetailProjection() =>
                    AgentUnifiedPatchEvidenceView(
                      ownerEntryId: item.ownerEntryId,
                      changeId: item.changeId,
                      detail: detail,
                    ),
                },
              ),
      ),
    );
  }
}

class _Title extends StatelessWidget {
  const _Title({
    required this.item,
    required this.action,
    this.statusLabel,
    this.statusColor,
  });

  final AgentFileChangeItemProjection item;
  final String action;
  final String? statusLabel;
  final Color? statusColor;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final statistics = item.statistics;
    return Row(
      children: <Widget>[
        Text(action, style: styles.caption),
        const SizedBox(width: IdeSpacing.space6),
        Expanded(
          child: Text(
            _path(item),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.codeSmall.copyWith(color: colors.textPrimary),
          ),
        ),
        if (statusLabel case final label?) ...<Widget>[
          const SizedBox(width: IdeSpacing.space8),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: styles.caption.copyWith(color: statusColor),
          ),
        ],
        if (statistics != null) ...<Widget>[
          const SizedBox(width: IdeSpacing.space8),
          if (statistics.addedLines == null && statistics.removedLines == null)
            Text('${statistics.totalLines} 行', style: styles.meta)
          else
            Semantics(
              label:
                  '新增 ${statistics.addedLines ?? 0} 行，删除 ${statistics.removedLines ?? 0} 行',
              child: Text.rich(
                TextSpan(
                  children: <InlineSpan>[
                    TextSpan(
                      text: '+${statistics.addedLines ?? 0}',
                      style: styles.meta.copyWith(color: colors.success),
                    ),
                    const TextSpan(text: '  '),
                    TextSpan(
                      text: '−${statistics.removedLines ?? 0}',
                      style: styles.meta.copyWith(color: colors.error),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ],
    );
  }
}

class _Summary extends StatelessWidget {
  const _Summary({required this.item, required this.detailLabel});

  final AgentFileChangeItemProjection item;
  final String detailLabel;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return Wrap(
      spacing: IdeSpacing.space8,
      runSpacing: IdeSpacing.space4,
      children: <Widget>[
        Text(
          detailLabel,
          key: item.detail == null
              ? agentFileChangeEvidenceKey(
                  item.ownerEntryId,
                  item.changeId,
                  'no-evidence',
                )
              : null,
          style: styles.meta,
        ),
        if (item.replayability == AgentFileChangeReplayability.liveOnly)
          Semantics(
            label: '本回合实时汇总，不可从历史恢复',
            child: Text(
              '本回合实时汇总',
              key: agentFileChangeEvidenceKey(
                item.ownerEntryId,
                item.changeId,
                'live-only',
              ),
              style: styles.caption.copyWith(color: colors.info),
            ),
          ),
      ],
    );
  }
}

(String, Color) _status(AgentToolStatus status, IdeColors colors) {
  return switch (status) {
    AgentToolStatus.pending => ('待执行', colors.warning),
    AgentToolStatus.inProgress => ('进行中', colors.info),
    AgentToolStatus.completed => ('已完成', colors.success),
    AgentToolStatus.failed => ('失败', colors.error),
    AgentToolStatus.cancelled => ('已取消', colors.textTertiary),
  };
}

String _action(AgentFileChangeKind kind) => switch (kind) {
  AgentFileChangeKind.created => '新建',
  AgentFileChangeKind.modified => '修改',
  AgentFileChangeKind.deleted => '删除',
  AgentFileChangeKind.moved => '移动',
  AgentFileChangeKind.unknown => '文件变更',
};

IconData _icon(AgentFileChangeKind kind) => switch (kind) {
  AgentFileChangeKind.created => Icons.note_add_outlined,
  AgentFileChangeKind.modified => Icons.edit_note_rounded,
  AgentFileChangeKind.deleted => Icons.delete_outline_rounded,
  AgentFileChangeKind.moved => Icons.drive_file_move_outline,
  AgentFileChangeKind.unknown => Icons.description_outlined,
};

String _detailLabel(AgentFileChangeDetailProjection? detail) =>
    switch (detail) {
      null => 'Provider 未提供内容证据',
      AgentTextReplacementDetailProjection(:final replaceAll) =>
        replaceAll == true ? '替换片段 · 全部匹配' : '替换片段',
      AgentWrittenContentDetailProjection() => '写入内容',
      AgentUnifiedPatchDetailProjection() => '统一差异',
    };

String _path(AgentFileChangeItemProjection item) =>
    item.destinationPath == null || item.destinationPath!.isEmpty
    ? item.path
    : '${item.path} → ${item.destinationPath}';

void _noop() {}

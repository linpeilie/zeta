import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// owner/change/role 组成的稳定 key；revision 与宽度不参与 identity。
ValueKey<Object> agentFileChangeEvidenceKey(
  String ownerEntryId,
  String changeId,
  String role, [
  int? index,
]) => ValueKey<Object>((ownerEntryId, changeId, role, index));

/// 替换片段：`< 640px` 上下排列，否则左右并排。
class AgentTextReplacementEvidenceView extends StatelessWidget {
  const AgentTextReplacementEvidenceView({
    required this.ownerEntryId,
    required this.changeId,
    required this.detail,
    super.key,
  });

  final String ownerEntryId;
  final String changeId;
  final AgentTextReplacementDetailProjection detail;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label:
          '替换片段，替换前 ${detail.beforeLines.length} 行，替换后 ${detail.afterLines.length} 行',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : IdeMetrics.contentMaxWidth;
          final stacked = width < IdeMetrics.stackedRowBreakpoint;
          final panelWidth = stacked ? width : (width - IdeSpacing.space8) / 2;
          final alignedLines = math.max(
            detail.beforeLines.length,
            detail.afterLines.length,
          );
          // 固定 Wrap 拓扑；跨断点时只改宽度，不销毁内层滚动状态。
          return Wrap(
            spacing: IdeSpacing.space8,
            runSpacing: IdeSpacing.space8,
            children: <Widget>[
              SizedBox(
                width: panelWidth,
                child: _EvidencePanel(
                  key: agentFileChangeEvidenceKey(
                    ownerEntryId,
                    changeId,
                    'panel-before',
                  ),
                  owner: ownerEntryId,
                  changeId: changeId,
                  role: 'before',
                  title: context.l10n.agentEvidenceReplaceBefore,
                  count: detail.beforeLines.length,
                  viewportCount: alignedLines,
                  emptyLabel: context.l10n.agentEvidenceEmptySnippet,
                  lineAt: (index) => _LineData(
                    detail.beforeLines[index],
                    context.l10n.agentEvidenceRemove,
                    _LineTone.removed,
                    marker: '−',
                  ),
                ),
              ),
              SizedBox(
                width: panelWidth,
                child: _EvidencePanel(
                  key: agentFileChangeEvidenceKey(
                    ownerEntryId,
                    changeId,
                    'panel-after',
                  ),
                  owner: ownerEntryId,
                  changeId: changeId,
                  role: 'after',
                  title: context.l10n.agentEvidenceReplaceAfter,
                  count: detail.afterLines.length,
                  viewportCount: alignedLines,
                  emptyLabel: context.l10n.agentEvidenceEmptySnippet,
                  lineAt: (index) => _LineData(
                    detail.afterLines[index],
                    context.l10n.agentEvidenceAdd,
                    _LineTone.added,
                    marker: '+',
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 单侧写入内容 evidence。
class AgentWrittenContentEvidenceView extends StatelessWidget {
  const AgentWrittenContentEvidenceView({
    required this.ownerEntryId,
    required this.changeId,
    required this.detail,
    required this.statusLabel,
    super.key,
  });

  final String ownerEntryId;
  final String changeId;
  final AgentWrittenContentDetailProjection detail;
  final String statusLabel;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '写入内容，$statusLabel，共 ${detail.lines.length} 行',
    child: _EvidencePanel(
      key: agentFileChangeEvidenceKey(ownerEntryId, changeId, 'panel-written'),
      owner: ownerEntryId,
      changeId: changeId,
      role: 'written',
      title: context.l10n.agentWrittenContentWithStatus(
        context.l10n.agentWrittenContent,
        statusLabel,
      ),
      count: detail.lines.length,
      emptyLabel: context.l10n.agentEvidenceEmptyContent,
      lineAt: (index) => _LineData(
        detail.lines[index],
        context.l10n.agentEvidenceWrite,
        _LineTone.neutral,
      ),
    ),
  );
}

/// unified patch evidence，复用新增/删除/分块标题的 diff 视觉。
class AgentUnifiedPatchEvidenceView extends StatelessWidget {
  const AgentUnifiedPatchEvidenceView({
    required this.ownerEntryId,
    required this.changeId,
    required this.detail,
    super.key,
  });

  final String ownerEntryId;
  final String changeId;
  final AgentUnifiedPatchDetailProjection detail;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: '统一差异，共 ${detail.lines.length} 行',
    child: _EvidencePanel(
      key: agentFileChangeEvidenceKey(ownerEntryId, changeId, 'panel-patch'),
      owner: ownerEntryId,
      changeId: changeId,
      role: 'patch',
      title: context.l10n.agentUnifiedDiff,
      count: detail.lines.length,
      emptyLabel: context.l10n.agentEvidenceEmptyDiff,
      lineAt: (index) => _patchLine(detail.lines[index], context.l10n),
    ),
  );
}

enum _LineTone { neutral, added, removed, metadata, hunk }

@immutable
class _LineData {
  const _LineData(this.text, this.semanticKind, this.tone, {this.marker});

  final String text;
  final String semanticKind;
  final _LineTone tone;
  final String? marker;
}

_LineData _patchLine(
  AgentUnifiedPatchLineProjection line,
  AppLocalizations l10n,
) {
  return switch (line.kind) {
    AgentUnifiedPatchLineKind.metadata => _LineData(
      line.text,
      l10n.agentDiffMetadata,
      _LineTone.metadata,
    ),
    AgentUnifiedPatchLineKind.hunkHeader => _LineData(
      line.text,
      l10n.agentDiffHunkTitle,
      _LineTone.hunk,
    ),
    AgentUnifiedPatchLineKind.context => _LineData(
      line.text,
      l10n.agentContext,
      _LineTone.neutral,
    ),
    AgentUnifiedPatchLineKind.added => _LineData(
      line.text,
      l10n.agentEvidenceAdd,
      _LineTone.added,
    ),
    AgentUnifiedPatchLineKind.removed => _LineData(
      line.text,
      l10n.agentEvidenceRemove,
      _LineTone.removed,
    ),
  };
}

class _EvidencePanel extends StatelessWidget {
  const _EvidencePanel({
    required this.owner,
    required this.changeId,
    required this.role,
    required this.title,
    required this.count,
    required this.emptyLabel,
    required this.lineAt,
    this.viewportCount,
    super.key,
  });

  final String owner;
  final String changeId;
  final String role;
  final String title;
  final int count;
  final int? viewportCount;
  final String emptyLabel;
  final _LineData Function(int index) lineAt;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    return RepaintBoundary(
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: colors.controlSurface,
          borderRadius: IdeRadius.allSmall,
          border: Border.all(color: colors.borderSubtle),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: IdeSpacing.space8,
                vertical: IdeSpacing.space6,
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: styles.caption.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                  Text('$count 行', style: styles.meta),
                ],
              ),
            ),
            Container(
              height: _viewportHeight(context, viewportCount ?? count),
              decoration: BoxDecoration(
                color: colors.surfaceElevated,
                border: Border(top: BorderSide(color: colors.borderSubtle)),
              ),
              child: count == 0
                  ? Center(child: Text(emptyLabel, style: styles.codeSmall))
                  : _LazyLines(
                      key: agentFileChangeEvidenceKey(
                        owner,
                        changeId,
                        'viewport-$role',
                      ),
                      owner: owner,
                      changeId: changeId,
                      role: role,
                      label: '$title，可滚动，$count 行',
                      count: count,
                      lineAt: lineAt,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

double _viewportHeight(BuildContext context, int count) {
  if (count <= 0) return 52;
  final style = IdeTextStyles.of(context).codeSmall;
  final fontSize = MediaQuery.textScalerOf(context).scale(style.fontSize ?? 11);
  return (count * (fontSize * (style.height ?? 1.35) + IdeSpacing.space8))
      .clamp(52.0, 280.0)
      .toDouble();
}

class _LazyLines extends StatefulWidget {
  const _LazyLines({
    required this.owner,
    required this.changeId,
    required this.role,
    required this.label,
    required this.count,
    required this.lineAt,
    super.key,
  });

  final String owner;
  final String changeId;
  final String role;
  final String label;
  final int count;
  final _LineData Function(int index) lineAt;

  @override
  State<_LazyLines> createState() => _LazyLinesState();
}

class _LazyLinesState extends State<_LazyLines> {
  late final ScrollController _controller = ScrollController();
  late final FocusNode _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is! KeyDownEvent || !_controller.hasClients) {
      return KeyEventResult.ignored;
    }
    final position = _controller.position;
    final pixels = position.pixels;
    final page = math.max(position.viewportDimension * 0.85, 1);
    final step = math.max(position.viewportDimension / 8, 24);
    final target = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => pixels + step,
      LogicalKeyboardKey.arrowUp => pixels - step,
      LogicalKeyboardKey.pageDown => pixels + page,
      LogicalKeyboardKey.pageUp => pixels - page,
      LogicalKeyboardKey.home => position.minScrollExtent,
      LogicalKeyboardKey.end => position.maxScrollExtent,
      _ => null,
    };
    if (target == null) return KeyEventResult.ignored;
    _controller.jumpTo(
      target.clamp(position.minScrollExtent, position.maxScrollExtent),
    );
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: _onKey,
      onFocusChange: (value) => setState(() => _focused = value),
      child: Semantics(
        focusable: true,
        focused: _focused,
        label: widget.label,
        hint: '使用方向键、Page Up、Page Down、Home 或 End 滚动',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _focusNode.requestFocus,
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: _focused ? Border.all(color: colors.focusRing) : null,
            ),
            child: Scrollbar(
              controller: _controller,
              thumbVisibility: widget.count > 12,
              child: ListView.builder(
                controller: _controller,
                primary: false,
                padding: EdgeInsets.zero,
                scrollCacheExtent: const ScrollCacheExtent.pixels(80),
                prototypeItem: _EvidenceLine(index: 0, data: widget.lineAt(0)),
                itemCount: widget.count,
                itemBuilder: (context, index) => _EvidenceLine(
                  key: agentFileChangeEvidenceKey(
                    widget.owner,
                    widget.changeId,
                    'line-${widget.role}',
                    index,
                  ),
                  index: index,
                  data: widget.lineAt(index),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _EvidenceLine extends StatelessWidget {
  const _EvidenceLine({required this.index, required this.data, super.key});

  final int index;
  final _LineData data;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final styles = IdeTextStyles.of(context);
    final (foreground, background) = switch (data.tone) {
      _LineTone.neutral => (colors.textSecondary, colors.surfaceElevated),
      _LineTone.added => (
        colors.success,
        colors.success.withValues(alpha: 0.08),
      ),
      _LineTone.removed => (colors.error, colors.error.withValues(alpha: 0.08)),
      _LineTone.metadata => (colors.textTertiary, colors.surfaceElevated),
      _LineTone.hunk => (colors.info, colors.info.withValues(alpha: 0.08)),
    };
    final spoken = data.text.isEmpty ? '空行' : data.text;
    return Semantics(
      container: true,
      label: '${data.semanticKind}，第 ${index + 1} 行：$spoken',
      child: ColoredBox(
        color: background,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: IdeSpacing.space8,
            vertical: IdeSpacing.space4,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              SizedBox(
                width: 38,
                child: Text(
                  '${index + 1}',
                  textAlign: TextAlign.right,
                  style: styles.meta,
                ),
              ),
              const SizedBox(width: IdeSpacing.space8),
              if (data.marker case final marker?) ...<Widget>[
                SizedBox(
                  width: 12,
                  child: Text(marker, style: styles.codeSmall),
                ),
                const SizedBox(width: IdeSpacing.space4),
              ],
              Expanded(
                child: Text(
                  data.text.isEmpty ? ' ' : data.text,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.clip,
                  style: styles.codeSmall.copyWith(color: foreground),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

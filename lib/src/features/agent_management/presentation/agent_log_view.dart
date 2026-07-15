import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// Agent 磁盘日志或受控内存诊断的查看、搜索、复制和刷新页面。
class AgentLogView extends StatefulWidget {
  const AgentLogView({
    required this.controller,
    required this.onBack,
    super.key,
  });

  final AgentManagementController controller;
  final VoidCallback onBack;

  @override
  State<AgentLogView> createState() => _AgentLogViewState();
}

class _AgentLogViewState extends State<AgentLogView> {
  late final TextEditingController _searchController;
  AgentLogLevel? _level;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_refreshView);
    unawaited(widget.controller.loadLogs());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final entries = _filteredEntries(widget.controller.logs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: IdeSpacing.all12,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      sf.IconButton.ghost(
                        key: const ValueKey('agent-log-back-button'),
                        onPressed: widget.onBack,
                        size: sf.ButtonSize.small,
                        density: sf.ButtonDensity.iconDense,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      ),
                      const SizedBox(width: IdeSpacing.space8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${widget.controller.agent.definition.displayName} 运行日志',
                              style: textStyles.displaySmall.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              '${widget.controller.agent.logPaths.length} 个诊断来源 · '
                              '${widget.controller.logs.length} 行已加载',
                              style: textStyles.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      sf.OutlineButton(
                        onPressed: widget.controller.loadingLogs
                            ? null
                            : widget.controller.loadLogs,
                        size: sf.ButtonSize.small,
                        child: Text(
                          widget.controller.loadingLogs ? '刷新中…' : '刷新',
                        ),
                      ),
                      const SizedBox(width: IdeSpacing.space8),
                      sf.OutlineButton(
                        onPressed: entries.isEmpty
                            ? null
                            : () => _copy(entries),
                        size: sf.ButtonSize.small,
                        child: const Text('复制日志'),
                      ),
                    ],
                  ),
                  const SizedBox(height: IdeSpacing.space12),
                  LayoutBuilder(
                    builder: (context, constraints) {
                      final search = sf.TextField(
                        key: const ValueKey('agent-log-search'),
                        controller: _searchController,
                        placeholder: const Text('搜索日志关键词'),
                        features: const <sf.InputFeature>[
                          sf.InputFeature.leading(
                            Icon(Icons.search_rounded, size: 18),
                          ),
                        ],
                      );
                      final filters = IdeTabs<AgentLogLevel?>(
                        value: _level,
                        semanticLabel: '日志级别',
                        items: const [
                          IdeTabItem<AgentLogLevel?>(value: null, label: '全部'),
                          IdeTabItem<AgentLogLevel?>(
                            value: AgentLogLevel.debug,
                            label: 'Debug',
                          ),
                          IdeTabItem<AgentLogLevel?>(
                            value: AgentLogLevel.info,
                            label: 'Info',
                          ),
                          IdeTabItem<AgentLogLevel?>(
                            value: AgentLogLevel.warning,
                            label: 'Warning',
                          ),
                          IdeTabItem<AgentLogLevel?>(
                            value: AgentLogLevel.error,
                            label: 'Error',
                          ),
                        ],
                        onChanged: (value) {
                          setState(() {
                            _level = value;
                          });
                        },
                      );
                      if (constraints.maxWidth < 720) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            search,
                            const SizedBox(height: IdeSpacing.space8),
                            filters,
                          ],
                        );
                      }
                      return Row(
                        children: [
                          Expanded(child: search),
                          const SizedBox(width: IdeSpacing.space12),
                          Flexible(child: filters),
                        ],
                      );
                    },
                  ),
                ],
              ),
            ),
            Expanded(
              child:
                  widget.controller.loadingLogs &&
                      widget.controller.logs.isEmpty
                  ? const Center(
                      child: IdeLoadingIndicator(
                        width: 32,
                        height: 14,
                        semanticsLabel: '正在读取 Agent 日志',
                      ),
                    )
                  : entries.isEmpty
                  ? const EmptyState(text: '没有符合当前条件的日志。')
                  : ListView.builder(
                      key: const ValueKey('agent-log-list'),
                      padding: IdeSpacing.all12,
                      itemCount: entries.length,
                      itemBuilder: (context, index) {
                        return _LogRow(
                          key: ValueKey<String>(entries[index].id),
                          entry: entries[index],
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  List<AgentLogEntry> _filteredEntries(List<AgentLogEntry> entries) {
    final query = _searchController.text.trim().toLowerCase();
    return entries
        .where((entry) {
          if (_level != null && entry.level != _level) {
            return false;
          }
          if (query.isEmpty) {
            return true;
          }
          return entry.message.toLowerCase().contains(query) ||
              entry.sourcePath.toLowerCase().contains(query);
        })
        .toList(growable: false);
  }

  Future<void> _copy(List<AgentLogEntry> entries) async {
    final text = entries
        .map((entry) {
          final timestamp = entry.timestamp?.toIso8601String() ?? '--';
          return '$timestamp ${entry.level.name.toUpperCase()} ${entry.message}';
        })
        .join('\n');
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showIdeToast(context, message: '已复制 ${entries.length} 行脱敏日志。');
    }
  }

  void _refreshView() {
    if (mounted) {
      setState(() {});
    }
  }
}

class _LogRow extends StatelessWidget {
  const _LogRow({required this.entry, super.key});

  final AgentLogEntry entry;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tone = switch (entry.level) {
      AgentLogLevel.debug => colors.textTertiary,
      AgentLogLevel.info => colors.info,
      AgentLogLevel.warning => colors.warning,
      AgentLogLevel.error => colors.error,
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space4),
      child: PanelCard(
        borderColor: tone.withValues(alpha: 0.22),
        child: Padding(
          padding: IdeSpacing.all8,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 68,
                child: Text(
                  entry.level.name.toUpperCase(),
                  style: textStyles.codeSmall.copyWith(
                    color: tone,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Expanded(
                child: SelectableText(
                  entry.message,
                  style: textStyles.codeSmall.copyWith(
                    color: colors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: IdeSpacing.space8),
              Text(
                File(entry.sourcePath).uri.pathSegments.last,
                style: textStyles.caption.copyWith(color: colors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

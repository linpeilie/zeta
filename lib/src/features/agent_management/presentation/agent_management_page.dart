import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_configuration_editor.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_log_view.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/metrics/compact_metric_bar.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';
import 'package:zeta/src/ui/core/workbench/ide_section.dart';
import 'package:zeta/src/ui/core/workbench/ide_toolbar.dart';

/// 设置中的 Agent 管理列表、详情、配置和日志页面。
class AgentManagementPage extends StatefulWidget {
  const AgentManagementPage({
    required this.controller,
    this.autoDetect = true,
    super.key,
  });

  final AgentManagementController controller;
  final bool autoDetect;

  @override
  State<AgentManagementPage> createState() => AgentManagementPageState();
}

/// 设置容器通过该状态检查配置编辑器是否可以安全离开。
class AgentManagementPageState extends State<AgentManagementPage> {
  final GlobalKey<AgentConfigurationEditorState> _configurationKey =
      GlobalKey<AgentConfigurationEditorState>();
  late final TextEditingController _searchController;
  late final TextEditingController _timeoutController;
  _ManagementView _view = _ManagementView.list;
  _AgentListTab _listTab = _AgentListTab.installed;
  _AgentListFilter _filter = _AgentListFilter.all;
  _AgentDetailTab _detailTab = _AgentDetailTab.overview;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_refreshView);
    _timeoutController = TextEditingController(text: '60');
    unawaited(widget.controller.initialize(autoDetect: widget.autoDetect));
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
    _timeoutController.dispose();
    super.dispose();
  }

  Future<bool> confirmCanLeave() async {
    return await _configurationKey.currentState?.confirmCanLeave() ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return IdeSurface.canvas(
      key: const ValueKey('agent-management-page'),
      child: switch (_view) {
        _ManagementView.list => _buildListPage(context),
        _ManagementView.detail => _buildDetailPage(context),
        _ManagementView.logs => AgentLogView(
          controller: widget.controller,
          onBack: () {
            setState(() {
              _view = _ManagementView.detail;
            });
          },
        ),
      },
    );
  }

  Widget _buildListPage(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final allAgents = widget.controller.agents;
        final visibleAgents = allAgents
            .where(_matchesList)
            .toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdePageHeader(
              title: 'Agent 管理',
              subtitle: '管理本机已安装及当前应用支持的 Agent',
              leading: Icon(
                Icons.smart_toy_outlined,
                size: 20,
                color: colors.accent,
              ),
              actions: [
                sf.PrimaryButton(
                  key: const ValueKey('agent-detect-button'),
                  onPressed: widget.controller.detecting
                      ? null
                      : widget.controller.detect,
                  size: sf.ButtonSize.small,
                  leading: widget.controller.detecting
                      ? const IdeLoadingIndicator(width: 18, height: 10)
                      : const Icon(Icons.radar_rounded, size: 16),
                  child: Text(
                    widget.controller.detecting ? '正在检测…' : '自动检测 Agent',
                  ),
                ),
              ],
            ),
            if (widget.controller.detecting &&
                widget.controller.detectionProgress != null)
              _DetectionProgressBanner(
                progress: widget.controller.detectionProgress!,
              ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final compact =
                      constraints.maxWidth < IdeMetrics.mediumBreakpoint;
                  return Padding(
                    padding: compact
                        ? IdeSpacing.pagePaddingCompact
                        : IdeSpacing.pagePadding,
                    child: Align(
                      alignment: Alignment.topCenter,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(
                          maxWidth: IdeMetrics.settingsContentMaxWidth,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            if (widget.controller.operationError
                                case final String error) ...[
                              IdeStatusCard(
                                tone: IdeStatusCardTone.error,
                                title: '操作未完成',
                                body: Text(
                                  error,
                                  style: textStyles.bodySmall.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: IdeSpacing.space12),
                            ],
                            _buildSummary(context, allAgents),
                            const SizedBox(height: IdeSpacing.space12),
                            _buildListToolbar(context),
                            const SizedBox(height: IdeSpacing.space8),
                            Expanded(
                              child: visibleAgents.isEmpty
                                  ? _buildListEmptyState(context, allAgents)
                                  : IdeSurface.pane(
                                      key: const ValueKey('agent-list-pane'),
                                      child: ListView.builder(
                                        key: const ValueKey(
                                          'agent-management-list',
                                        ),
                                        itemCount: visibleAgents.length,
                                        itemBuilder: (context, index) {
                                          final agent = visibleAgents[index];
                                          return _AgentListRow(
                                            agent: agent,
                                            showDivider:
                                                index <
                                                visibleAgents.length - 1,
                                            onOpen: () => _openDetail(
                                              agent.definition.id,
                                            ),
                                            onEnabledChanged: (enabled) =>
                                                _setEnabled(
                                                  agent.definition.id,
                                                  enabled,
                                                ),
                                          );
                                        },
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummary(BuildContext context, List<ManagedAgent> agents) {
    final colors = IdeColors.of(context);
    final installed = agents.where((agent) => agent.installed).length;
    final enabled = agents
        .where((agent) => agent.enabled && agent.installed)
        .length;
    final running = agents
        .where((agent) => agent.runtimeState == AgentRuntimeState.running)
        .length;
    final attention = agents.where((agent) => agent.needsAttention).length;
    return CompactMetricBar(
      items: [
        CompactMetricItem(
          label: '已安装',
          value: '$installed',
          icon: Icons.download_done_rounded,
          onPressed: () {
            setState(() {
              _listTab = _AgentListTab.installed;
              _filter = _AgentListFilter.all;
            });
          },
        ),
        CompactMetricItem(
          label: '已启用',
          value: '$enabled',
          icon: Icons.toggle_on_outlined,
          onPressed: () {
            setState(() {
              _listTab = _AgentListTab.supported;
              _filter = _AgentListFilter.enabled;
            });
          },
        ),
        CompactMetricItem(
          label: '运行中',
          value: '$running',
          icon: Icons.play_circle_outline_rounded,
          onPressed: () {
            setState(() {
              _filter = _AgentListFilter.running;
            });
          },
        ),
        CompactMetricItem(
          label: '需要处理',
          value: '$attention',
          icon: Icons.warning_amber_rounded,
          tone: attention > 0 ? colors.warning : null,
          onPressed: () {
            setState(() {
              _filter = _AgentListFilter.attention;
            });
          },
        ),
      ],
    );
  }

  Widget _buildListToolbar(BuildContext context) {
    return IdeToolbar(
      key: const ValueKey('agent-list-toolbar'),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final searchWidth = constraints.maxWidth < 280
              ? constraints.maxWidth
              : 280.0;
          return Wrap(
            spacing: IdeSpacing.space8,
            runSpacing: IdeSpacing.space8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              IdeTabs<_AgentListTab>(
                value: _listTab,
                semanticLabel: 'Agent 列表范围',
                items: const [
                  IdeTabItem<_AgentListTab>(
                    key: ValueKey('agent-tab-installed'),
                    value: _AgentListTab.installed,
                    label: '已安装',
                  ),
                  IdeTabItem<_AgentListTab>(
                    key: ValueKey('agent-tab-supported'),
                    value: _AgentListTab.supported,
                    label: '全部支持',
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _listTab = value;
                  });
                },
              ),
              IdeTabs<_AgentListFilter>(
                value: _filter,
                semanticLabel: 'Agent 状态筛选',
                items: const [
                  IdeTabItem<_AgentListFilter>(
                    key: ValueKey('agent-filter-all'),
                    value: _AgentListFilter.all,
                    label: '全部状态',
                  ),
                  IdeTabItem<_AgentListFilter>(
                    key: ValueKey('agent-filter-enabled'),
                    value: _AgentListFilter.enabled,
                    label: '已启用',
                  ),
                  IdeTabItem<_AgentListFilter>(
                    key: ValueKey('agent-filter-attention'),
                    value: _AgentListFilter.attention,
                    label: '需要处理',
                  ),
                  IdeTabItem<_AgentListFilter>(
                    key: ValueKey('agent-filter-running'),
                    value: _AgentListFilter.running,
                    label: '运行中',
                  ),
                  IdeTabItem<_AgentListFilter>(
                    key: ValueKey('agent-filter-update'),
                    value: _AgentListFilter.updateAvailable,
                    label: '可更新',
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _filter = value;
                  });
                },
              ),
              SizedBox(
                width: searchWidth,
                child: sf.TextField(
                  key: const ValueKey('agent-search-field'),
                  controller: _searchController,
                  placeholder: const Text('搜索 Agent 或厂商'),
                  features: const <sf.InputFeature>[
                    sf.InputFeature.leading(
                      Icon(Icons.search_rounded, size: 18),
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildListEmptyState(BuildContext context, List<ManagedAgent> agents) {
    final installedTab = _listTab == _AgentListTab.installed;
    final noQuery =
        _searchController.text.trim().isEmpty &&
        _filter == _AgentListFilter.all;
    final anyInstalled = agents.any((agent) => agent.installed);
    if (installedTab && !anyInstalled && noQuery) {
      return _ActionEmptyState(
        icon: Icons.travel_explore_rounded,
        title: '暂未检测到已安装的 Agent',
        description: '可以自动检测本机环境，或者前往“全部支持”查看当前应用支持的 Agent。',
        primaryLabel: '自动检测 Agent',
        onPrimary: widget.controller.detect,
        secondaryLabel: '查看全部支持',
        onSecondary: () {
          setState(() {
            _listTab = _AgentListTab.supported;
          });
        },
      );
    }
    return _ActionEmptyState(
      icon: Icons.search_off_rounded,
      title: '没有找到匹配的 Agent',
      description: '请尝试修改搜索内容或清除筛选条件。',
      primaryLabel: '清除筛选',
      onPrimary: () {
        _searchController.clear();
        setState(() {
          _filter = _AgentListFilter.all;
        });
      },
    );
  }

  Widget _buildDetailPage(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final agent = widget.controller.agent;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            IdePageHeader(
              title: agent.definition.displayName,
              subtitle:
                  '${agent.definition.vendor} · ${agent.definition.commandName} · '
                  '版本 ${agent.currentVersion ?? '未知'}',
              leading: sf.IconButton.ghost(
                key: const ValueKey('agent-detail-back-button'),
                onPressed: _backToList,
                size: sf.ButtonSize.small,
                density: sf.ButtonDensity.iconDense,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              actions: [
                sf.OutlineButton(
                  key: const ValueKey('agent-test-connection-button'),
                  onPressed: agent.installed && !widget.controller.testing
                      ? _testConnection
                      : null,
                  size: sf.ButtonSize.small,
                  child: Text(widget.controller.testing ? '正在测试…' : '测试连接'),
                ),
                sf.OutlineButton(
                  key: const ValueKey('agent-open-logs-button'),
                  onPressed: agent.logPaths.isEmpty ? null : _openLogs,
                  size: sf.ButtonSize.small,
                  child: const Text('查看运行日志'),
                ),
                sf.OutlineButton(
                  onPressed: agent.installed
                      ? () => _setEnabled(agent.definition.id, !agent.enabled)
                      : null,
                  size: sf.ButtonSize.small,
                  child: Text(agent.enabled ? '禁用 Agent' : '启用 Agent'),
                ),
              ],
            ),
            IdeToolbar(
              child: Wrap(
                spacing: IdeSpacing.space12,
                runSpacing: IdeSpacing.space8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _AgentDetailStatusSummary(agent: agent),
                  IdeTabs<_AgentDetailTab>(
                    value: _detailTab,
                    semanticLabel: 'Agent 详情',
                    items: const [
                      IdeTabItem<_AgentDetailTab>(
                        key: ValueKey('agent-detail-tab-overview'),
                        value: _AgentDetailTab.overview,
                        label: '基础信息',
                      ),
                      IdeTabItem<_AgentDetailTab>(
                        key: ValueKey('agent-detail-tab-models'),
                        value: _AgentDetailTab.models,
                        label: '模型',
                      ),
                      IdeTabItem<_AgentDetailTab>(
                        key: ValueKey('agent-detail-tab-configuration'),
                        value: _AgentDetailTab.configuration,
                        label: '配置',
                      ),
                    ],
                    onChanged: _selectDetailTab,
                  ),
                ],
              ),
            ),
            Expanded(
              child: switch (_detailTab) {
                _AgentDetailTab.overview => _buildOverview(context, agent),
                _AgentDetailTab.models => _buildModels(context, agent),
                _AgentDetailTab.configuration => AgentConfigurationEditor(
                  key: _configurationKey,
                  controller: widget.controller,
                ),
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildOverview(BuildContext context, ManagedAgent agent) {
    return SingleChildScrollView(
      padding: IdeSpacing.all16,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final information = _AgentInformationCard(
            agent: agent,
            timeoutController: _timeoutController,
            onSelectExecutable: _selectExecutable,
            onDetect: widget.controller.detect,
            onOpenExecutableDirectory: _openExecutableDirectory,
            onSaveTimeout: _saveTimeout,
            onCopyCommand: () =>
                _copyText(agent.definition.commandName, '已复制启动命令。'),
          );
          final diagnostics = _AgentDiagnosticsCard(
            agent: agent,
            onDetect: widget.controller.detect,
            onSelectExecutable: _selectExecutable,
          );
          if (constraints.maxWidth < 780) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                const SizedBox(height: IdeSpacing.space12),
                diagnostics,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: information),
              const SizedBox(width: IdeSpacing.space12),
              Expanded(flex: 2, child: diagnostics),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModels(BuildContext context, ManagedAgent agent) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    if (agent.models.isEmpty) {
      return _ActionEmptyState(
        icon: Icons.view_in_ar_outlined,
        title: '无法加载模型列表',
        description: agent.accountState == AgentAccountState.loggedOut
            ? '当前账号尚未登录。登录 Codex 后重新加载。'
            : 'Codex app-server 未返回模型，或当前配置无法完成握手。',
        primaryLabel: '重新加载',
        onPrimary: _testConnection,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: IdeSpacing.all12,
          child: Text(
            '数据来源：${agent.modelSource ?? 'Codex app-server'} · '
            '更新时间：${_relativeTime(agent.modelsUpdatedAt)}',
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        Expanded(
          child: ListView.builder(
            key: const ValueKey('agent-model-list'),
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            itemCount: agent.models.length,
            itemBuilder: (context, index) => _ModelCard(
              key: ValueKey<String>('agent-model-${agent.models[index].id}'),
              model: agent.models[index],
            ),
          ),
        ),
      ],
    );
  }

  bool _matchesList(ManagedAgent agent) {
    if (_listTab == _AgentListTab.installed && !agent.installed) {
      return false;
    }
    final query = _searchController.text.trim().toLowerCase();
    if (query.isNotEmpty &&
        !agent.definition.displayName.toLowerCase().contains(query) &&
        !agent.definition.vendor.toLowerCase().contains(query) &&
        !agent.definition.commandName.toLowerCase().contains(query)) {
      return false;
    }
    return switch (_filter) {
      _AgentListFilter.all => true,
      _AgentListFilter.enabled => agent.enabled,
      _AgentListFilter.attention => agent.needsAttention,
      _AgentListFilter.running =>
        agent.runtimeState == AgentRuntimeState.running,
      _AgentListFilter.updateAvailable => agent.updateAvailable,
    };
  }

  void _openDetail(String agentId) {
    widget.controller.selectAgent(agentId);
    _timeoutController.text = '${widget.controller.agent.timeoutSeconds}';
    setState(() {
      _view = _ManagementView.detail;
      _detailTab = _AgentDetailTab.overview;
    });
  }

  Future<void> _backToList() async {
    if (!await confirmCanLeave() || !mounted) {
      return;
    }
    setState(() {
      _view = _ManagementView.list;
      _detailTab = _AgentDetailTab.overview;
    });
  }

  Future<void> _selectDetailTab(_AgentDetailTab value) async {
    if (_detailTab == value) {
      return;
    }
    if (_detailTab == _AgentDetailTab.configuration &&
        !await confirmCanLeave()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _detailTab = value;
    });
  }

  Future<void> _openLogs() async {
    if (_detailTab == _AgentDetailTab.configuration &&
        !await confirmCanLeave()) {
      return;
    }
    if (!mounted) {
      return;
    }
    setState(() {
      _view = _ManagementView.logs;
    });
  }

  Future<void> _setEnabled(String agentId, bool enabled) async {
    widget.controller.selectAgent(agentId);
    final agent = widget.controller.agent;
    if (!enabled && agent.runtimeState == AgentRuntimeState.running) {
      final confirmed = await showIdeDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => IdeDialog(
          title: Text('${agent.definition.displayName} 当前正在运行'),
          content: const Text('禁用后将停止当前任务，已有会话会变为只读模式。'),
          actions: <IdeDialogAction>[
            IdeDialogAction.cancel(
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IdeDialogAction.destructive(
              label: '停止并禁用',
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true) {
        return;
      }
    }
    await widget.controller.setEnabled(enabled);
  }

  Future<void> _testConnection() async {
    final result = await widget.controller.testConnection();
    if (!mounted || result == null) {
      return;
    }
    showIdeToast(
      context,
      message: result.success
          ? '连接测试成功，响应耗时 ${result.elapsed.inMilliseconds} ms。'
          : '连接测试失败：${result.message ?? '未知错误'}',
      tone: result.success ? IdeToastTone.success : IdeToastTone.error,
    );
  }

  Future<void> _selectExecutable() async {
    final file = await openFile(
      acceptedTypeGroups: <XTypeGroup>[
        if (Platform.isWindows)
          const XTypeGroup(
            label: 'Codex executable',
            extensions: <String>['exe', 'ps1', 'cmd', 'bat'],
          )
        else
          const XTypeGroup(label: 'Codex executable'),
      ],
    );
    if (file == null) {
      return;
    }
    try {
      await widget.controller.setExecutablePath(file.path);
    } catch (error) {
      if (mounted) {
        showIdeToast(
          context,
          message: '无法使用所选可执行文件：$error',
          tone: IdeToastTone.error,
        );
      }
    }
  }

  Future<void> _openExecutableDirectory() async {
    final path = widget.controller.agent.executablePath;
    if (path == null) {
      return;
    }
    try {
      await openPathInSystemFileManager(File(path).parent.path);
    } catch (error) {
      if (mounted) {
        showIdeToast(
          context,
          message: '无法打开可执行文件目录：$error',
          tone: IdeToastTone.error,
        );
      }
    }
  }

  Future<void> _saveTimeout() async {
    final value = int.tryParse(_timeoutController.text.trim());
    if (value == null || !await widget.controller.setTimeoutSeconds(value)) {
      if (mounted) {
        showIdeToast(
          context,
          message: '超时时间必须是 5 到 600 之间的整数。',
          tone: IdeToastTone.error,
        );
      }
      return;
    }
    if (mounted) {
      showIdeToast(context, message: 'Agent 超时时间已保存。');
    }
  }

  Future<void> _copyText(String text, String message) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      showIdeToast(context, message: message);
    }
  }

  void _refreshView() {
    if (mounted) {
      setState(() {});
    }
  }
}

enum _ManagementView { list, detail, logs }

enum _AgentListTab { installed, supported }

enum _AgentListFilter { all, enabled, attention, running, updateAvailable }

enum _AgentDetailTab { overview, models, configuration }

class _AgentDetailStatusSummary extends StatelessWidget {
  const _AgentDetailStatusSummary({required this.agent});

  final ManagedAgent agent;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Row(
      key: const ValueKey('agent-detail-status-summary'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _AgentLogo(providerId: agent.definition.id, installed: agent.installed),
        const SizedBox(width: IdeSpacing.space8),
        _AgentStatusText(status: _priorityAgentStatus(colors, agent)),
      ],
    );
  }
}

class _DetectionProgressBanner extends StatelessWidget {
  const _DetectionProgressBanner({required this.progress});

  final AgentDetectionProgress progress;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Container(
      key: const ValueKey('agent-detection-progress-bar'),
      constraints: const BoxConstraints(minHeight: IdeMetrics.compactRowHeight),
      padding: IdeSpacing.horizontal12,
      decoration: BoxDecoration(
        color: colors.info.withValues(alpha: 0.06),
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(Icons.radar_rounded, size: 14, color: colors.info),
          const SizedBox(width: IdeSpacing.space6),
          Expanded(
            flex: 3,
            child: Text(
              progress.message,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Expanded(
            flex: 2,
            child: sf.Progress(
              progress: progress.total == 0
                  ? null
                  : progress.completed / progress.total,
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          Text(
            '${progress.completed}/${progress.total}',
            style: textStyles.codeSmall.copyWith(color: colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _AgentListRow extends StatelessWidget {
  const _AgentListRow({
    required this.agent,
    required this.onOpen,
    required this.onEnabledChanged,
    required this.showDivider,
  });

  final ManagedAgent agent;
  final VoidCallback onOpen;
  final ValueChanged<bool> onEnabledChanged;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxWidth < 760;
        return IdeListRow(
          key: ValueKey('agent-row-${agent.definition.id}'),
          title: agent.definition.displayName,
          subtitle: agent.definition.commandName,
          leading: _AgentLogo(
            providerId: agent.definition.id,
            installed: agent.installed,
          ),
          trailing: _AgentRowStatus(
            agent: agent,
            compact: compact,
            onEnabledChanged: onEnabledChanged,
          ),
          showDivider: showDivider,
          semanticLabel: '查看 ${agent.definition.displayName} 详情',
          onPressed: onOpen,
        );
      },
    );
  }
}

class _AgentRowStatus extends StatelessWidget {
  const _AgentRowStatus({
    required this.agent,
    required this.compact,
    required this.onEnabledChanged,
  });

  final ManagedAgent agent;
  final bool compact;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    if (compact) {
      final status = _priorityAgentStatus(colors, agent);
      return Row(
        key: const ValueKey('agent-row-status-compact'),
        mainAxisSize: MainAxisSize.min,
        children: [
          _AgentStatusText(status: status),
          const SizedBox(width: IdeSpacing.space4),
          Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: colors.textTertiary,
          ),
        ],
      );
    }

    final accountNeedsAttention = switch (agent.accountState) {
      AgentAccountState.loggedOut || AgentAccountState.expired => true,
      _ => false,
    };
    final runtimeNeedsAttention = switch (agent.runtimeState) {
      AgentRuntimeState.error || AgentRuntimeState.unavailable => true,
      _ => false,
    };
    return Row(
      key: const ValueKey('agent-row-status-wide'),
      mainAxisSize: MainAxisSize.min,
      children: [
        if (agent.definition.isBeta) ...[
          StateLabel(text: 'Beta', color: colors.warning),
          const SizedBox(width: IdeSpacing.space8),
        ],
        SizedBox(
          width: 92,
          child: _AgentStatusText(
            status: _AgentStatus(
              label: agent.installed ? _accountLabel(agent.accountState) : '—',
              icon: accountNeedsAttention
                  ? Icons.account_circle_outlined
                  : Icons.person_outline_rounded,
              color: accountNeedsAttention
                  ? colors.warning
                  : colors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 96,
          child: _AgentStatusText(
            status: _AgentStatus(
              label: agent.currentVersion ?? '版本未知',
              icon: Icons.tag_rounded,
              color: agent.updateAvailable
                  ? colors.warning
                  : colors.textSecondary,
            ),
          ),
        ),
        SizedBox(
          width: 92,
          child: _AgentStatusText(
            status: _AgentStatus(
              label: agent.installed
                  ? _runtimeLabel(agent.runtimeState)
                  : '未安装',
              icon: runtimeNeedsAttention
                  ? Icons.error_outline_rounded
                  : Icons.circle_outlined,
              color: runtimeNeedsAttention
                  ? colors.error
                  : agent.installed
                  ? colors.textSecondary
                  : colors.warning,
            ),
          ),
        ),
        sf.Switch(
          value: agent.enabled,
          enabled: agent.installed,
          onChanged: agent.installed ? onEnabledChanged : null,
        ),
        const SizedBox(width: IdeSpacing.space6),
        Icon(Icons.chevron_right_rounded, size: 18, color: colors.textTertiary),
      ],
    );
  }
}

class _AgentStatusText extends StatelessWidget {
  const _AgentStatusText({required this.status});

  final _AgentStatus status;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(status.icon, size: 13, color: status.color),
        const SizedBox(width: IdeSpacing.space4),
        Flexible(
          child: Text(
            status.label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.meta.copyWith(color: status.color),
          ),
        ),
      ],
    );
  }
}

class _AgentStatus {
  const _AgentStatus({
    required this.label,
    required this.icon,
    required this.color,
  });

  final String label;
  final IconData icon;
  final Color color;
}

_AgentStatus _priorityAgentStatus(IdeColors colors, ManagedAgent agent) {
  if (agent.runtimeState == AgentRuntimeState.error ||
      agent.runtimeState == AgentRuntimeState.unavailable) {
    return _AgentStatus(
      label: _runtimeLabel(agent.runtimeState),
      icon: Icons.error_outline_rounded,
      color: colors.error,
    );
  }
  if (!agent.installed) {
    return _AgentStatus(
      label: '未安装',
      icon: Icons.download_for_offline_outlined,
      color: colors.warning,
    );
  }
  if (agent.accountState == AgentAccountState.loggedOut ||
      agent.accountState == AgentAccountState.expired) {
    return _AgentStatus(
      label: _accountLabel(agent.accountState),
      icon: Icons.account_circle_outlined,
      color: colors.warning,
    );
  }
  if (agent.updateAvailable) {
    return _AgentStatus(
      label: '可更新',
      icon: Icons.system_update_alt_rounded,
      color: colors.warning,
    );
  }
  if (agent.accountState == AgentAccountState.checking ||
      agent.runtimeState == AgentRuntimeState.starting ||
      agent.runtimeState == AgentRuntimeState.stopping) {
    return _AgentStatus(
      label: agent.accountState == AgentAccountState.checking
          ? '检测中'
          : _runtimeLabel(agent.runtimeState),
      icon: Icons.sync_rounded,
      color: colors.info,
    );
  }
  if (agent.definition.isBeta) {
    return _AgentStatus(
      label: 'Beta',
      icon: Icons.science_outlined,
      color: colors.warning,
    );
  }
  return _AgentStatus(
    label: agent.runtimeState == AgentRuntimeState.running
        ? '运行中'
        : agent.enabled
        ? '已启用'
        : '已安装',
    icon: agent.runtimeState == AgentRuntimeState.running
        ? Icons.play_circle_outline_rounded
        : agent.enabled
        ? Icons.toggle_on_outlined
        : Icons.download_done_rounded,
    color: colors.textSecondary,
  );
}

class _AgentLogo extends StatelessWidget {
  const _AgentLogo({required this.providerId, required this.installed});

  final String providerId;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: IdeRadius.allSmall,
        border: Border.all(color: colors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: AgentProviderIcon(
        providerId: providerId,
        size: 17,
        color: installed ? colors.textSecondary : colors.textTertiary,
      ),
    );
  }
}

class _ActionEmptyState extends StatelessWidget {
  const _ActionEmptyState({
    required this.icon,
    required this.title,
    required this.description,
    required this.primaryLabel,
    required this.onPrimary,
    this.secondaryLabel,
    this.onSecondary,
  });

  final IconData icon;
  final String title;
  final String description;
  final String primaryLabel;
  final VoidCallback onPrimary;
  final String? secondaryLabel;
  final VoidCallback? onSecondary;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 56),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 36, color: colors.textTertiary),
              const SizedBox(height: IdeSpacing.space12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: textStyles.titleLarge.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: IdeSpacing.space6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: IdeSpacing.space16),
              Wrap(
                spacing: IdeSpacing.space8,
                children: [
                  sf.PrimaryButton(
                    onPressed: onPrimary,
                    size: sf.ButtonSize.small,
                    child: Text(primaryLabel),
                  ),
                  if (secondaryLabel != null)
                    sf.OutlineButton(
                      onPressed: onSecondary,
                      size: sf.ButtonSize.small,
                      child: Text(secondaryLabel!),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AgentInformationCard extends StatelessWidget {
  const _AgentInformationCard({
    required this.agent,
    required this.timeoutController,
    required this.onSelectExecutable,
    required this.onDetect,
    required this.onOpenExecutableDirectory,
    required this.onSaveTimeout,
    required this.onCopyCommand,
  });

  final ManagedAgent agent;
  final TextEditingController timeoutController;
  final VoidCallback onSelectExecutable;
  final VoidCallback onDetect;
  final VoidCallback onOpenExecutableDirectory;
  final VoidCallback onSaveTimeout;
  final VoidCallback onCopyCommand;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeSection(
      title: '基础信息',
      child: IdeSurface.pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _InfoRow(label: '名称', value: agent.definition.displayName),
            _InfoRow(label: '厂商', value: agent.definition.vendor),
            _InfoRow(
              label: '启动命令',
              value: agent.definition.commandName,
              trailing: sf.IconButton.ghost(
                onPressed: onCopyCommand,
                size: sf.ButtonSize.xSmall,
                density: sf.ButtonDensity.iconDense,
                icon: const Icon(Icons.copy_rounded, size: 14),
              ),
            ),
            _InfoRow(label: '当前版本', value: agent.currentVersion ?? '未知'),
            _InfoRow(
              label: '最新版本',
              value: agent.latestVersion ?? '未知',
              valueColor: agent.updateAvailable ? colors.warning : null,
            ),
            _InfoRow(label: '通信协议', value: agent.definition.protocol),
            _InfoRow(label: '传输方式', value: agent.definition.transport),
            IdeSettingsRow(
              label: '可执行文件路径',
              description: agent.executablePath == null ? '尚未检测到可执行文件' : null,
              control: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (agent.executablePath case final String executablePath)
                    SelectableText(
                      executablePath,
                      maxLines: 2,
                      style: textStyles.codeSmall.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  const SizedBox(height: IdeSpacing.space6),
                  Wrap(
                    spacing: IdeSpacing.space6,
                    runSpacing: IdeSpacing.space6,
                    alignment: WrapAlignment.end,
                    children: [
                      sf.OutlineButton(
                        onPressed: onSelectExecutable,
                        size: sf.ButtonSize.small,
                        child: const Text('选择文件'),
                      ),
                      sf.OutlineButton(
                        onPressed: onDetect,
                        size: sf.ButtonSize.small,
                        child: const Text('自动检测'),
                      ),
                      sf.OutlineButton(
                        onPressed: agent.executablePath == null
                            ? null
                            : onOpenExecutableDirectory,
                        size: sf.ButtonSize.small,
                        child: const Text('打开目录'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            IdeSettingsRow(
              label: '超时时间',
              description: 'Agent 启动、握手或单次无响应等待的最大时长。',
              showDivider: false,
              control: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 120,
                    child: sf.TextField(
                      key: const ValueKey('agent-timeout-field'),
                      controller: timeoutController,
                      keyboardType: TextInputType.number,
                      features: const <sf.InputFeature>[
                        sf.InputFeature.trailing(Text('秒')),
                      ],
                    ),
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                  sf.OutlineButton(
                    onPressed: onSaveTimeout,
                    size: sf.ButtonSize.small,
                    child: const Text('保存'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    required this.value,
    this.trailing,
    this.valueColor,
  });

  final String label;
  final String value;
  final Widget? trailing;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    return IdeSettingsRow(
      label: label,
      control: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.end,
              style: textStyles.bodyMedium.copyWith(color: valueColor),
            ),
          ),
          if (trailing case final Widget trailingWidget) ...[
            const SizedBox(width: IdeSpacing.space4),
            trailingWidget,
          ],
        ],
      ),
    );
  }
}

class _AgentDiagnosticsCard extends StatelessWidget {
  const _AgentDiagnosticsCard({
    required this.agent,
    required this.onDetect,
    required this.onSelectExecutable,
  });

  final ManagedAgent agent;
  final VoidCallback onDetect;
  final VoidCallback onSelectExecutable;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final healthy =
        agent.installed &&
        agent.errorMessage == null &&
        agent.accountState == AgentAccountState.loggedIn;
    final diagnostics = <_DiagnosticEntry>[
      _DiagnosticEntry(
        label: '程序',
        value: agent.installed ? '可执行文件存在且可调用' : '未找到可执行文件',
      ),
      _DiagnosticEntry(label: '账号', value: _accountLabel(agent.accountState)),
      _DiagnosticEntry(
        label: '通信',
        value: agent.connectionTest?.protocolReady == true
            ? '握手成功'
            : agent.runtimeState == AgentRuntimeState.idle
            ? '基础握手正常'
            : '尚未确认',
      ),
      _DiagnosticEntry(
        label: '最近检测',
        value: _relativeTime(agent.lastDetectedAt),
      ),
      if (agent.connectionTest != null)
        _DiagnosticEntry(
          label: '最近测试耗时',
          value: '${agent.connectionTest!.elapsed.inMilliseconds} ms',
        ),
      if (agent.connectionTest?.protocolVersion case final String version)
        _DiagnosticEntry(label: '协议', value: version),
      if (agent.connectionTest?.agentName case final String agentName)
        _DiagnosticEntry(
          label: '握手身份',
          value:
              '$agentName'
              '${agent.connectionTest!.agentVersion == null ? '' : ' ${agent.connectionTest!.agentVersion}'}',
        ),
      if (agent.connectionTest?.capabilitySummary.isNotEmpty == true)
        _DiagnosticEntry(
          label: '协商能力',
          value: agent.connectionTest!.capabilitySummary.join(', '),
        ),
      if (agent.connectionTest?.compatibilitySummary
          case final String compatibility)
        _DiagnosticEntry(label: '兼容性', value: compatibility),
      if (agent.connectionTest?.success == false &&
          agent.connectionTest?.exitReason != null)
        _DiagnosticEntry(
          label: '退出原因',
          value: agent.connectionTest!.exitReason!,
        ),
      if (agent.errorStage case final AgentDiagnosticStage errorStage)
        _DiagnosticEntry(
          label: '异常阶段',
          value: _diagnosticStageLabel(errorStage),
        ),
    ];
    final hasSupplement =
        agent.errorDetails != null || agent.suggestion != null || !healthy;
    return IdeSection(
      title: '诊断',
      subtitle: healthy ? '连接正常' : (agent.errorMessage ?? '状态需要检查'),
      trailing: Icon(
        healthy ? Icons.check_circle_outline_rounded : Icons.error_outline,
        size: 17,
        color: healthy ? colors.textSecondary : colors.error,
      ),
      child: IdeSurface.pane(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var index = 0; index < diagnostics.length; index++)
              _DiagnosticLine(
                label: diagnostics[index].label,
                value: diagnostics[index].value,
                showDivider: index < diagnostics.length - 1 || hasSupplement,
              ),
            if (agent.errorDetails case final String errorDetails)
              Container(
                padding: IdeSpacing.all12,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: SelectableText(
                  errorDetails,
                  maxLines: 8,
                  style: textStyles.codeSmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            if (agent.suggestion case final String suggestion)
              Container(
                padding: IdeSpacing.all12,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: colors.borderSubtle),
                  ),
                ),
                child: Text(
                  '建议操作：$suggestion',
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ),
            if (!healthy)
              Padding(
                padding: IdeSpacing.all12,
                child: Wrap(
                  spacing: IdeSpacing.space8,
                  runSpacing: IdeSpacing.space8,
                  children: [
                    sf.OutlineButton(
                      onPressed: onDetect,
                      size: sf.ButtonSize.small,
                      child: const Text('自动检测'),
                    ),
                    sf.OutlineButton(
                      onPressed: onSelectExecutable,
                      size: sf.ButtonSize.small,
                      child: const Text('选择文件'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _DiagnosticEntry {
  const _DiagnosticEntry({required this.label, required this.value});

  final String label;
  final String value;
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({
    required this.label,
    required this.value,
    required this.showDivider,
  });

  final String label;
  final String value;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return IdeListRow(
      title: label,
      subtitle: value,
      leading: const Icon(Icons.circle_outlined),
      showDivider: showDivider,
    );
  }
}

class _ModelCard extends StatelessWidget {
  const _ModelCard({required this.model, super.key});

  final AgentModelInfo model;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final modalities = model.raw['inputModalities'];
    final supportsImage = modalities is List && modalities.contains('image');
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
      child: PanelCard(
        child: Padding(
          padding: IdeSpacing.all12,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(model.displayName, style: textStyles.rowTitle),
                        SelectableText(
                          model.model,
                          style: textStyles.codeSmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  StateLabel(
                    text: model.hidden ? '隐藏' : '可用',
                    color: model.hidden ? colors.textTertiary : colors.success,
                  ),
                ],
              ),
              if (model.description case final String description) ...[
                const SizedBox(height: IdeSpacing.space8),
                Text(
                  description,
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: IdeSpacing.space10),
              Wrap(
                spacing: IdeSpacing.space6,
                runSpacing: IdeSpacing.space6,
                children: [
                  const IdeChip(label: '文本'),
                  if (supportsImage) const IdeChip(label: '图片'),
                  const IdeChip(label: '代码'),
                  const IdeChip(label: '文件操作'),
                  const IdeChip(label: '工具调用'),
                  const IdeChip(label: '终端'),
                  const IdeChip(label: '流式输出'),
                ],
              ),
              const SizedBox(height: IdeSpacing.space8),
              Text(
                model.supportedReasoningEfforts.isEmpty
                    ? '思考能力：未知'
                    : '思考能力：可调节（${orderedReasoningEffortsForDisplay(model.supportedReasoningEfforts).map((item) => item.effort).join('、')}）',
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _accountLabel(AgentAccountState state) {
  return switch (state) {
    AgentAccountState.unknown => '无法检测',
    AgentAccountState.checking => '检测中',
    AgentAccountState.loggedIn => '已登录',
    AgentAccountState.loggedOut => '未登录',
    AgentAccountState.expired => '登录失效',
    AgentAccountState.notRequired => '无需登录',
    AgentAccountState.unavailable => '无法检测',
  };
}

String _runtimeLabel(AgentRuntimeState state) {
  return switch (state) {
    AgentRuntimeState.notRunning => '未运行',
    AgentRuntimeState.idle => '空闲',
    AgentRuntimeState.starting => '启动中',
    AgentRuntimeState.running => '运行中',
    AgentRuntimeState.stopping => '停止中',
    AgentRuntimeState.error => '异常',
    AgentRuntimeState.unavailable => '不可用',
    AgentRuntimeState.disabled => '已禁用',
  };
}

String _diagnosticStageLabel(AgentDiagnosticStage stage) {
  return switch (stage) {
    AgentDiagnosticStage.fileDetection => '文件检测',
    AgentDiagnosticStage.cliStartup => '进程启动',
    AgentDiagnosticStage.versionDetection => '版本检测',
    AgentDiagnosticStage.accountAuthentication => '账号认证',
    AgentDiagnosticStage.protocolHandshake => '协议握手',
    AgentDiagnosticStage.modelLoading => '模型读取',
    AgentDiagnosticStage.configurationRead => '配置读取',
    AgentDiagnosticStage.testRequest => '测试请求',
    AgentDiagnosticStage.processExit => '进程退出',
  };
}

String _relativeTime(DateTime? value) {
  if (value == null) {
    return '尚未更新';
  }
  final difference = DateTime.now().difference(value);
  if (difference.inMinutes < 1) {
    return '刚刚';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} 分钟前';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours} 小时前';
  }
  return '${difference.inDays} 天前';
}

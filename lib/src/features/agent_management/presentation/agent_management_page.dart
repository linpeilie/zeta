import 'dart:async';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_configuration_editor.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_log_view.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

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
    return PanelCard(
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
            _PageHeader(
              title: 'Agent 管理',
              subtitle: '管理本机已安装及当前应用支持的 Agent CLI',
              icon: Icons.smart_toy_outlined,
              trailing: sf.PrimaryButton(
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
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: IdeSpacing.all16,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (widget.controller.detecting &&
                        widget.controller.detectionProgress != null)
                      _DetectionProgressBanner(
                        progress: widget.controller.detectionProgress!,
                      ),
                    if (widget.controller.operationError
                        case final String error)
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
                    _buildSummary(context, allAgents),
                    const SizedBox(height: IdeSpacing.space16),
                    _buildListToolbar(context),
                    const SizedBox(height: IdeSpacing.space12),
                    if (visibleAgents.isEmpty)
                      _buildListEmptyState(context, allAgents)
                    else
                      ...visibleAgents.map(
                        (agent) => Padding(
                          padding: const EdgeInsets.only(
                            bottom: IdeSpacing.space8,
                          ),
                          child: _AgentListRow(
                            agent: agent,
                            onOpen: () => _openDetail(agent.definition.id),
                            onEnabledChanged: (enabled) =>
                                _setEnabled(agent.definition.id, enabled),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildSummary(BuildContext context, List<ManagedAgent> agents) {
    final installed = agents.where((agent) => agent.installed).length;
    final enabled = agents
        .where((agent) => agent.enabled && agent.installed)
        .length;
    final running = agents
        .where((agent) => agent.runtimeState == AgentRuntimeState.running)
        .length;
    final attention = agents.where((agent) => agent.needsAttention).length;
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 760
            ? (constraints.maxWidth - IdeSpacing.space24) / 4
            : constraints.maxWidth >= 420
            ? (constraints.maxWidth - IdeSpacing.space8) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: IdeSpacing.space8,
          runSpacing: IdeSpacing.space8,
          children: [
            _SummaryBlock(
              width: width,
              label: '已安装',
              value: installed,
              icon: Icons.download_done_rounded,
              onPressed: () {
                setState(() {
                  _listTab = _AgentListTab.installed;
                  _filter = _AgentListFilter.all;
                });
              },
            ),
            _SummaryBlock(
              width: width,
              label: '已启用',
              value: enabled,
              icon: Icons.toggle_on_outlined,
              onPressed: () {
                setState(() {
                  _listTab = _AgentListTab.supported;
                  _filter = _AgentListFilter.enabled;
                });
              },
            ),
            _SummaryBlock(
              width: width,
              label: '运行中',
              value: running,
              icon: Icons.play_circle_outline_rounded,
              onPressed: () {
                setState(() {
                  _filter = _AgentListFilter.running;
                });
              },
            ),
            _SummaryBlock(
              width: width,
              label: '需要处理',
              value: attention,
              icon: Icons.warning_amber_rounded,
              warning: attention > 0,
              onPressed: () {
                setState(() {
                  _filter = _AgentListFilter.attention;
                });
              },
            ),
          ],
        );
      },
    );
  }

  Widget _buildListToolbar(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final tabs = Wrap(
              spacing: IdeSpacing.space6,
              runSpacing: IdeSpacing.space6,
              children: [
                IdeChip(
                  key: const ValueKey('agent-tab-installed'),
                  label: '已安装',
                  selected: _listTab == _AgentListTab.installed,
                  trailingIcon: null,
                  onPressed: () {
                    setState(() {
                      _listTab = _AgentListTab.installed;
                    });
                  },
                ),
                IdeChip(
                  key: const ValueKey('agent-tab-supported'),
                  label: '全部支持',
                  selected: _listTab == _AgentListTab.supported,
                  trailingIcon: null,
                  onPressed: () {
                    setState(() {
                      _listTab = _AgentListTab.supported;
                    });
                  },
                ),
              ],
            );
            final search = sf.TextField(
              key: const ValueKey('agent-search-field'),
              controller: _searchController,
              placeholder: const Text('搜索 Agent 或厂商'),
              features: const <sf.InputFeature>[
                sf.InputFeature.leading(Icon(Icons.search_rounded, size: 18)),
              ],
            );
            if (constraints.maxWidth < 640) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  tabs,
                  const SizedBox(height: IdeSpacing.space8),
                  search,
                ],
              );
            }
            return Row(
              children: [
                tabs,
                const Spacer(),
                SizedBox(width: 280, child: search),
              ],
            );
          },
        ),
        const SizedBox(height: IdeSpacing.space8),
        Wrap(
          spacing: IdeSpacing.space6,
          runSpacing: IdeSpacing.space6,
          children: [
            _filterChip('全部状态', _AgentListFilter.all),
            _filterChip('已启用', _AgentListFilter.enabled),
            _filterChip('需要处理', _AgentListFilter.attention),
            _filterChip('运行中', _AgentListFilter.running),
            _filterChip('可更新', _AgentListFilter.updateAvailable),
          ],
        ),
      ],
    );
  }

  Widget _filterChip(String label, _AgentListFilter value) {
    return IdeChip(
      label: label,
      selected: _filter == value,
      trailingIcon: null,
      onPressed: () {
        setState(() {
          _filter = value;
        });
      },
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
        title: '暂未检测到已安装的 Agent CLI',
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
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final agent = widget.controller.agent;
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
                        key: const ValueKey('agent-detail-back-button'),
                        onPressed: _backToList,
                        size: sf.ButtonSize.small,
                        density: sf.ButtonDensity.iconDense,
                        icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      ),
                      const SizedBox(width: IdeSpacing.space8),
                      Expanded(
                        child: Text(
                          'Agent 管理 / ${agent.definition.displayName}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.caption.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: IdeSpacing.space8),
                  _buildDetailTitle(context, agent),
                  const SizedBox(height: IdeSpacing.space12),
                  Wrap(
                    spacing: IdeSpacing.space6,
                    runSpacing: IdeSpacing.space6,
                    children: [
                      _detailTabChip('基础信息', _AgentDetailTab.overview),
                      _detailTabChip('模型', _AgentDetailTab.models),
                      _detailTabChip('配置', _AgentDetailTab.configuration),
                    ],
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

  Widget _buildDetailTitle(BuildContext context, ManagedAgent agent) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final identity = Row(
          children: [
            _AgentLogo(installed: agent.installed),
            const SizedBox(width: IdeSpacing.space12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    agent.definition.displayName,
                    style: textStyles.titleLarge.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    '${agent.definition.vendor} · ${agent.definition.commandName} · '
                    '版本 ${agent.currentVersion ?? '未知'}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                  const SizedBox(height: IdeSpacing.space6),
                  Wrap(
                    spacing: IdeSpacing.space6,
                    runSpacing: IdeSpacing.space6,
                    children: [
                      StateLabel(
                        text: _accountLabel(agent.accountState),
                        color: _accountColor(colors, agent.accountState),
                      ),
                      StateLabel(
                        text: agent.installed ? 'CLI 可用' : 'CLI 未安装',
                        color: agent.installed
                            ? colors.success
                            : colors.warning,
                      ),
                      StateLabel(
                        text: _runtimeLabel(agent.runtimeState),
                        color: _runtimeColor(colors, agent.runtimeState),
                      ),
                      if (agent.updateAvailable)
                        StateLabel(text: '存在可用更新', color: colors.warning),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
        final actions = Wrap(
          spacing: IdeSpacing.space8,
          runSpacing: IdeSpacing.space8,
          children: [
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
              onPressed:
                  agent.installed &&
                      (agent.definition.id != cursorAgentProviderId ||
                          agent.enabled ||
                          agent.connectionTest?.success == true)
                  ? () => _setEnabled(agent.definition.id, !agent.enabled)
                  : null,
              size: sf.ButtonSize.small,
              child: Text(agent.enabled ? '禁用 Agent' : '启用 Agent'),
            ),
          ],
        );
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              identity,
              const SizedBox(height: IdeSpacing.space12),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: identity),
            const SizedBox(width: IdeSpacing.space16),
            actions,
          ],
        );
      },
    );
  }

  Widget _detailTabChip(String label, _AgentDetailTab value) {
    return IdeChip(
      label: label,
      selected: _detailTab == value,
      trailingIcon: null,
      onPressed: () => _selectDetailTab(value),
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
                _copyText(agent.definition.commandName, '已复制 CLI 命令。'),
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
            ? '当前账号尚未登录。登录 Codex CLI 后重新加载。'
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
          message: '无法使用所选 CLI 文件：$error',
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
          message: '无法打开 CLI 目录：$error',
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

class _PageHeader extends StatelessWidget {
  const _PageHeader({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.trailing,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final Widget trailing;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Container(
      padding: IdeSpacing.all12,
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: colors.borderSubtle)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: colors.accent),
          const SizedBox(width: IdeSpacing.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textStyles.displaySmall.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.caption.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: IdeSpacing.space12),
          trailing,
        ],
      ),
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
    return IdeStatusCard(
      tone: IdeStatusCardTone.info,
      title: progress.message,
      body: Row(
        children: [
          Expanded(
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

class _SummaryBlock extends StatelessWidget {
  const _SummaryBlock({
    required this.width,
    required this.label,
    required this.value,
    required this.icon,
    required this.onPressed,
    this.warning = false,
  });

  final double width;
  final String label;
  final int value;
  final IconData icon;
  final VoidCallback onPressed;
  final bool warning;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final accent = warning ? colors.warning : colors.accent;
    return PaneInteractiveSurface(
      width: width,
      onPressed: onPressed,
      padding: IdeSpacing.all12,
      borderColor: colors.borderSubtle,
      child: Row(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(width: IdeSpacing.space8),
          Expanded(
            child: Text(
              label,
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          Text(
            '$value',
            style: textStyles.titleLarge.copyWith(
              color: accent,
              fontWeight: FontWeight.w800,
            ),
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
  });

  final ManagedAgent agent;
  final VoidCallback onOpen;
  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PaneInteractiveSurface(
      key: ValueKey('agent-row-${agent.definition.id}'),
      onPressed: onOpen,
      padding: IdeSpacing.all12,
      borderColor: colors.border,
      semanticLabel: '查看 ${agent.definition.displayName} 详情',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final identity = Row(
            children: [
              _AgentLogo(installed: agent.installed),
              const SizedBox(width: IdeSpacing.space10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      agent.definition.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.displaySmall.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      agent.definition.commandName,
                      style: textStyles.codeSmall.copyWith(
                        color: colors.textTertiary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          );
          if (constraints.maxWidth < 760) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                identity,
                const SizedBox(height: IdeSpacing.space10),
                Wrap(
                  spacing: IdeSpacing.space8,
                  runSpacing: IdeSpacing.space8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    StateLabel(
                      text: agent.installed ? '已安装' : '未安装',
                      color: agent.installed ? colors.success : colors.warning,
                    ),
                    StateLabel(
                      text: _accountLabel(agent.accountState),
                      color: _accountColor(colors, agent.accountState),
                    ),
                    StateLabel(
                      text: _runtimeLabel(agent.runtimeState),
                      color: _runtimeColor(colors, agent.runtimeState),
                    ),
                    Text(
                      '版本 ${agent.currentVersion ?? '未知'}',
                      style: textStyles.bodySmall,
                    ),
                    sf.Switch(
                      value: agent.enabled,
                      enabled: agent.installed,
                      onChanged: agent.installed ? onEnabledChanged : null,
                      trailing: const Text('启用'),
                    ),
                  ],
                ),
              ],
            );
          }
          return Row(
            children: [
              Expanded(flex: 3, child: identity),
              Expanded(child: Text(agent.definition.vendor)),
              Expanded(
                child: StateLabel(
                  text: agent.installed
                      ? _accountLabel(agent.accountState)
                      : '—',
                  color: _accountColor(colors, agent.accountState),
                ),
              ),
              Expanded(
                child: sf.Switch(
                  value: agent.enabled,
                  enabled: agent.installed,
                  onChanged: agent.installed ? onEnabledChanged : null,
                ),
              ),
              Expanded(child: Text(agent.currentVersion ?? '未知')),
              Expanded(
                child: Text(
                  agent.latestVersion ?? '未知',
                  style: textStyles.bodySmall.copyWith(
                    color: agent.updateAvailable
                        ? colors.warning
                        : colors.textPrimary,
                  ),
                ),
              ),
              Expanded(
                child: StateLabel(
                  text: agent.installed
                      ? _runtimeLabel(agent.runtimeState)
                      : '未安装',
                  color: agent.installed
                      ? _runtimeColor(colors, agent.runtimeState)
                      : colors.textTertiary,
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: colors.textTertiary),
            ],
          );
        },
      ),
    );
  }
}

class _AgentLogo extends StatelessWidget {
  const _AgentLogo({required this.installed});

  final bool installed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: colors.primaryMuted,
        borderRadius: IdeRadius.allMedium,
        border: Border.all(color: colors.accent.withValues(alpha: 0.35)),
      ),
      alignment: Alignment.center,
      child: Icon(
        Icons.auto_awesome_rounded,
        size: 22,
        color: installed ? colors.accent : colors.textTertiary,
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
    return PanelCard(
      child: Padding(
        padding: IdeSpacing.all16,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              '基础信息',
              style: textStyles.displaySmall.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: IdeSpacing.space12),
            _InfoRow(label: '名称', value: agent.definition.displayName),
            _InfoRow(label: '厂商', value: agent.definition.vendor),
            _InfoRow(
              label: 'Agent CLI',
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
            const SizedBox(height: IdeSpacing.space12),
            Text('可执行文件路径', style: textStyles.titleSmall),
            const SizedBox(height: IdeSpacing.space6),
            SelectableText(
              agent.executablePath ?? '尚未检测到可执行文件',
              style: textStyles.codeSmall.copyWith(
                color: agent.executablePath == null
                    ? colors.error
                    : colors.textSecondary,
              ),
            ),
            const SizedBox(height: IdeSpacing.space8),
            Wrap(
              spacing: IdeSpacing.space8,
              runSpacing: IdeSpacing.space8,
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
                  child: const Text('打开所在目录'),
                ),
              ],
            ),
            const SizedBox(height: IdeSpacing.space16),
            Text('超时时间', style: textStyles.titleSmall),
            const SizedBox(height: IdeSpacing.space4),
            Text(
              'Agent 启动、握手或单次无响应等待的最大时长。',
              style: textStyles.caption.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: IdeSpacing.space8),
            Row(
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
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 112,
            child: Text(
              label,
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ),
          Expanded(
            child: Text(
              value,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodyMedium.copyWith(color: valueColor),
            ),
          ),
          ?trailing,
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
    return IdeStatusCard(
      tone: healthy ? IdeStatusCardTone.success : IdeStatusCardTone.error,
      title: healthy ? '连接正常' : (agent.errorMessage ?? '状态需要检查'),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _DiagnosticLine(
            label: 'CLI',
            value: agent.installed ? '可执行文件存在且可调用' : '未找到可执行文件',
          ),
          _DiagnosticLine(
            label: '账号',
            value: _accountLabel(agent.accountState),
          ),
          _DiagnosticLine(
            label: '通信',
            value: agent.connectionTest?.protocolReady == true
                ? '握手成功'
                : agent.runtimeState == AgentRuntimeState.idle
                ? '基础握手正常'
                : '尚未确认',
          ),
          _DiagnosticLine(
            label: '最近检测',
            value: _relativeTime(agent.lastDetectedAt),
          ),
          if (agent.connectionTest != null)
            _DiagnosticLine(
              label: '最近测试耗时',
              value: '${agent.connectionTest!.elapsed.inMilliseconds} ms',
            ),
          if (agent.errorStage != null)
            _DiagnosticLine(
              label: '异常阶段',
              value: _diagnosticStageLabel(agent.errorStage!),
            ),
          if (agent.errorDetails != null) ...[
            const SizedBox(height: IdeSpacing.space8),
            Text(
              agent.errorDetails!,
              maxLines: 8,
              overflow: TextOverflow.ellipsis,
              style: textStyles.codeSmall.copyWith(color: colors.textSecondary),
            ),
          ],
          if (agent.suggestion != null) ...[
            const SizedBox(height: IdeSpacing.space8),
            Text(
              '建议操作：${agent.suggestion}',
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
      footer: healthy
          ? null
          : Wrap(
              spacing: IdeSpacing.space8,
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
    );
  }
}

class _DiagnosticLine extends StatelessWidget {
  const _DiagnosticLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: textStyles.caption.copyWith(color: colors.textTertiary),
          ),
          Text(value, style: textStyles.bodySmall),
        ],
      ),
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
                        Text(
                          model.displayName,
                          style: textStyles.displaySmall.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
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
                  const IdeChip(label: '文本', trailingIcon: null),
                  if (supportsImage)
                    const IdeChip(label: '图片', trailingIcon: null),
                  const IdeChip(label: '代码', trailingIcon: null),
                  const IdeChip(label: '文件操作', trailingIcon: null),
                  const IdeChip(label: '工具调用', trailingIcon: null),
                  const IdeChip(label: '终端', trailingIcon: null),
                  const IdeChip(label: '流式输出', trailingIcon: null),
                ],
              ),
              const SizedBox(height: IdeSpacing.space8),
              Text(
                model.supportedReasoningEfforts.isEmpty
                    ? '思考能力：未知'
                    : '思考能力：可调节（${model.supportedReasoningEfforts.map((item) => _reasoningLabel(item.effort)).join('、')}）',
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

Color _accountColor(IdeColors colors, AgentAccountState state) {
  return switch (state) {
    AgentAccountState.loggedIn ||
    AgentAccountState.notRequired => colors.success,
    AgentAccountState.loggedOut || AgentAccountState.expired => colors.warning,
    AgentAccountState.checking => colors.info,
    _ => colors.textTertiary,
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

Color _runtimeColor(IdeColors colors, AgentRuntimeState state) {
  return switch (state) {
    AgentRuntimeState.idle => colors.success,
    AgentRuntimeState.running || AgentRuntimeState.starting => colors.info,
    AgentRuntimeState.stopping => colors.warning,
    AgentRuntimeState.error || AgentRuntimeState.unavailable => colors.error,
    AgentRuntimeState.disabled ||
    AgentRuntimeState.notRunning => colors.textTertiary,
  };
}

String _diagnosticStageLabel(AgentDiagnosticStage stage) {
  return switch (stage) {
    AgentDiagnosticStage.fileDetection => '文件检测',
    AgentDiagnosticStage.cliStartup => 'CLI 启动',
    AgentDiagnosticStage.versionDetection => '版本检测',
    AgentDiagnosticStage.accountAuthentication => '账号认证',
    AgentDiagnosticStage.protocolHandshake => '协议握手',
    AgentDiagnosticStage.modelLoading => '模型读取',
    AgentDiagnosticStage.configurationRead => '配置读取',
    AgentDiagnosticStage.testRequest => '测试请求',
    AgentDiagnosticStage.processExit => '进程退出',
  };
}

String _reasoningLabel(String value) {
  return switch (value) {
    'none' => '无',
    'minimal' => '极低',
    'low' => '低',
    'medium' => '中',
    'high' => '高',
    'xhigh' => '极高',
    _ => value,
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

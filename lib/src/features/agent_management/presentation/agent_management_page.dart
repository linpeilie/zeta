import 'dart:async';
import 'dart:io';

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
import 'package:zeta/src/features/agent_management/presentation/agent_management_l10n.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta/src/ui/localization/relative_time.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_switch.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_key_value_row.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/rows/ide_row_group.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';
import 'package:zeta/src/ui/core/workbench/ide_section.dart';
import 'package:zeta/src/ui/core/workbench/ide_toolbar.dart';

/// 列表筛选条中搜索框的固定宽度。
const double _searchFieldWidth = 280;

/// Agent 列表行右侧每个状态列的宽度。
///
/// 三列等宽是这一片能读成「表格」而不是「一堆标签」的唯一原因：宽度一旦按
/// 内容浮动，账号、版本、运行状态在相邻两行就会各自错开，眼睛得逐行重新
/// 定位。宁可让个别长文案省略，也不让列轴动。
const double _statusColumnWidth = 96;

/// Beta 标识槽与开关槽的宽度。
///
/// Beta 槽在非 Beta 行也会占位（渲染空盒）——否则一行有标签、一行没有，
/// 右侧整列就会整体平移。
const double _statusBadgeSlotWidth = 44;

/// Agent 列表行左侧图标的边长。
const double _agentLogoSize = 24;

/// 详情页「基础信息」标签下切换单栏 / 双栏的宽度阈值。
const double _overviewTwoColumnBreakpoint = 780;

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
  _ManagementView _view = _ManagementView.list;
  _AgentListTab _listTab = _AgentListTab.installed;
  _AgentDetailTab _detailTab = _AgentDetailTab.overview;

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController()..addListener(_refreshView);
    unawaited(widget.controller.initialize(autoDetect: widget.autoDetect));
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_refreshView)
      ..dispose();
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
                                title: context.l10n.mgmtOperationIncomplete,
                                body: Text(
                                  error,
                                  style: textStyles.bodySmall.copyWith(
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              const SizedBox(height: IdeSpacing.space12),
                            ],
                            _buildListToolbar(context),
                            // 去掉列表卡片后，这条线是整页唯一的贯通分隔：
                            // 它交代「上面是筛选、下面是数据」，不再需要一圈
                            // 描边把列表框起来。
                            const IdeRowDivider(),
                            Expanded(
                              child: visibleAgents.isEmpty
                                  ? _buildListEmptyState(context, allAgents)
                                  : ListView.builder(
                                      key: const ValueKey('agent-list'),
                                      itemCount: visibleAgents.length,
                                      itemBuilder: (context, index) {
                                        final agent = visibleAgents[index];
                                        return _AgentListRow(
                                          agent: agent,
                                          showDivider:
                                              index < visibleAgents.length - 1,
                                          onOpen: () =>
                                              _openDetail(agent.definition.id),
                                          onEnabledChanged: (enabled) =>
                                              _setEnabled(
                                                agent.definition.id,
                                                enabled,
                                              ),
                                        );
                                      },
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

  /// 列表筛选条：分段控件、搜索框与检测按钮排在同一条基线上。
  ///
  /// 这里刻意**不用** `IdeToolbar`——它画 `surfaceElevated` 底加上下边框，是一条
  /// 独立「条带」。列表卡片去掉之后，再留一条带背景的横幅就会变成整页仅存的
  /// 容器边界，反而更显眼。筛选条直接坐在 canvas 底色上，只靠下方那条
  /// `IdeRowDivider` 与数据区分界。
  Widget _buildListToolbar(BuildContext context) {
    final detecting = widget.controller.detecting;
    final tabs = IdeTabs<_AgentListTab>(
      value: _listTab,
      semanticLabel: 'Agent 列表范围',
      items: [
        IdeTabItem<_AgentListTab>(
          key: const ValueKey('agent-tab-installed'),
          value: _AgentListTab.installed,
          label: context.l10n.mgmtFilterInstalled,
        ),
        IdeTabItem<_AgentListTab>(
          key: const ValueKey('agent-tab-supported'),
          value: _AgentListTab.supported,
          label: context.l10n.mgmtFilterAllSupported,
        ),
      ],
      onChanged: (value) {
        setState(() {
          _listTab = value;
        });
      },
    );
    final searchField = sf.TextField(
      key: const ValueKey('agent-search-field'),
      controller: _searchController,
      placeholder: Text(context.l10n.mgmtSearchPlaceholder),
      features: const <sf.InputFeature>[
        sf.InputFeature.leading(Icon(Icons.search_rounded, size: 18)),
      ],
    );
    // 页面顶栏移除后，自动检测改由筛选条承载——列表非空时这里是唯一的检测
    // 入口（空列表另有 _ActionEmptyState 的引导按钮）。用主色描边而不是实心
    // 主色：一条筛选条上不该有唯一亮点，它会把注意力从搜索和分段控件上夺走。
    final detectButton = IdeButton(
      key: const ValueKey('agent-detect-button'),
      label: detecting
          ? context.l10n.mgmtDetecting
          : context.l10n.mgmtAutoDetect,
      variant: IdeButtonVariant.accentOutline,
      onPressed: detecting ? null : widget.controller.detect,
      leading: detecting
          ? const IdeLoadingIndicator(width: 18, height: 10)
          : null,
      leadingIcon: detecting ? null : Icons.radar_rounded,
    );

    return Padding(
      padding: const EdgeInsets.only(bottom: IdeSpacing.space8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 窄视口下三件套排不进一行，回落成换行流；宽视口保持同一条基线，
          // 搜索框定宽、检测按钮被 Spacer 推到右端。
          if (constraints.maxWidth < IdeMetrics.mediumBreakpoint) {
            final searchWidth = constraints.maxWidth < _searchFieldWidth
                ? constraints.maxWidth
                : _searchFieldWidth;
            return Wrap(
              spacing: IdeSpacing.space8,
              runSpacing: IdeSpacing.space8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                tabs,
                SizedBox(width: searchWidth, child: searchField),
                detectButton,
              ],
            );
          }
          return Row(
            children: [
              tabs,
              const SizedBox(width: IdeSpacing.space8),
              SizedBox(width: _searchFieldWidth, child: searchField),
              const Spacer(),
              detectButton,
            ],
          );
        },
      ),
    );
  }

  Widget _buildListEmptyState(BuildContext context, List<ManagedAgent> agents) {
    final installedTab = _listTab == _AgentListTab.installed;
    final noQuery = _searchController.text.trim().isEmpty;
    final anyInstalled = agents.any((agent) => agent.installed);
    if (installedTab && !anyInstalled && noQuery) {
      return _ActionEmptyState(
        icon: Icons.travel_explore_rounded,
        title: context.l10n.mgmtEmptyInstalledTitle,
        description: context.l10n.mgmtEmptyInstalledBody,
        primaryLabel: context.l10n.mgmtAutoDetect,
        onPrimary: widget.controller.detect,
        secondaryLabel: context.l10n.mgmtViewAllSupported,
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
      description: '请尝试修改搜索内容。',
      primaryLabel: '清除搜索',
      onPrimary: _searchController.clear,
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
                  '${context.l10n.mgmtVersionWithValue(agent.currentVersion ?? context.l10n.mgmtUnknown)}',
              leading: sf.IconButton.ghost(
                key: const ValueKey('agent-detail-back-button'),
                onPressed: _backToList,
                size: sf.ButtonSize.small,
                density: sf.ButtonDensity.iconDense,
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
              ),
              // 三个操作按同一尺寸、同一圆角、space4 间隔排成一组，读起来是
              // 「这一片是对当前 Agent 的操作」，而不是三颗散落的按钮。
              actions: [
                IdeButton(
                  key: const ValueKey('agent-test-connection-button'),
                  label: widget.controller.testing
                      ? context.l10n.mgmtTesting
                      : context.l10n.mgmtTestConnection,
                  onPressed: agent.installed && !widget.controller.testing
                      ? _testConnection
                      : null,
                ),
                IdeButton(
                  key: const ValueKey('agent-open-logs-button'),
                  label: context.l10n.mgmtViewLogs,
                  onPressed: agent.logPaths.isEmpty ? null : _openLogs,
                ),
                IdeButton(
                  label: agent.enabled
                      ? context.l10n.mgmtDisableAgent
                      : context.l10n.mgmtEnableAgent,
                  // 只有「禁用」是危险态。启用是恢复动作，套红会让这个来回
                  // 切换的开关长期处于报警状态。
                  variant: agent.enabled
                      ? IdeButtonVariant.dangerOutline
                      : IdeButtonVariant.outline,
                  onPressed: agent.installed
                      ? () => _setEnabled(agent.definition.id, !agent.enabled)
                      : null,
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
                    items: [
                      IdeTabItem<_AgentDetailTab>(
                        key: const ValueKey('agent-detail-tab-overview'),
                        value: _AgentDetailTab.overview,
                        label: context.l10n.mgmtTabBasics,
                      ),
                      IdeTabItem<_AgentDetailTab>(
                        key: const ValueKey('agent-detail-tab-models'),
                        value: _AgentDetailTab.models,
                        label: context.l10n.mgmtTabModels,
                      ),
                      IdeTabItem<_AgentDetailTab>(
                        key: const ValueKey('agent-detail-tab-configuration'),
                        value: _AgentDetailTab.configuration,
                        label: context.l10n.mgmtTabConfig,
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
            onDetect: widget.controller.detect,
            onOpenExecutableDirectory: _openExecutableDirectory,
            onCopyCommand: () => _copyText(
              agent.definition.commandName,
              context.l10n.mgmtCopiedCommand,
            ),
          );
          final diagnostics = _AgentDiagnosticsCard(
            agent: agent,
            onDetect: widget.controller.detect,
          );
          final setupGuide = agent.definition.id == defaultClaudeCodeProviderId
              ? const _ClaudeCodeSetupGuideCard()
              : null;
          final accountDataEnrichment =
              agent.definition.id == defaultClaudeCodeProviderId
              ? _ClaudeCodeAccountDataEnrichmentCard(
                  enabled:
                      widget.controller.claudeCodeAccountDataEnrichmentEnabled,
                  updating: widget.controller.updatingAccountDataEnrichment,
                  onChanged: (value) {
                    unawaited(
                      widget.controller
                          .setClaudeCodeAccountDataEnrichmentEnabled(value),
                    );
                  },
                )
              : null;
          if (constraints.maxWidth < _overviewTwoColumnBreakpoint) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                information,
                if (accountDataEnrichment != null) ...[
                  const SizedBox(height: IdeSpacing.space24),
                  const IdeRowDivider(),
                  const SizedBox(height: IdeSpacing.space16),
                  accountDataEnrichment,
                ],
                if (setupGuide != null) ...[
                  const SizedBox(height: IdeSpacing.space24),
                  const IdeRowDivider(),
                  const SizedBox(height: IdeSpacing.space16),
                  setupGuide,
                ],
                const SizedBox(height: IdeSpacing.space24),
                const IdeRowDivider(),
                const SizedBox(height: IdeSpacing.space16),
                diagnostics,
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 两栏之间只留白，不画竖线：`IdeColumnDivider` 需要有界高度，而
              // 撑起它的 `IntrinsicHeight` 无法穿过 `IdeSection` / `IdeSettingsRow`
              // 内部的 `LayoutBuilder`。这也正是 `IdeSpacing.space32` 的本职
              // ——无卡片布局下，那段留白就是分组边界。
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: information),
                  const SizedBox(width: IdeSpacing.space32),
                  Expanded(flex: 2, child: diagnostics),
                ],
              ),
              if (accountDataEnrichment != null) ...[
                const SizedBox(height: IdeSpacing.space24),
                const IdeRowDivider(),
                const SizedBox(height: IdeSpacing.space16),
                accountDataEnrichment,
              ],
              if (setupGuide != null) ...[
                const SizedBox(height: IdeSpacing.space24),
                const IdeRowDivider(),
                const SizedBox(height: IdeSpacing.space16),
                setupGuide,
              ],
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
        title: context.l10n.mgmtCannotLoadModels,
        description: agent.accountState == AgentAccountState.loggedOut
            ? context.l10n.mgmtModelsNeedLogin
            : 'Codex app-server 未返回模型，或当前配置无法完成握手。',
        primaryLabel: context.l10n.mgmtReload,
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
            '更新时间：${_relativeTime(agent.modelsUpdatedAt, notUpdated: context.l10n.mgmtNotUpdated, l10n: context.l10n)}',
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
    if (query.isEmpty) {
      return true;
    }
    return agent.definition.displayName.toLowerCase().contains(query) ||
        agent.definition.vendor.toLowerCase().contains(query) ||
        agent.definition.commandName.toLowerCase().contains(query);
  }

  void _openDetail(String agentId) {
    widget.controller.selectAgent(agentId);
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
          content: Text(context.l10n.mgmtDisableWarning),
          actions: <IdeDialogAction>[
            IdeDialogAction.cancel(
              label: context.l10n.commonCancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IdeDialogAction.destructive(
              label: context.l10n.mgmtStopAndDisable,
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
    if (widget.controller.selectedAgentId == defaultClaudeCodeProviderId) {
      final confirmed = await showIdeDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (context) => IdeDialog(
          title: Text(context.l10n.mgmtTestClaudeTitle),
          content: Text(context.l10n.mgmtTestClaudeBody),
          actions: <IdeDialogAction>[
            IdeDialogAction.cancel(
              label: context.l10n.commonCancel,
              onPressed: () => Navigator.of(context).pop(false),
            ),
            IdeDialogAction.confirm(
              label: context.l10n.mgmtContinueTest,
              onPressed: () => Navigator.of(context).pop(true),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) {
        return;
      }
    }
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
        _AgentLogo(
          providerId: agent.definition.id,
          kind: _kindForAgentId(agent.definition.id),
          installed: agent.installed,
        ),
        const SizedBox(width: IdeSpacing.space8),
        _AgentStatusText(
          status: _priorityAgentStatus(colors, agent, context.l10n),
        ),
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
            kind: _kindForAgentId(agent.definition.id),
            installed: agent.installed,
          ),
          trailing: _AgentRowStatus(
            agent: agent,
            compact: compact,
            onEnabledChanged: onEnabledChanged,
          ),
          showDivider: showDivider,
          // 线的起点推到标题左边缘：行内边距 + logo 宽 + logo 与文字的间隙。
          // 用 token 相加而不是写死，改 logo 尺寸时对齐会自己跟上。
          dividerIndent:
              IdeSpacing.space10 + _agentLogoSize + IdeSpacing.space8,
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
    // 两个断点都不画 `>` 箭头：整行可点击已由 `PaneInteractiveSurface` 的
    // hover 高亮表达，重复一个指向性图标只会让右端多一列噪音。
    if (compact) {
      final status = _priorityAgentStatus(colors, agent, context.l10n);
      return _AgentStatusText(
        key: const ValueKey('agent-row-status-compact'),
        status: status,
      );
    }

    final accountNeedsAttention = switch (agent.accountState) {
      AgentAccountState.loggedOut ||
      AgentAccountState.expired => !_hasSuccessfulConnectionTest(agent),
      _ => false,
    };
    final runtimeNeedsAttention = switch (agent.runtimeState) {
      AgentRuntimeState.error || AgentRuntimeState.unavailable => true,
      _ => false,
    };
    // 固定宽度栅格：Beta 槽 → 账号 → 版本 → 运行状态 → 开关。每一格宽度都与
    // 内容无关，纵向才会真的对齐成列。
    return Row(
      key: const ValueKey('agent-row-status-wide'),
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: _statusBadgeSlotWidth,
          child: agent.definition.isBeta
              ? Align(
                  alignment: Alignment.centerRight,
                  child: StateLabel(text: 'Beta', color: colors.warning),
                )
              : null,
        ),
        const SizedBox(width: IdeSpacing.space8),
        SizedBox(
          width: _statusColumnWidth,
          child: _AgentStatusText(
            status: _AgentStatus(
              label: agent.installed
                  ? _accountEvidenceLabel(agent, context.l10n)
                  : '—',
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
          width: _statusColumnWidth,
          child: _AgentStatusText(
            // 版本号是机器数据：等宽 + tabularFigures 之后，0.144.1 与
            // 0.99.10 才会按小数点逐位对齐，扫视一列版本才有意义。
            mono: true,
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
          width: _statusColumnWidth,
          child: _AgentStatusText(
            status: _AgentStatus(
              label: agent.installed
                  ? agent.runtimeState.localizedLabel(context.l10n)
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
        SizedBox(
          width: _statusBadgeSlotWidth,
          child: Align(
            alignment: Alignment.centerRight,
            child: IdeSwitch(
              value: agent.enabled,
              enabled: agent.installed,
              onChanged: agent.installed ? onEnabledChanged : null,
            ),
          ),
        ),
      ],
    );
  }
}

class _AgentStatusText extends StatelessWidget {
  const _AgentStatusText({required this.status, super.key, this.mono = false});

  final _AgentStatus status;

  /// 标签是否为机器数据（版本号等），为真时改用等宽 `numeric`。
  final bool mono;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final style = mono ? textStyles.numeric : textStyles.meta;
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
            style: style.copyWith(color: status.color),
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

_AgentStatus _priorityAgentStatus(
  IdeColors colors,
  ManagedAgent agent,
  AppLocalizations l10n,
) {
  if (agent.runtimeState == AgentRuntimeState.error ||
      agent.runtimeState == AgentRuntimeState.unavailable) {
    return _AgentStatus(
      label: agent.runtimeState.localizedLabel(l10n),
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
    if (_hasSuccessfulConnectionTest(agent)) {
      return _AgentStatus(
        label: l10n.mgmtConnectionAvailable,
        icon: Icons.check_circle_outline_rounded,
        color: colors.textSecondary,
      );
    }
    return _AgentStatus(
      label: _accountEvidenceLabel(agent, l10n),
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
          : agent.runtimeState.localizedLabel(l10n),
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
  const _AgentLogo({
    required this.providerId,
    required this.installed,
    this.kind,
  });

  final String providerId;
  final AgentProviderKind? kind;
  final bool installed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return Container(
      width: _agentLogoSize,
      height: _agentLogoSize,
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: IdeRadius.allSmall,
        border: Border.all(color: colors.borderSubtle),
      ),
      alignment: Alignment.center,
      child: AgentProviderIcon(
        providerId: providerId,
        kind: kind,
        size: 14,
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
                  // 空状态里主色实心是对的：整屏没有别的内容可被它压过，
                  // 这一颗按钮就是用户此刻唯一该做的事。
                  IdeButton(
                    label: primaryLabel,
                    variant: IdeButtonVariant.primary,
                    onPressed: onPrimary,
                  ),
                  if (secondaryLabel case final String label)
                    IdeButton(label: label, onPressed: onSecondary),
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
    required this.onDetect,
    required this.onOpenExecutableDirectory,
    required this.onCopyCommand,
  });

  final ManagedAgent agent;
  final VoidCallback onDetect;
  final VoidCallback onOpenExecutableDirectory;
  final VoidCallback onCopyCommand;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeSection(
      title: context.l10n.mgmtSectionBasics,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdeRowGroup(
            title: context.l10n.mgmtBasicAttributes,
            dividers: false,
            children: [
              // 显示名与协议名都是「可复制的机器串」，走等宽；厂商是人类
              // 文案，留在 UI 字体里。
              IdeKeyValueRow(
                label: context.l10n.mgmtName,
                value: agent.definition.displayName,
                tone: IdeKeyValueTone.identifier,
              ),
              IdeKeyValueRow(
                label: context.l10n.mgmtVendor,
                value: agent.definition.vendor,
              ),
              IdeKeyValueRow(
                label: '通信协议',
                value: agent.definition.protocol,
                tone: IdeKeyValueTone.identifier,
              ),
              IdeKeyValueRow(
                label: '传输方式',
                value: agent.definition.transport,
                tone: IdeKeyValueTone.identifier,
              ),
            ],
          ),
          const SizedBox(height: IdeSpacing.space12),
          const IdeRowDivider(),
          IdeRowGroup(
            title: '版本',
            dividers: false,
            children: [
              IdeKeyValueRow(
                label: '当前版本',
                value: agent.currentVersion ?? '未知',
                tone: IdeKeyValueTone.numeric,
              ),
              IdeKeyValueRow(
                label: '最新版本',
                value: agent.latestVersion ?? '未知',
                tone: IdeKeyValueTone.numeric,
                valueColor: agent.updateAvailable ? colors.warning : null,
              ),
            ],
          ),
          const SizedBox(height: IdeSpacing.space12),
          const IdeRowDivider(),
          IdeRowGroup(
            title: '路径与命令',
            dividers: false,
            children: [
              IdeKeyValueRow(
                label: '启动命令',
                value: agent.definition.commandName,
                tone: IdeKeyValueTone.identifier,
                trailing: sf.IconButton.ghost(
                  onPressed: onCopyCommand,
                  size: sf.ButtonSize.xSmall,
                  density: sf.ButtonDensity.iconDense,
                  icon: const Icon(Icons.copy_rounded, size: 14),
                ),
              ),
              IdeKeyValueRow(
                label: '可执行文件路径',
                value: agent.executablePath ?? '未检测到',
                tone: IdeKeyValueTone.code,
                selectable: agent.executablePath != null,
              ),
              if (agent.executablePath == null)
                Padding(
                  padding: const EdgeInsets.only(
                    left: IdeMetrics.keyValueLabelWidth + IdeSpacing.space8,
                    bottom: IdeSpacing.space6,
                  ),
                  child: Text(
                    '尚未检测到可执行文件，请先安装并确保已加入 PATH',
                    style: textStyles.meta.copyWith(height: 1.25),
                  ),
                ),
              // 去掉卡片后右对齐失去了参照边：按钮跟着值列左对齐，和上面
              // 几行共用同一条竖轴。
              Padding(
                padding: const EdgeInsets.only(
                  left: IdeMetrics.keyValueLabelWidth + IdeSpacing.space8,
                  top: IdeSpacing.space4,
                ),
                child: Wrap(
                  spacing: IdeSpacing.space6,
                  runSpacing: IdeSpacing.space6,
                  children: [
                    IdeButton(label: '自动检测', onPressed: onDetect),
                    IdeButton(
                      label: '打开目录',
                      onPressed: agent.executablePath == null
                          ? null
                          : onOpenExecutableDirectory,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AgentDiagnosticsCard extends StatelessWidget {
  const _AgentDiagnosticsCard({required this.agent, required this.onDetect});

  final ManagedAgent agent;
  final VoidCallback onDetect;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final connectionReady = _hasSuccessfulConnectionTest(agent);
    final accountOrConnectionReady = switch (agent.accountState) {
      AgentAccountState.loggedIn || AgentAccountState.notRequired => true,
      _ => connectionReady,
    };
    final healthy =
        agent.installed &&
        agent.errorMessage == null &&
        accountOrConnectionReady;
    final diagnostics = <_DiagnosticEntry>[
      _DiagnosticEntry(
        label: '程序',
        value: agent.installed ? '可执行文件存在且可调用' : '未找到可执行文件',
      ),
      _DiagnosticEntry(
        label: context.l10n.mgmtAuthEvidence,
        value: _accountEvidenceLabel(agent, context.l10n),
      ),
      _DiagnosticEntry(
        label: '通信',
        value: connectionReady
            ? agent.connectionTest?.message ?? '连接探测成功'
            : agent.runtimeState == AgentRuntimeState.idle
            ? '基础握手正常'
            : '尚未确认',
      ),
      _DiagnosticEntry(
        label: '最近检测',
        value: _relativeTime(
          agent.lastDetectedAt,
          notUpdated: context.l10n.mgmtNotUpdated,
          l10n: context.l10n,
        ),
      ),
      if (agent.connectionTest != null)
        _DiagnosticEntry(
          label: '最近测试耗时',
          value: '${agent.connectionTest!.elapsed.inMilliseconds} ms',
          tone: IdeKeyValueTone.numeric,
        ),
      if (agent.connectionTest?.protocolVersion case final String version)
        _DiagnosticEntry(
          label: '协议',
          value: version,
          tone: IdeKeyValueTone.identifier,
        ),
      if (agent.connectionTest?.agentName case final String agentName)
        _DiagnosticEntry(
          label: '握手身份',
          value:
              '$agentName'
              '${agent.connectionTest!.agentVersion == null ? '' : ' ${agent.connectionTest!.agentVersion}'}',
          tone: IdeKeyValueTone.identifier,
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
          value: errorStage.localizedLabel(context.l10n),
        ),
    ];
    final hasSupplement =
        agent.errorDetails != null || agent.suggestion != null || !healthy;
    return IdeSection(
      title: context.l10n.mgmtDiagnostics,
      subtitle: healthy
          ? context.l10n.mgmtConnectionHealthy
          : (agent.errorMessage ?? '状态需要检查'),
      trailing: Icon(
        healthy ? Icons.check_circle_outline_rounded : Icons.error_outline,
        size: 17,
        color: healthy ? colors.textSecondary : colors.error,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in diagnostics)
            IdeKeyValueRow(
              label: entry.label,
              value: entry.value,
              tone: entry.tone,
            ),
          // 补充信息（错误正文、建议、修复入口）与上面的事实清单之间只隔
          // 一条线，不再各自套一个带边框的盒子。
          if (hasSupplement) ...[
            const SizedBox(height: IdeSpacing.space8),
            const IdeRowDivider(),
            const SizedBox(height: IdeSpacing.space12),
          ],
          if (agent.errorDetails case final String errorDetails) ...[
            SelectableText(
              errorDetails,
              maxLines: 8,
              style: textStyles.codeSmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: IdeSpacing.space8),
          ],
          if (agent.suggestion case final String suggestion) ...[
            Text(
              '建议操作：$suggestion',
              style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: IdeSpacing.space8),
          ],
          if (!healthy)
            Align(
              alignment: Alignment.centerLeft,
              child: IdeButton(label: '自动检测', onPressed: onDetect),
            ),
        ],
      ),
    );
  }
}

class _DiagnosticEntry {
  const _DiagnosticEntry({
    required this.label,
    required this.value,
    this.tone = IdeKeyValueTone.text,
  });

  final String label;
  final String value;

  /// 值的排版语义；协议号、耗时这类机器数据走等宽档。
  final IdeKeyValueTone tone;
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
                        Text(model.displayName, style: textStyles.identifier),
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
                    text: model.hidden
                        ? context.l10n.mgmtHidden
                        : context.l10n.mgmtAvailable,
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
                  IdeChip(label: context.l10n.mgmtCapText),
                  if (supportsImage) IdeChip(label: context.l10n.mgmtCapImage),
                  IdeChip(label: context.l10n.mgmtCapCode),
                  IdeChip(label: context.l10n.mgmtCapFileOps),
                  IdeChip(label: context.l10n.mgmtCapToolCall),
                  IdeChip(label: context.l10n.mgmtCapTerminal),
                  IdeChip(label: context.l10n.mgmtCapStreaming),
                ],
              ),
              const SizedBox(height: IdeSpacing.space8),
              Text(
                model.supportedReasoningEfforts.isEmpty
                    ? context.l10n.mgmtReasoningUnknown
                    : context.l10n.mgmtReasoningAdjustable(
                        orderedReasoningEffortsForDisplay(
                          model.supportedReasoningEfforts,
                        ).map((item) => item.effort).join('、'),
                      ),
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

class _ClaudeCodeAccountDataEnrichmentCard extends StatelessWidget {
  const _ClaudeCodeAccountDataEnrichmentCard({
    required this.enabled,
    required this.updating,
    required this.onChanged,
  });

  final bool enabled;
  final bool updating;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return IdeSection(
      title: context.l10n.mgmtQuotaEnrichmentTitle,
      subtitle: context.l10n.mgmtQuotaEnrichmentSubtitle,
      child: IdeSettingsRow(
        key: const ValueKey('claude-account-data-enrichment-row'),
        label: context.l10n.mgmtQuotaEnrichmentLabel,
        description: context.l10n.mgmtQuotaEnrichmentBody,
        showDivider: false,
        padding: IdeSpacing.settingsRowPaddingFlat,
        control: IdeSwitch(
          key: const ValueKey('claude-account-data-enrichment-switch'),
          value: enabled,
          enabled: !updating,
          onChanged: updating ? null : onChanged,
        ),
      ),
    );
  }
}

/// Claude Code 详情页安装 / 登录 / 文档三段指引（M0）。
class _ClaudeCodeSetupGuideCard extends StatelessWidget {
  const _ClaudeCodeSetupGuideCard();

  static const String _docsUrl =
      'https://docs.anthropic.com/en/docs/claude-code';

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return IdeSection(
      title: context.l10n.mgmtSetupGuideTitle,
      subtitle: context.l10n.mgmtSetupGuideSubtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _SetupGuideStep(
            title: context.l10n.mgmtSetupInstallTitle,
            body: context.l10n.mgmtSetupInstallBody,
            textStyles: textStyles,
            colors: colors,
            showDivider: true,
          ),
          _SetupGuideStep(
            title: context.l10n.mgmtSetupLoginTitle,
            body: context.l10n.mgmtSetupLoginBody,
            textStyles: textStyles,
            colors: colors,
            showDivider: true,
          ),
          _SetupGuideStep(
            title: context.l10n.mgmtSetupDocsTitle,
            body: context.l10n.mgmtSetupDocsBody(_docsUrl),
            textStyles: textStyles,
            colors: colors,
            showDivider: false,
          ),
        ],
      ),
    );
  }
}

class _SetupGuideStep extends StatelessWidget {
  const _SetupGuideStep({
    required this.title,
    required this.body,
    required this.textStyles,
    required this.colors,
    required this.showDivider,
  });

  final String title;
  final String body;
  final IdeTextStyles textStyles;
  final IdeColors colors;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: IdeSpacing.space8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: textStyles.identifier),
              const SizedBox(height: IdeSpacing.space6),
              Text(
                body,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        // 全页共用一套分隔线机制，不再各自手写 BorderSide。
        if (showDivider) const IdeRowDivider(),
      ],
    );
  }
}

AgentProviderKind? _kindForAgentId(String agentId) {
  return switch (agentId) {
    defaultAgentProviderId => AgentProviderKind.codexAppServer,
    grokAgentProviderId => AgentProviderKind.acp,
    defaultClaudeCodeProviderId => AgentProviderKind.claudeCode,
    cursorAgentProviderId => AgentProviderKind.cursorAcp,
    _ => null,
  };
}

String _accountEvidenceLabel(ManagedAgent agent, AppLocalizations l10n) {
  final label = agent.accountLabel?.trim();
  return label == null || label.isEmpty
      ? agent.accountState.localizedLabel(l10n)
      : label;
}

bool _hasSuccessfulConnectionTest(ManagedAgent agent) {
  return agent.connectionTest?.protocolReady == true;
}

String _relativeTime(
  DateTime? value, {
  required String notUpdated,
  required AppLocalizations l10n,
}) {
  if (value == null) {
    return notUpdated;
  }
  return formatLocalizedRelativeTime(value, DateTime.now(), l10n);
}

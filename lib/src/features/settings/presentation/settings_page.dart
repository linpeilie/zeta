import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_body.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_header.dart';

enum SettingsSection { general, appearance, agents }

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.activeSection,
    required this.appearanceController,
    required this.generalSettingsController,
    required this.onBackPressed,
    required this.onSectionSelected,
    this.agentManagementController,
    super.key,
  });

  final SettingsSection activeSection;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final AgentManagementController? agentManagementController;
  final VoidCallback onBackPressed;
  final ValueChanged<SettingsSection> onSectionSelected;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  final GlobalKey<SettingsPageCanvasState> _canvasKey =
      GlobalKey<SettingsPageCanvasState>();

  static const double _navigationWidth = IdeMetrics.navigationPaneWidth;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: _navigationWidth,
          child: SettingsNavigationPane(
            activeSection: widget.activeSection,
            showAgentManagement: widget.agentManagementController != null,
            onBackPressed: () {
              unawaited(_handleBackPressed());
            },
            onSectionSelected: (section) {
              unawaited(_handleSectionSelected(section));
            },
          ),
        ),
        const SizedBox(width: IdeSpacing.space8),
        Expanded(
          child: SettingsPageCanvas(
            key: _canvasKey,
            activeSection: widget.activeSection,
            appearanceController: widget.appearanceController,
            generalSettingsController: widget.generalSettingsController,
            agentManagementController: widget.agentManagementController,
          ),
        ),
      ],
    );
  }

  Future<void> _handleBackPressed() async {
    if (!(await _canvasKey.currentState?.confirmCanLeave() ?? true)) {
      return;
    }
    widget.onBackPressed();
  }

  Future<void> _handleSectionSelected(SettingsSection section) async {
    if (section == widget.activeSection) {
      return;
    }
    if (!(await _canvasKey.currentState?.confirmCanLeave() ?? true)) {
      return;
    }
    widget.onSectionSelected(section);
  }
}

/// 设置页放入 Workbench Navigation slot 的导航内容。
///
/// 分区切换与离开确认仍由设置 Feature 的 Canvas 状态协调；该组件只负责展示
/// 设置导航和转发用户意图。
class SettingsNavigationPane extends StatelessWidget {
  const SettingsNavigationPane({
    required this.activeSection,
    required this.onBackPressed,
    required this.onSectionSelected,
    required this.showAgentManagement,
    super.key,
  });

  final SettingsSection activeSection;
  final VoidCallback onBackPressed;
  final ValueChanged<SettingsSection> onSectionSelected;
  final bool showAgentManagement;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeSurface.pane(
      key: const ValueKey('settings-nav-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdePageHeader(
            title: '设置',
            leading: IdeTooltip(
              message: '返回主界面',
              child: sf.IconButton.ghost(
                key: const ValueKey('settings-back-button'),
                onPressed: onBackPressed,
                size: sf.ButtonSize.small,
                density: sf.ButtonDensity.iconDense,
                icon: Icon(
                  Icons.arrow_back_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: IdeSpacing.all8,
              children: [
                IdeListRow(
                  key: const ValueKey('settings-nav-general'),
                  title: '常规',
                  leading: const Icon(Icons.tune_rounded),
                  selected: activeSection == SettingsSection.general,
                  onPressed: () => onSectionSelected(SettingsSection.general),
                  showDivider: false,
                ),
                IdeListRow(
                  key: const ValueKey('settings-nav-appearance'),
                  title: '外观',
                  leading: const Icon(Icons.palette_outlined),
                  selected: activeSection == SettingsSection.appearance,
                  onPressed: () =>
                      onSectionSelected(SettingsSection.appearance),
                  showDivider: false,
                ),
                if (showAgentManagement)
                  IdeListRow(
                    key: const ValueKey('settings-nav-agents'),
                    title: 'Agent 管理',
                    leading: const Icon(Icons.smart_toy_outlined),
                    selected: activeSection == SettingsSection.agents,
                    onPressed: () => onSectionSelected(SettingsSection.agents),
                    showDivider: false,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 设置页放入 Workbench Canvas slot 的业务内容。
class SettingsPageCanvas extends StatefulWidget {
  const SettingsPageCanvas({
    required this.activeSection,
    required this.appearanceController,
    required this.generalSettingsController,
    required this.agentManagementController,
    super.key,
  });

  final SettingsSection activeSection;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final AgentManagementController? agentManagementController;

  @override
  State<SettingsPageCanvas> createState() => SettingsPageCanvasState();
}

/// 设置 Canvas 的可离开状态，由设置 Feature 持有并供页面路由入口查询。
class SettingsPageCanvasState extends State<SettingsPageCanvas> {
  final GlobalKey<AgentManagementPageState> _agentManagementKey =
      GlobalKey<AgentManagementPageState>();

  /// 当前设置内容是否允许离开；Agent 配置编辑器可能需要先确认未保存内容。
  Future<bool> confirmCanLeave() async {
    if (widget.activeSection != SettingsSection.agents) {
      return true;
    }
    return await _agentManagementKey.currentState?.confirmCanLeave() ?? true;
  }

  @override
  Widget build(BuildContext context) {
    return switch (widget.activeSection) {
      SettingsSection.general => _GeneralSettingsPane(
        generalSettingsController: widget.generalSettingsController,
      ),
      SettingsSection.appearance => _AppearanceSettingsPane(
        appearanceController: widget.appearanceController,
      ),
      SettingsSection.agents =>
        widget.agentManagementController == null
            ? const IdeSurface.canvas(child: EmptyState(text: 'Agent 管理服务不可用。'))
            : AgentManagementPage(
                key: _agentManagementKey,
                controller: widget.agentManagementController!,
              ),
    };
  }
}

class _GeneralSettingsPane extends StatelessWidget {
  const _GeneralSettingsPane({required this.generalSettingsController});

  final GeneralSettingsController generalSettingsController;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final modifierLabel = isMacOS ? 'Cmd + Enter 发送' : 'Ctrl + Enter 发送';
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdePageHeader(
            title: '常规',
            subtitle: '配置消息输入与发送行为',
            leading: Icon(
              Icons.tune_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<GeneralSettings>(
              valueListenable: generalSettingsController.listenable,
              builder: (context, settings, _) {
                final textStyles = IdeTextStyles.of(context);
                final colors = IdeColors.of(context);
                final description = switch (settings.sendMessageShortcut) {
                  MessageSendShortcut.enter =>
                    '按 Enter 发送消息，按 Shift + Enter 换行。',
                  MessageSendShortcut.primaryModifierEnter =>
                    isMacOS
                        ? '按 Cmd + Enter 发送消息，按 Enter 换行。'
                        : '按 Ctrl + Enter 发送消息，按 Enter 换行。',
                };
                return IdePageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '设置会立即应用，并保留到下次启动。',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space12),
                      IdeSurface.pane(
                        key: const ValueKey('settings-general-group'),
                        child: IdeSettingsRow(
                          key: const ValueKey(
                            'settings-send-message-shortcut-row',
                          ),
                          label: '发送快捷键',
                          description: description,
                          showDivider: false,
                          control: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 380),
                            child: IdeTabs<MessageSendShortcut>(
                              key: const ValueKey(
                                'settings-send-message-shortcut-tabs',
                              ),
                              value: settings.sendMessageShortcut,
                              semanticLabel: '发送快捷键',
                              items: <IdeTabItem<MessageSendShortcut>>[
                                const IdeTabItem<MessageSendShortcut>(
                                  key: ValueKey(
                                    'settings-send-message-shortcut-enter',
                                  ),
                                  value: MessageSendShortcut.enter,
                                  label: 'Enter 发送',
                                  leadingIcon: Icons.keyboard_return_rounded,
                                  semanticLabel: 'Enter 发送',
                                ),
                                IdeTabItem<MessageSendShortcut>(
                                  key: const ValueKey(
                                    'settings-send-message-shortcut-modifier',
                                  ),
                                  value:
                                      MessageSendShortcut.primaryModifierEnter,
                                  label: modifierLabel,
                                  leadingIcon:
                                      Icons.keyboard_command_key_rounded,
                                  semanticLabel: modifierLabel,
                                ),
                              ],
                              onChanged: (value) {
                                unawaited(
                                  generalSettingsController
                                      .setMessageSendShortcut(value),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _AppearanceSettingsPane extends StatelessWidget {
  const _AppearanceSettingsPane({required this.appearanceController});

  final AppearanceSettingsController appearanceController;

  static const List<_ThemeModeTabSpec> _tabs = <_ThemeModeTabSpec>[
    _ThemeModeTabSpec(
      keyName: 'system',
      title: '跟随系统',
      icon: Icons.brightness_auto_rounded,
      description: '使用系统当前的浅色或深色偏好。',
      value: ThemeMode.system,
    ),
    _ThemeModeTabSpec(
      keyName: 'light',
      title: '浅色',
      icon: Icons.light_mode_outlined,
      description: '使用浅底、低对比度边框和蔚蓝强调色。',
      value: ThemeMode.light,
    ),
    _ThemeModeTabSpec(
      keyName: 'dark',
      title: '深色',
      icon: Icons.dark_mode_outlined,
      description: '使用深底、高对比度面板和明亮强调色。',
      value: ThemeMode.dark,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IdePageHeader(
            title: '外观',
            subtitle: '切换主题模式、字体与字号',
            leading: Icon(
              Icons.palette_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
          Expanded(
            child: ValueListenableBuilder<AppearanceSettings>(
              valueListenable: appearanceController.listenable,
              builder: (context, settings, _) {
                final textStyles = IdeTextStyles.of(context);
                final colors = IdeColors.of(context);
                return IdePageBody(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '设置会立即应用，并保留到下次启动。',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space12),
                      IdeSurface.pane(
                        key: const ValueKey('settings-appearance-group'),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _ThemeModeSection(
                              tabs: _tabs,
                              groupValue: settings.themeMode,
                              onSelected: (value) {
                                unawaited(
                                  appearanceController.setThemeMode(value),
                                );
                              },
                            ),
                            const IdeRowDivider(),
                            _AppearanceSettingRow(
                              key: const ValueKey('settings-ui-font-row'),
                              label: '界面字体',
                              description: '用于普通界面文本与非代码 Markdown 正文。',
                              value: _fontChoiceLabel(
                                settings.uiFontChoice,
                                systemFontDisplayName: appearanceController
                                    .displayNameFor(settings.uiFontChoice),
                              ),
                              onTap: () => _selectUiFont(
                                context,
                                currentChoice: settings.uiFontChoice,
                              ),
                            ),
                            const IdeRowDivider(),
                            _FontSizeSettingRow(
                              key: const ValueKey('settings-ui-font-size-row'),
                              keyPrefix: 'settings-ui-font-size',
                              label: '界面字号',
                              description:
                                  '缩放普通界面文本（${minUiFontSize.toInt()}–${maxUiFontSize.toInt()} px）。',
                              value: settings.uiFontSize,
                              min: minUiFontSize,
                              max: maxUiFontSize,
                              onChanged: (value) {
                                unawaited(
                                  appearanceController.setUiFontSize(value),
                                );
                              },
                            ),
                            const IdeRowDivider(),
                            _AppearanceSettingRow(
                              key: const ValueKey('settings-code-font-row'),
                              label: '代码字体',
                              description: '用于代码块、命令、Diff 和工具输出。',
                              value: _fontChoiceLabel(
                                settings.codeFontChoice,
                                systemFontDisplayName: appearanceController
                                    .displayNameFor(settings.codeFontChoice),
                              ),
                              onTap: () => _selectCodeFont(
                                context,
                                currentChoice: settings.codeFontChoice,
                              ),
                            ),
                            const IdeRowDivider(),
                            _FontSizeSettingRow(
                              key: const ValueKey(
                                'settings-code-font-size-row',
                              ),
                              keyPrefix: 'settings-code-font-size',
                              label: '代码字号',
                              description:
                                  '缩放代码内容（${minCodeFontSize.toInt()}–${maxCodeFontSize.toInt()} px）。',
                              value: settings.codeFontSize,
                              min: minCodeFontSize,
                              max: maxCodeFontSize,
                              onChanged: (value) {
                                unawaited(
                                  appearanceController.setCodeFontSize(value),
                                );
                              },
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _selectUiFont(
    BuildContext context, {
    required AppearanceFontChoice currentChoice,
  }) async {
    final choice = await _showFontPicker(
      context: context,
      title: '界面字体',
      searchHint: '搜索界面字体',
      choicesFuture: appearanceController.loadUiFontChoices(),
      selectedChoice: currentChoice,
    );
    if (choice == null || !context.mounted) {
      return;
    }
    final updated = await appearanceController.setUiFontChoice(choice);
    if (!updated && context.mounted) {
      _showFontSelectionError(context, '无法加载所选界面字体。');
    }
  }

  Future<void> _selectCodeFont(
    BuildContext context, {
    required AppearanceFontChoice currentChoice,
  }) async {
    final choice = await _showFontPicker(
      context: context,
      title: '代码字体',
      searchHint: '搜索代码字体',
      choicesFuture: appearanceController.loadCodeFontChoices(),
      selectedChoice: currentChoice,
    );
    if (choice == null || !context.mounted) {
      return;
    }
    final updated = await appearanceController.setCodeFontChoice(choice);
    if (!updated && context.mounted) {
      _showFontSelectionError(context, '无法加载所选代码字体。');
    }
  }
}

class _ThemeModeTabSpec {
  const _ThemeModeTabSpec({
    required this.keyName,
    required this.title,
    required this.icon,
    required this.description,
    required this.value,
  });

  final String keyName;
  final String title;
  final IconData icon;
  final String description;
  final ThemeMode value;
}

/// 主题模式使用紧凑分段控件，并复用设置行的响应式堆叠规则。
class _ThemeModeSection extends StatelessWidget {
  const _ThemeModeSection({
    required this.tabs,
    required this.groupValue,
    required this.onSelected,
  });

  final List<_ThemeModeTabSpec> tabs;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final selectedTab = tabs.firstWhere(
      (tab) => tab.value == groupValue,
      orElse: () => tabs.first,
    );
    return IdeSettingsRow(
      label: '主题模式',
      description: selectedTab.description,
      showDivider: false,
      control: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: IdeTabs<ThemeMode>(
          key: const ValueKey('settings-theme-tabs'),
          value: groupValue,
          semanticLabel: '主题模式',
          items: [
            for (final tab in tabs)
              IdeTabItem<ThemeMode>(
                value: tab.value,
                label: tab.title,
                leadingIcon: tab.icon,
                semanticLabel: tab.title,
                key: ValueKey<String>('settings-theme-${tab.keyName}'),
              ),
          ],
          onChanged: onSelected,
        ),
      ),
    );
  }
}

class _AppearanceSettingRow extends StatelessWidget {
  const _AppearanceSettingRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onTap,
    super.key,
  });

  final String label;
  final String description;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PaneInteractiveSurface(
      onPressed: onTap,
      borderRadius: BorderRadius.zero,
      child: IdeSettingsRow(
        label: label,
        description: description,
        showDivider: false,
        control: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodyMedium.copyWith(
                  color: colors.accent,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(width: IdeSpacing.space8),
            Icon(
              Icons.expand_more_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

/// 字号步进设置行；宽度不足时把控制器换到下一行，避免说明文字被过度挤压。
class _FontSizeSettingRow extends StatelessWidget {
  const _FontSizeSettingRow({
    required this.keyPrefix,
    required this.label,
    required this.description,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    super.key,
  });

  final String keyPrefix;
  final String label;
  final String description;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final canDecrease = value > min;
    final canIncrease = value < max;
    final controls = Semantics(
      container: true,
      label: '$label，当前 ${value.toInt()} 像素',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeTooltip(
            message: '减小$label',
            child: Semantics(
              button: true,
              enabled: canDecrease,
              label: '减小$label',
              child: ExcludeSemantics(
                child: sf.IconButton.outline(
                  key: ValueKey<String>('$keyPrefix-decrease'),
                  onPressed: canDecrease ? () => onChanged(value - 1) : null,
                  size: sf.ButtonSize.small,
                  density: sf.ButtonDensity.iconDense,
                  icon: const Icon(Icons.remove_rounded, size: 16),
                ),
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          SizedBox(
            width: 48,
            child: Text(
              '${value.toInt()} px',
              key: ValueKey<String>('$keyPrefix-value'),
              textAlign: TextAlign.center,
              maxLines: 1,
              style: textStyles.bodyMedium.copyWith(
                color: colors.accent,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          IdeTooltip(
            message: '增大$label',
            child: Semantics(
              button: true,
              enabled: canIncrease,
              label: '增大$label',
              child: ExcludeSemantics(
                child: sf.IconButton.outline(
                  key: ValueKey<String>('$keyPrefix-increase'),
                  onPressed: canIncrease ? () => onChanged(value + 1) : null,
                  size: sf.ButtonSize.small,
                  density: sf.ButtonDensity.iconDense,
                  icon: const Icon(Icons.add_rounded, size: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );

    return IdeSettingsRow(
      label: label,
      description: description,
      showDivider: false,
      control: controls,
    );
  }
}

Future<AppearanceFontChoice?> _showFontPicker({
  required BuildContext context,
  required String title,
  required String searchHint,
  required Future<List<AppearanceFontOption>> choicesFuture,
  required AppearanceFontChoice selectedChoice,
}) {
  return showIdeDialog<AppearanceFontChoice>(
    context: context,
    builder: (context) {
      return _FontChoiceDialog(
        title: title,
        searchHint: searchHint,
        choicesFuture: choicesFuture,
        selectedChoice: selectedChoice,
      );
    },
  );
}

class _FontChoiceDialog extends StatefulWidget {
  const _FontChoiceDialog({
    required this.title,
    required this.searchHint,
    required this.choicesFuture,
    required this.selectedChoice,
  });

  final String title;
  final String searchHint;
  final Future<List<AppearanceFontOption>> choicesFuture;
  final AppearanceFontChoice selectedChoice;

  @override
  State<_FontChoiceDialog> createState() => _FontChoiceDialogState();
}

class _FontChoiceDialogState extends State<_FontChoiceDialog> {
  late final TextEditingController _searchController;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    // 字体选择不是纯确认弹窗：在 AlertDialog 壳内自建搜索 + 列表布局。
    // 关闭按钮放在 title 行，避免 AlertDialog.trailing 被强制套 iconXLarge。
    return IdeDialog(
      key: const ValueKey('settings-font-picker-dialog'),
      title: Row(
        children: [
          Expanded(child: Text(widget.title)),
          sf.IconButton.ghost(
            onPressed: () => Navigator.of(context).pop(),
            size: sf.ButtonSize.small,
            density: sf.ButtonDensity.iconDense,
            icon: Icon(
              Icons.close_rounded,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: 528,
        height: 420,
        child: DefaultTextStyle.merge(
          style: textStyles.bodyMedium.copyWith(color: colors.textPrimary),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              sf.TextField(
                key: const ValueKey('settings-font-search-field'),
                controller: _searchController,
                autofocus: true,
                onChanged: (value) {
                  setState(() {
                    _query = value;
                  });
                },
                placeholder: Text(widget.searchHint),
                features: const [
                  sf.InputFeature.leading(Icon(Icons.search_rounded, size: 18)),
                ],
              ),
              const SizedBox(height: IdeSpacing.space12),
              Expanded(
                child: FutureBuilder<List<AppearanceFontOption>>(
                  future: widget.choicesFuture,
                  builder: (context, snapshot) {
                    if (snapshot.connectionState != ConnectionState.done) {
                      return const Center(
                        child: IdeLoadingIndicator(
                          key: ValueKey('settings-font-picker-loading'),
                          width: 28,
                          height: 12,
                          barHeight: 4,
                        ),
                      );
                    }
                    if (snapshot.hasError) {
                      return Center(
                        child: Text(
                          '字体列表加载失败。',
                          style: textStyles.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      );
                    }

                    final choices =
                        snapshot.data ?? const <AppearanceFontOption>[];
                    final filtered = choices
                        .where((option) => option.matches(_query))
                        .toList(growable: false);
                    if (filtered.isEmpty) {
                      return Center(
                        child: Text(
                          '没有匹配的字体。',
                          style: textStyles.bodySmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      );
                    }

                    return ListView.builder(
                      key: const ValueKey('settings-font-picker-list'),
                      itemCount: filtered.length,
                      itemBuilder: (context, index) {
                        final option = filtered[index];
                        final choice = option.choice;
                        final selected = choice == widget.selectedChoice;
                        final optionStyle =
                            sf.ButtonStyle.ghost(
                              size: sf.ButtonSize.normal,
                              density: sf.ButtonDensity.dense,
                            ).withBackgroundColor(
                              color: selected
                                  ? colors.selectedSurface
                                  : Colors.transparent,
                              hoverColor: selected
                                  ? colors.selectedHoverSurface
                                  : colors.hoverSurface,
                            );
                        return SizedBox(
                          width: double.infinity,
                          height: 36,
                          child: sf.Button(
                            key: ValueKey<String>(
                              'settings-font-option-${choice.stableId}',
                            ),
                            onPressed: () => Navigator.of(context).pop(choice),
                            style: optionStyle,
                            alignment: Alignment.centerLeft,
                            trailing: selected
                                ? Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colors.accent,
                                  )
                                : null,
                            child: Text(
                              option.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyles.bodyMedium.copyWith(
                                color: colors.textPrimary,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _fontChoiceLabel(
  AppearanceFontChoice choice, {
  String? systemFontDisplayName,
}) {
  return switch (choice.kind) {
    AppearanceFontChoiceKind.systemDefault => '系统默认',
    AppearanceFontChoiceKind.bundledJetBrainsMono => 'JetBrainsMono（内置默认）',
    AppearanceFontChoiceKind.system =>
      systemFontDisplayName ?? choice.fontFamily!,
  };
}

void _showFontSelectionError(BuildContext context, String message) {
  showIdeToast(
    context,
    message: message,
    tone: IdeToastTone.error,
    showDuration: const Duration(seconds: 3),
  );
}

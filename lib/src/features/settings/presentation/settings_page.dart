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
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_switch.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/core/rows/ide_row_group.dart';
import 'package:zeta/src/ui/core/rows/ide_settings_row.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/ui/core/workbench/ide_page_body.dart';

enum SettingsSection { general, appearance, agents }

/// 平铺设置行：不自带横向内边距，也不自带分割线。
///
/// 横向对齐交给 `IdePageBody` 的页面 padding，分割线由 [IdeRowGroup] 在行
/// 与行之间统一插入——这样整页只有一套分割线机制。
IdeSettingsRow _flatSettingsRow({
  required String label,
  required String description,
  required Widget control,
  Key? key,
}) {
  return IdeSettingsRow(
    key: key,
    label: label,
    description: description,
    control: control,
    showDivider: false,
    padding: IdeSpacing.settingsRowPaddingFlat,
  );
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({
    required this.activeSection,
    required this.appearanceController,
    required this.generalSettingsController,
    required this.onSectionSelected,
    this.agentManagementController,
    super.key,
  });

  final SettingsSection activeSection;
  final AppearanceSettingsController appearanceController;
  final GeneralSettingsController generalSettingsController;
  final AgentManagementController? agentManagementController;
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
    required this.onSectionSelected,
    required this.showAgentManagement,
    super.key,
  });

  final SettingsSection activeSection;
  final ValueChanged<SettingsSection> onSectionSelected;
  final bool showAgentManagement;

  @override
  Widget build(BuildContext context) {
    return IdeSurface.pane(
      key: const ValueKey('settings-nav-panel'),
      // 无描边：导航与内容区只靠 paneSurface / canvasSurface 的明度差分层，
      // 少一圈线就少一层视觉容器。
      showBorder: false,
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
            onPressed: () => onSectionSelected(SettingsSection.appearance),
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
    final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
    final modifierLabel = isMacOS ? 'Cmd + Enter 发送' : 'Ctrl + Enter 发送';
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: ValueListenableBuilder<GeneralSettings>(
        valueListenable: generalSettingsController.listenable,
        builder: (context, settings, _) {
          final description = switch (settings.sendMessageShortcut) {
            MessageSendShortcut.enter => '按 Enter 发送消息，按 Shift + Enter 换行。',
            MessageSendShortcut.primaryModifierEnter =>
              isMacOS
                  ? '按 Cmd + Enter 发送消息，按 Enter 换行。'
                  : '按 Ctrl + Enter 发送消息，按 Enter 换行。',
          };
          return IdePageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IdeRowGroup(
                  key: const ValueKey('settings-general-group'),
                  title: '消息发送',
                  children: [
                    _flatSettingsRow(
                      key: const ValueKey('settings-send-message-shortcut-row'),
                      label: '发送快捷键',
                      description: description,
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
                              value: MessageSendShortcut.primaryModifierEnter,
                              label: modifierLabel,
                              leadingIcon: Icons.keyboard_command_key_rounded,
                              semanticLabel: modifierLabel,
                            ),
                          ],
                          onChanged: (value) {
                            unawaited(
                              generalSettingsController.setMessageSendShortcut(
                                value,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: IdeSpacing.space32),
                IdeRowGroup(
                  key: const ValueKey('settings-agent-notifications-group'),
                  title: '通知',
                  children: [
                    _flatSettingsRow(
                      key: const ValueKey('settings-notifications-enabled-row'),
                      label: '系统通知',
                      description: '在任务转入后台或其他会话时发送系统提醒。',
                      control: IdeSwitch(
                        key: const ValueKey(
                          'settings-notifications-enabled-switch',
                        ),
                        semanticLabel: '系统通知',
                        value: settings.notifications.enabled,
                        onChanged: (value) {
                          unawaited(
                            generalSettingsController.setNotificationsEnabled(
                              value,
                            ),
                          );
                        },
                      ),
                    ),
                    _flatSettingsRow(
                      key: const ValueKey(
                        'settings-turn-terminal-notifications-row',
                      ),
                      label: '任务结束',
                      description: '任务完成、失败或中断时提醒。',
                      control: IdeSwitch(
                        key: const ValueKey(
                          'settings-turn-terminal-notifications-switch',
                        ),
                        semanticLabel: '任务结束',
                        value: settings.notifications.turnTerminalEnabled,
                        enabled: settings.notifications.enabled,
                        onChanged: settings.notifications.enabled
                            ? (value) {
                                unawaited(
                                  generalSettingsController
                                      .setTurnTerminalNotificationsEnabled(
                                        value,
                                      ),
                                );
                              }
                            : null,
                      ),
                    ),
                    _flatSettingsRow(
                      key: const ValueKey(
                        'settings-action-required-notifications-row',
                      ),
                      label: '需要确认',
                      description: '权限、问题、计划审批或执行确认等待处理时提醒。',
                      control: IdeSwitch(
                        key: const ValueKey(
                          'settings-action-required-notifications-switch',
                        ),
                        semanticLabel: '需要确认',
                        value: settings.notifications.actionRequiredEnabled,
                        enabled: settings.notifications.enabled,
                        onChanged: settings.notifications.enabled
                            ? (value) {
                                unawaited(
                                  generalSettingsController
                                      .setActionRequiredNotificationsEnabled(
                                        value,
                                      ),
                                );
                              }
                            : null,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          );
        },
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
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: ValueListenableBuilder<AppearanceSettings>(
        valueListenable: appearanceController.listenable,
        builder: (context, settings, _) {
          return IdePageBody(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                IdeRowGroup(
                  key: const ValueKey('settings-appearance-group'),
                  title: '主题',
                  children: [
                    _ThemeModeSection(
                      tabs: _tabs,
                      groupValue: settings.themeMode,
                      onSelected: (value) {
                        unawaited(appearanceController.setThemeMode(value));
                      },
                    ),
                  ],
                ),
                const SizedBox(height: IdeSpacing.space32),
                IdeRowGroup(
                  key: const ValueKey('settings-appearance-font-group'),
                  title: '字体',
                  children: [
                    _FontChoiceSettingRow(
                      key: const ValueKey('settings-ui-font-row'),
                      keyPrefix: 'settings-ui-font',
                      label: '界面字体',
                      description: '用于普通界面文本与非代码 Markdown 正文。',
                      selectedChoice: settings.uiFontChoice,
                      selectedLabel: _fontChoiceLabel(
                        settings.uiFontChoice,
                        systemFontDisplayName: appearanceController
                            .displayNameFor(settings.uiFontChoice),
                      ),
                      choicesLoader: appearanceController.loadUiFontChoices,
                      onChanged: appearanceController.setUiFontChoice,
                      errorMessage: '无法加载所选界面字体。',
                    ),
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
                        unawaited(appearanceController.setUiFontSize(value));
                      },
                    ),
                    _FontChoiceSettingRow(
                      key: const ValueKey('settings-code-font-row'),
                      keyPrefix: 'settings-code-font',
                      label: '代码字体',
                      description: '用于代码块、命令、Diff 和工具输出。',
                      selectedChoice: settings.codeFontChoice,
                      selectedLabel: _fontChoiceLabel(
                        settings.codeFontChoice,
                        systemFontDisplayName: appearanceController
                            .displayNameFor(settings.codeFontChoice),
                      ),
                      choicesLoader: appearanceController.loadCodeFontChoices,
                      onChanged: appearanceController.setCodeFontChoice,
                      errorMessage: '无法加载所选代码字体。',
                    ),
                    _FontSizeSettingRow(
                      key: const ValueKey('settings-code-font-size-row'),
                      keyPrefix: 'settings-code-font-size',
                      label: '代码字号',
                      description:
                          '缩放代码内容（${minCodeFontSize.toInt()}–${maxCodeFontSize.toInt()} px）。',
                      value: settings.codeFontSize,
                      min: minCodeFontSize,
                      max: maxCodeFontSize,
                      onChanged: (value) {
                        unawaited(appearanceController.setCodeFontSize(value));
                      },
                    ),
                  ],
                ),
              ],
            ),
          );
        },
      ),
    );
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
    return _flatSettingsRow(
      label: '主题模式',
      description: selectedTab.description,
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

class _FontChoiceSettingRow extends StatefulWidget {
  const _FontChoiceSettingRow({
    required this.keyPrefix,
    required this.label,
    required this.description,
    required this.selectedChoice,
    required this.selectedLabel,
    required this.choicesLoader,
    required this.onChanged,
    required this.errorMessage,
    super.key,
  });

  final String keyPrefix;
  final String label;
  final String description;
  final AppearanceFontChoice selectedChoice;
  final String selectedLabel;
  final Future<List<AppearanceFontOption>> Function() choicesLoader;
  final Future<bool> Function(AppearanceFontChoice choice) onChanged;
  final String errorMessage;

  @override
  State<_FontChoiceSettingRow> createState() => _FontChoiceSettingRowState();
}

class _FontChoiceSettingRowState extends State<_FontChoiceSettingRow> {
  Future<List<AppearanceFontOption>>? _choicesFuture;
  bool _updating = false;

  @override
  void didUpdateWidget(covariant _FontChoiceSettingRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.choicesLoader != widget.choicesLoader) {
      _choicesFuture = null;
    }
  }

  Future<List<AppearanceFontOption>> _loadChoices() {
    return _choicesFuture ??= widget.choicesLoader();
  }

  Future<void> _handleChanged(AppearanceFontChoice? choice) async {
    if (choice == null || choice == widget.selectedChoice || _updating) {
      return;
    }
    setState(() {
      _updating = true;
    });
    final updated = await widget.onChanged(choice);
    if (!mounted) {
      return;
    }
    setState(() {
      _updating = false;
    });
    if (!updated) {
      _showFontSelectionError(context, widget.errorMessage);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return _flatSettingsRow(
      label: widget.label,
      description: widget.description,
      control: Semantics(
        label: '${widget.label}：${widget.selectedLabel}',
        container: true,
        child: sf.Select<AppearanceFontChoice>(
          key: ValueKey<String>('${widget.keyPrefix}-select'),
          value: widget.selectedChoice,
          enabled: !_updating,
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
          popupConstraints: const BoxConstraints(maxHeight: 360),
          itemBuilder: (context, choice) => Text(
            widget.selectedLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.bodyMedium.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: (choice) {
            unawaited(_handleChanged(choice));
          },
          popup: sf.SelectPopup<AppearanceFontChoice>.builder(
            key: ValueKey<String>('${widget.keyPrefix}-select-popup'),
            searchPlaceholder: Text('搜索${widget.label}'),
            loadingBuilder: (context) => SizedBox(
              height: 72,
              child: Center(
                child: IdeLoadingIndicator(
                  key: ValueKey<String>('${widget.keyPrefix}-select-loading'),
                  width: 28,
                  height: 12,
                  barHeight: 4,
                ),
              ),
            ),
            emptyBuilder: (context) => Padding(
              padding: const EdgeInsets.all(IdeSpacing.space16),
              child: Text(
                '没有匹配的字体。',
                textAlign: TextAlign.center,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(IdeSpacing.space16),
              child: Text(
                '字体列表加载失败。',
                textAlign: TextAlign.center,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            builder: (context, searchQuery) async {
              final choices = await _loadChoices();
              final filtered = choices
                  .where((option) => option.matches(searchQuery ?? ''))
                  .toList(growable: false);
              return sf.SelectItemList(
                children: [
                  for (final option in filtered)
                    sf.SelectItemButton<AppearanceFontChoice>(
                      key: ValueKey<String>(
                        '${widget.keyPrefix}-option-'
                        '${option.choice.stableId}',
                      ),
                      value: option.choice,
                      child: Text(
                        option.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.bodyMedium.copyWith(
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                ],
              );
            },
          ).call,
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

    return _flatSettingsRow(
      label: label,
      description: description,
      control: controls,
    );
  }
}

String _fontChoiceLabel(
  AppearanceFontChoice choice, {
  String? systemFontDisplayName,
}) {
  return switch (choice.kind) {
    AppearanceFontChoiceKind.systemDefault => 'Geist（内置默认）',
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

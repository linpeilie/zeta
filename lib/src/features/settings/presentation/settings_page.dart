import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/features/settings/application/appearance_font_option.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/presentation/appearance_theme_mode_mapper.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_slice/agent_management_slice_store.dart';
import 'package:zeta/src/features/agent_management/presentation/agent_management_page.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_state.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_state.dart';
import 'package:zeta/src/features/settings/application/settings_slice/appearance_settings_slice_store.dart';

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
    required this.onSectionSelected,
    this.agentManagementSliceStore,
    super.key,
  });

  final SettingsSection activeSection;
  final AgentManagementSliceStore? agentManagementSliceStore;
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
            showAgentManagement: widget.agentManagementSliceStore != null,
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
            agentManagementSliceStore: widget.agentManagementSliceStore,
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
            title: context.l10n.settingsNavGeneral,
            leading: const Icon(Icons.tune_rounded),
            selected: activeSection == SettingsSection.general,
            onPressed: () => onSectionSelected(SettingsSection.general),
            showDivider: false,
          ),
          IdeListRow(
            key: const ValueKey('settings-nav-appearance'),
            title: context.l10n.settingsNavAppearance,
            leading: const Icon(Icons.palette_outlined),
            selected: activeSection == SettingsSection.appearance,
            onPressed: () => onSectionSelected(SettingsSection.appearance),
            showDivider: false,
          ),
          if (showAgentManagement)
            IdeListRow(
              key: const ValueKey('settings-nav-agents'),
              title: context.l10n.settingsNavAgents,
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
    this.agentManagementSliceStore,
    super.key,
  });

  final SettingsSection activeSection;
  final AgentManagementSliceStore? agentManagementSliceStore;

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
      SettingsSection.general => const _GeneralSettingsPane(),
      SettingsSection.appearance => const _AppearanceSettingsPane(),
      SettingsSection.agents =>
        widget.agentManagementSliceStore == null
            ? IdeSurface.canvas(
                child: EmptyState(text: context.l10n.settingsAgentsUnavailable),
              )
            : AgentManagementPage(
                key: _agentManagementKey,
                sliceStore: widget.agentManagementSliceStore!,
              ),
    };
  }
}

/// general 设置面板的写操作集。
typedef _GeneralSettingsWriteOps = ({
  void Function(AppLanguage language) setAppLanguage,
  void Function(MessageSendShortcut shortcut) setMessageSendShortcut,
  void Function(bool enabled) setNotificationsEnabled,
  void Function(bool enabled) setTurnTerminalNotificationsEnabled,
  void Function(bool enabled) setActionRequiredNotificationsEnabled,
});

class _GeneralSettingsPane extends ConsumerStatefulWidget {
  const _GeneralSettingsPane();

  @override
  ConsumerState<_GeneralSettingsPane> createState() =>
      _GeneralSettingsPaneState();
}

class _GeneralSettingsPaneState extends ConsumerState<_GeneralSettingsPane> {
  void _showLanguageSaveFailedToast() {
    showIdeToast(
      context,
      message: context.l10n.settingsLanguageSaveFailed,
      tone: IdeToastTone.error,
      showDuration: const Duration(seconds: 3),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(generalSettingsSliceStoreProvider);
    // 语言保存失败的 toast：只认 language 这一类失败，其余失败保持静默
    // （快捷键/通知开关失败保持静默）。
    ref.listen(
      generalSettingsSliceProvider.select((state) => state.lastPersistFailure),
      (previous, next) {
        if (next == null ||
            next.operation != GeneralSettingsPersistOperation.language) {
          return;
        }
        _showLanguageSaveFailedToast();
        store.acknowledgeFailure();
      },
    );

    final settings = ref.watch(generalSettingsSliceValueProvider);
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: _generalSettingsBody(
        context: context,
        settings: settings,
        ops: (
          setAppLanguage: store.setAppLanguage,
          setMessageSendShortcut: store.setMessageSendShortcut,
          setNotificationsEnabled: store.setNotificationsEnabled,
          setTurnTerminalNotificationsEnabled:
              store.setTurnTerminalNotificationsEnabled,
          setActionRequiredNotificationsEnabled:
              store.setActionRequiredNotificationsEnabled,
        ),
      ),
    );
  }
}

/// general 设置面板正文。
Widget _generalSettingsBody({
  required BuildContext context,
  required GeneralSettings settings,
  required _GeneralSettingsWriteOps ops,
}) {
  final l10n = context.l10n;
  final isMacOS = Theme.of(context).platform == TargetPlatform.macOS;
  final modifierLabel = isMacOS
      ? l10n.settingsSendShortcutCmdEnter
      : l10n.settingsSendShortcutCtrlEnter;
  final description = switch (settings.sendMessageShortcut) {
    MessageSendShortcut.enter => l10n.settingsSendShortcutEnterHint,
    MessageSendShortcut.primaryModifierEnter =>
      isMacOS
          ? l10n.settingsSendShortcutCmdHint
          : l10n.settingsSendShortcutCtrlHint,
  };
  final effectiveLanguage = ZetaLocalization.languageForLocale(
    Localizations.localeOf(context),
  );
  final languagePending = settings.appLanguage != effectiveLanguage;
  return IdePageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeRowGroup(
          key: const ValueKey('settings-language-group'),
          title: l10n.settingsLanguage,
          children: [
            _flatSettingsRow(
              key: const ValueKey('settings-language-row'),
              label: l10n.settingsLanguage,
              description: languagePending
                  ? l10n.settingsLanguageRestartToApply
                  : l10n.settingsLanguageHint,
              control: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: IdeSelect<AppLanguage>(
                  key: const ValueKey('settings-language-select'),
                  value: settings.appLanguage,
                  popupMinWidth: 180,
                  popupWidthPolicy: IdeSelectPopupWidthPolicy.fitContent,
                  options: <IdeSelectOption<AppLanguage>>[
                    IdeSelectOption<AppLanguage>(
                      AppLanguage.english,
                      l10n.settingsLanguageEnglish,
                      key: const ValueKey('settings-language-english'),
                    ),
                    IdeSelectOption<AppLanguage>(
                      AppLanguage.simplifiedChinese,
                      l10n.settingsLanguageSimplifiedChinese,
                      key: const ValueKey('settings-language-zh-hans'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) {
                      return;
                    }
                    ops.setAppLanguage(value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space32),
        IdeRowGroup(
          key: const ValueKey('settings-general-group'),
          title: l10n.settingsMessageSending,
          children: [
            _flatSettingsRow(
              key: const ValueKey('settings-send-message-shortcut-row'),
              label: l10n.settingsSendShortcut,
              description: description,
              control: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: IdeTabs<MessageSendShortcut>(
                  key: const ValueKey('settings-send-message-shortcut-tabs'),
                  value: settings.sendMessageShortcut,
                  semanticLabel: l10n.settingsSendShortcut,
                  items: <IdeTabItem<MessageSendShortcut>>[
                    IdeTabItem<MessageSendShortcut>(
                      key: const ValueKey(
                        'settings-send-message-shortcut-enter',
                      ),
                      value: MessageSendShortcut.enter,
                      label: l10n.settingsSendShortcutEnter,
                      leadingIcon: Icons.keyboard_return_rounded,
                      semanticLabel: l10n.settingsSendShortcutEnter,
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
                    ops.setMessageSendShortcut(value);
                  },
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space32),
        IdeRowGroup(
          key: const ValueKey('settings-agent-notifications-group'),
          title: l10n.settingsNotifications,
          children: [
            _flatSettingsRow(
              key: const ValueKey('settings-notifications-enabled-row'),
              label: l10n.settingsSystemNotifications,
              description: l10n.settingsSystemNotificationsHint,
              control: IdeSwitch(
                key: const ValueKey('settings-notifications-enabled-switch'),
                semanticLabel: l10n.settingsSystemNotifications,
                value: settings.notifications.enabled,
                onChanged: (value) {
                  ops.setNotificationsEnabled(value);
                },
              ),
            ),
            _flatSettingsRow(
              key: const ValueKey('settings-turn-terminal-notifications-row'),
              label: l10n.settingsTurnTerminalNotifications,
              description: l10n.settingsTurnTerminalNotificationsHint,
              control: IdeSwitch(
                key: const ValueKey(
                  'settings-turn-terminal-notifications-switch',
                ),
                semanticLabel: l10n.settingsTurnTerminalNotifications,
                value: settings.notifications.turnTerminalEnabled,
                enabled: settings.notifications.enabled,
                onChanged: settings.notifications.enabled
                    ? (value) {
                        ops.setTurnTerminalNotificationsEnabled(value);
                      }
                    : null,
              ),
            ),
            _flatSettingsRow(
              key: const ValueKey('settings-action-required-notifications-row'),
              label: l10n.settingsActionRequiredNotifications,
              description: l10n.settingsActionRequiredNotificationsHint,
              control: IdeSwitch(
                key: const ValueKey(
                  'settings-action-required-notifications-switch',
                ),
                semanticLabel: l10n.settingsActionRequiredNotifications,
                value: settings.notifications.actionRequiredEnabled,
                enabled: settings.notifications.enabled,
                onChanged: settings.notifications.enabled
                    ? (value) {
                        ops.setActionRequiredNotificationsEnabled(value);
                      }
                    : null,
              ),
            ),
          ],
        ),
      ],
    ),
  );
}

/// appearance 设置面板的写操作与异步查询集。
///
/// **必须按 store 实例缓存**：`_FontChoiceSettingRow` 用 `choicesLoader` 的闭包
/// 身份判断要不要重置 `_choicesFuture`，每次 build 造新闭包会让字体目录反复重载。
typedef _AppearanceWriteOps = ({
  void Function(ZetaThemeModePreference mode) setThemeMode,
  void Function(double value) setUiFontSize,
  void Function(double value) setCodeFontSize,
  Future<List<AppearanceFontOption>> Function() loadUiFontChoices,
  Future<List<AppearanceFontOption>> Function() loadCodeFontChoices,
  Future<bool> Function(AppearanceFontChoice choice) setUiFontChoice,
  Future<bool> Function(AppearanceFontChoice choice) setCodeFontChoice,
  String Function(AppearanceFontChoice choice) displayNameFor,
});

class _AppearanceSettingsPane extends ConsumerStatefulWidget {
  const _AppearanceSettingsPane();

  @override
  ConsumerState<_AppearanceSettingsPane> createState() =>
      _AppearanceSettingsPaneState();
}

class _AppearanceSettingsPaneState
    extends ConsumerState<_AppearanceSettingsPane> {
  /// 缓存的写操作集与它所属的 store 身份。
  Object? _opsOwner;
  _AppearanceWriteOps? _ops;

  _AppearanceWriteOps _opsFor(
    Object owner,
    _AppearanceWriteOps Function() build,
  ) {
    if (!identical(_opsOwner, owner) || _ops == null) {
      _opsOwner = owner;
      _ops = build();
    }
    return _ops!;
  }

  @override
  Widget build(BuildContext context) {
    final store = ref.watch(appearanceSettingsSliceStoreProvider);
    return _buildSlice(context, store);
  }

  Widget _buildSlice(BuildContext context, AppearanceSettingsSliceStore store) {
    final ops = _opsFor(store, () => _sliceOps(store));
    final settings = ref.watch(appearanceSettingsSliceValueProvider);
    return IdeSurface.canvas(
      key: const ValueKey('settings-detail-panel'),
      child: _appearanceSettingsBody(
        context: context,
        settings: settings,
        tabs: _tabs(context),
        ops: ops,
      ),
    );
  }

  _AppearanceWriteOps _sliceOps(AppearanceSettingsSliceStore store) {
    return (
      setThemeMode: store.selectThemeMode,
      setUiFontSize: store.adjustUiFontSize,
      setCodeFontSize: store.adjustCodeFontSize,
      loadUiFontChoices: () => _loadFontChoices(store, forCodeFont: false),
      loadCodeFontChoices: () => _loadFontChoices(store, forCodeFont: true),
      setUiFontChoice: (choice) =>
          _selectFontChoice(store, choice, forCodeFont: false),
      setCodeFontChoice: (choice) =>
          _selectFontChoice(store, choice, forCodeFont: true),
      displayNameFor: (choice) => _displayNameFor(store, choice),
    );
  }

  /// 目录已在切片里就直接返回，否则请求一次并等回流。
  Future<List<AppearanceFontOption>> _loadFontChoices(
    AppearanceSettingsSliceStore store, {
    required bool forCodeFont,
  }) {
    List<AppearanceFontOption>? current() => forCodeFont
        ? store.state.catalog.codeOptions
        : store.state.catalog.uiOptions;

    final loaded = current();
    if (loaded != null) {
      return Future<List<AppearanceFontOption>>.value(loaded);
    }
    final completer = Completer<List<AppearanceFontOption>>();
    late final void Function() unsubscribe;
    unsubscribe = store.subscribe(() {
      final options = current();
      if (options == null || completer.isCompleted) {
        return;
      }
      unsubscribe();
      completer.complete(options);
    });
    store.requestFontCatalog(forCodeFont: forCodeFont);
    // 请求可能同步回流；这种情况下上面的订阅不会触发。
    final afterRequest = current();
    if (afterRequest != null && !completer.isCompleted) {
      unsubscribe();
      completer.complete(afterRequest);
    }
    return completer.future;
  }

  /// 派发字体选择并等这次操作收口。
  ///
  /// 成功的判据是**值真的变了**：被拒绝时切片会回滚到原值，行据此弹错误 toast，
  /// 行级 `_updating` 已保证单飞。
  Future<bool> _selectFontChoice(
    AppearanceSettingsSliceStore store,
    AppearanceFontChoice choice, {
    required bool forCodeFont,
  }) {
    final operationId = forCodeFont
        ? store.selectCodeFontChoice(choice)
        : store.selectUiFontChoice(choice);

    bool stillPending() {
      final pending = forCodeFont
          ? store.state.pendingCodeFontChoiceOperationId
          : store.state.pendingUiFontChoiceOperationId;
      return pending == operationId;
    }

    bool applied() {
      final value = forCodeFont
          ? store.state.value.codeFontChoice
          : store.state.value.uiFontChoice;
      return value == choice;
    }

    if (!stillPending()) {
      return Future<bool>.value(applied());
    }
    final completer = Completer<bool>();
    late final void Function() unsubscribe;
    unsubscribe = store.subscribe(() {
      if (stillPending() || completer.isCompleted) {
        return;
      }
      unsubscribe();
      completer.complete(applied());
    });
    return completer.future;
  }

  String _displayNameFor(
    AppearanceSettingsSliceStore store,
    AppearanceFontChoice choice,
  ) {
    final family = choice.fontFamily;
    if (family == null) {
      return '';
    }
    return store.state.catalog.displayNames[family.toLowerCase()] ?? family;
  }

  List<_ThemeModeTabSpec> _tabs(BuildContext context) {
    final l10n = context.l10n;
    return <_ThemeModeTabSpec>[
      _ThemeModeTabSpec(
        keyName: 'system',
        title: l10n.settingsThemeFollowSystem,
        icon: Icons.brightness_auto_rounded,
        description: l10n.settingsThemeFollowSystemHint,
        value: ThemeMode.system,
      ),
      _ThemeModeTabSpec(
        keyName: 'light',
        title: l10n.settingsThemeLight,
        icon: Icons.light_mode_outlined,
        description: l10n.settingsThemeLightHint,
        value: ThemeMode.light,
      ),
      _ThemeModeTabSpec(
        keyName: 'dark',
        title: l10n.settingsThemeDark,
        icon: Icons.dark_mode_outlined,
        description: l10n.settingsThemeDarkHint,
        value: ThemeMode.dark,
      ),
    ];
  }
}

/// appearance 设置面板正文。
Widget _appearanceSettingsBody({
  required BuildContext context,
  required AppearanceSettingsSlice settings,
  required List<_ThemeModeTabSpec> tabs,
  required _AppearanceWriteOps ops,
}) {
  final l10n = context.l10n;
  return IdePageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        IdeRowGroup(
          key: const ValueKey('settings-appearance-group'),
          title: l10n.settingsTheme,
          children: [
            _ThemeModeSection(
              tabs: tabs,
              groupValue: themeModeForPreference(settings.themeMode),
              onSelected: (value) {
                ops.setThemeMode(preferenceForThemeMode(value));
              },
            ),
          ],
        ),
        const SizedBox(height: IdeSpacing.space32),
        IdeRowGroup(
          key: const ValueKey('settings-appearance-font-group'),
          title: l10n.settingsFonts,
          children: [
            _FontChoiceSettingRow(
              key: const ValueKey('settings-ui-font-row'),
              keyPrefix: 'settings-ui-font',
              label: l10n.settingsUiFont,
              description: l10n.settingsUiFontHint,
              selectedChoice: settings.uiFontChoice,
              selectedLabel: _fontChoiceLabel(
                context,
                settings.uiFontChoice,
                systemFontDisplayName: ops.displayNameFor(
                  settings.uiFontChoice,
                ),
              ),
              choicesLoader: ops.loadUiFontChoices,
              onChanged: ops.setUiFontChoice,
              errorMessage: l10n.settingsUiFontLoadError,
            ),
            _FontSizeSettingRow(
              key: const ValueKey('settings-ui-font-size-row'),
              keyPrefix: 'settings-ui-font-size',
              label: l10n.settingsUiFontSize,
              description: l10n.settingsUiFontSizeHint(
                '${minUiFontSize.toInt()}',
                '${maxUiFontSize.toInt()}',
              ),
              value: settings.uiFontSize,
              min: minUiFontSize,
              max: maxUiFontSize,
              onChanged: (value) {
                ops.setUiFontSize(value);
              },
            ),
            _FontChoiceSettingRow(
              key: const ValueKey('settings-code-font-row'),
              keyPrefix: 'settings-code-font',
              label: l10n.settingsCodeFont,
              description: l10n.settingsCodeFontHint,
              selectedChoice: settings.codeFontChoice,
              selectedLabel: _fontChoiceLabel(
                context,
                settings.codeFontChoice,
                systemFontDisplayName: ops.displayNameFor(
                  settings.codeFontChoice,
                ),
              ),
              choicesLoader: ops.loadCodeFontChoices,
              onChanged: ops.setCodeFontChoice,
              errorMessage: l10n.settingsCodeFontLoadError,
            ),
            _FontSizeSettingRow(
              key: const ValueKey('settings-code-font-size-row'),
              keyPrefix: 'settings-code-font-size',
              label: l10n.settingsCodeFontSize,
              description: l10n.settingsCodeFontSizeHint(
                '${minCodeFontSize.toInt()}',
                '${maxCodeFontSize.toInt()}',
              ),
              value: settings.codeFontSize,
              min: minCodeFontSize,
              max: maxCodeFontSize,
              onChanged: (value) {
                ops.setCodeFontSize(value);
              },
            ),
          ],
        ),
      ],
    ),
  );
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
    final l10n = context.l10n;
    return _flatSettingsRow(
      label: l10n.settingsThemeMode,
      description: selectedTab.description,
      control: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: IdeTabs<ThemeMode>(
          key: const ValueKey('settings-theme-tabs'),
          value: groupValue,
          semanticLabel: l10n.settingsThemeMode,
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
        label: context.l10n.settingsLabeledValue(
          widget.label,
          widget.selectedLabel,
        ),
        container: true,
        // 这里仍直接用 sf.Select（IdeSelect 尚不支持带搜索的弹层），因此文字档
        // 与展开箭头都显式对齐 IdeSelect：交互控件一律 bodySmall，箭头走等高
        // 图标盒，否则拆掉固定高度后这个下拉会比隔壁的语言下拉高一截。
        child: sf.Select<AppearanceFontChoice>(
          key: ValueKey<String>('${widget.keyPrefix}-select'),
          value: widget.selectedChoice,
          enabled: !_updating,
          expandIcon: IdeSelectExpandIcon(
            color: _updating ? colors.textTertiary : colors.textSecondary,
          ),
          constraints: const BoxConstraints(minWidth: 220, maxWidth: 320),
          popupConstraints: const BoxConstraints(maxHeight: 360),
          itemBuilder: (context, choice) => Text(
            widget.selectedLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: textStyles.bodySmall.copyWith(
              color: colors.textPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          onChanged: (choice) {
            unawaited(_handleChanged(choice));
          },
          popup: sf.SelectPopup<AppearanceFontChoice>.builder(
            key: ValueKey<String>('${widget.keyPrefix}-select-popup'),
            searchPlaceholder: Text(
              context.l10n.settingsSearchSomething(widget.label),
            ),
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
                context.l10n.settingsNoMatchingFonts,
                textAlign: TextAlign.center,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            errorBuilder: (context, error, stackTrace) => Padding(
              padding: const EdgeInsets.all(IdeSpacing.space16),
              child: Text(
                context.l10n.settingsFontListLoadFailed,
                textAlign: TextAlign.center,
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
            builder: (context, searchQuery) async {
              final l10n = context.l10n;
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
                        _fontOptionDisplayLabelFor(l10n, option),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textStyles.bodySmall.copyWith(
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
      label: context.l10n.settingsFontSizeSemantics(label, '${value.toInt()}'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IdeTooltip(
            message: context.l10n.settingsDecreaseSomething(label),
            child: IdeIconButton(
              key: ValueKey<String>('$keyPrefix-decrease'),
              icon: Icons.remove_rounded,
              semanticLabel: context.l10n.settingsDecreaseSomething(label),
              onPressed: canDecrease ? () => onChanged(value - 1) : null,
              controlSize: IdeControlSize.regular,
            ),
          ),
          const SizedBox(width: IdeSpacing.space8),
          SizedBox(
            width: 48,
            child: Text(
              context.l10n.settingsPixelValue('${value.toInt()}'),
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
            message: context.l10n.settingsIncreaseSomething(label),
            child: IdeIconButton(
              key: ValueKey<String>('$keyPrefix-increase'),
              icon: Icons.add_rounded,
              semanticLabel: context.l10n.settingsIncreaseSomething(label),
              onPressed: canIncrease ? () => onChanged(value + 1) : null,
              controlSize: IdeControlSize.regular,
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
  BuildContext context,
  AppearanceFontChoice choice, {
  String? systemFontDisplayName,
}) {
  return switch (choice.kind) {
    AppearanceFontChoiceKind.systemDefault =>
      context.l10n.settingsFontGeistDefault,
    AppearanceFontChoiceKind.bundledJetBrainsMono =>
      context.l10n.settingsFontJetBrainsDefault,
    AppearanceFontChoiceKind.system =>
      systemFontDisplayName ?? choice.fontFamily!,
  };
}

String _fontOptionDisplayLabelFor(
  AppLocalizations l10n,
  AppearanceFontOption option,
) {
  return switch (option.choice.kind) {
    AppearanceFontChoiceKind.systemDefault => l10n.settingsFontGeistDefault,
    AppearanceFontChoiceKind.bundledJetBrainsMono =>
      l10n.settingsFontJetBrainsDefault,
    AppearanceFontChoiceKind.system => option.label,
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

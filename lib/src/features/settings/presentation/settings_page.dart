import 'dart:async';

import 'package:flutter/material.dart';
import 'package:shadcn_ui/shadcn_ui.dart';

import 'package:zeta/src/features/settings/application/appearance_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/appearance_settings.dart';
import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

enum SettingsSection { appearance }

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.activeSection,
    required this.appearanceController,
    required this.onBackPressed,
    required this.onSectionSelected,
    super.key,
  });

  final SettingsSection activeSection;
  final AppearanceSettingsController appearanceController;
  final VoidCallback onBackPressed;
  final ValueChanged<SettingsSection> onSectionSelected;

  static const double _navigationWidth = 240;
  static const double _stackBreakpoint = 900;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useStackedLayout = constraints.maxWidth < _stackBreakpoint;
        final navigation = _SettingsNavigation(
          activeSection: activeSection,
          onBackPressed: onBackPressed,
          onSectionSelected: onSectionSelected,
        );
        final detail = _SettingsDetailPane(
          activeSection: activeSection,
          appearanceController: appearanceController,
        );

        if (useStackedLayout) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(height: 220, child: navigation),
              const SizedBox(height: idePanelGap),
              Expanded(child: detail),
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(width: _navigationWidth, child: navigation),
            const SizedBox(width: idePanelGap),
            Expanded(child: detail),
          ],
        );
      },
    );
  }
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.activeSection,
    required this.onBackPressed,
    required this.onSectionSelected,
  });

  final SettingsSection activeSection;
  final VoidCallback onBackPressed;
  final ValueChanged<SettingsSection> onSectionSelected;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PanelCard(
      key: const ValueKey('settings-nav-panel'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.surfaceElevated),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 44,
              padding: IdeSpacing.horizontal8,
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.borderSubtle)),
              ),
              child: Row(
                children: [
                  IdeTooltip(
                    message: '返回主界面',
                    child: ShadIconButton.ghost(
                      key: const ValueKey('settings-back-button'),
                      onPressed: onBackPressed,
                      width: 28,
                      height: 28,
                      padding: EdgeInsets.zero,
                      foregroundColor: colors.textSecondary,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                    ),
                  ),
                  const SizedBox(width: IdeSpacing.space8),
                  Text(
                    '设置',
                    style: textStyles.displaySmall.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: IdeSpacing.all8,
                children: [
                  _SettingsNavItem(
                    key: const ValueKey('settings-nav-appearance'),
                    label: '外观',
                    icon: Icons.palette_outlined,
                    active: activeSection == SettingsSection.appearance,
                    onTap: () => onSectionSelected(SettingsSection.appearance),
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

class _SettingsDetailPane extends StatelessWidget {
  const _SettingsDetailPane({
    required this.activeSection,
    required this.appearanceController,
  });

  final SettingsSection activeSection;
  final AppearanceSettingsController appearanceController;

  @override
  Widget build(BuildContext context) {
    return switch (activeSection) {
      SettingsSection.appearance => _AppearanceSettingsPane(
        appearanceController: appearanceController,
      ),
    };
  }
}

class _AppearanceSettingsPane extends StatelessWidget {
  const _AppearanceSettingsPane({required this.appearanceController});

  final AppearanceSettingsController appearanceController;

  static const List<_ThemeModeTabSpec> _tabs = <_ThemeModeTabSpec>[
    _ThemeModeTabSpec(
      keyName: 'system',
      title: '跟随系统',
      description: '使用系统当前的浅色或深色偏好。',
      value: ThemeMode.system,
    ),
    _ThemeModeTabSpec(
      keyName: 'light',
      title: '浅色',
      description: '使用浅底、低对比度边框和绿色强调色。',
      value: ThemeMode.light,
    ),
    _ThemeModeTabSpec(
      keyName: 'dark',
      title: '深色',
      description: '使用深底、高对比度面板和明亮强调色。',
      value: ThemeMode.dark,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return PanelCard(
      key: const ValueKey('settings-detail-panel'),
      child: Pane(
        title: '外观',
        subtitle: '切换主题模式、界面字体和代码字体',
        trailing: Icon(
          Icons.palette_outlined,
          size: 16,
          color: colors.textSecondary,
        ),
        child: ValueListenableBuilder<AppearanceSettings>(
          valueListenable: appearanceController.listenable,
          builder: (context, settings, _) {
            final textStyles = IdeTextStyles.of(context);
            final colors = IdeColors.of(context);
            final selectedTab = _tabs.firstWhere(
              (tab) => tab.value == settings.themeMode,
              orElse: () => _tabs.first,
            );
            return SingleChildScrollView(
              padding: IdeSpacing.all16,
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '主题模式',
                        style: textStyles.displayLarge.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space6),
                      Text(
                        '设置页会立即应用主题和字体切换，并保留到下次启动。',
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space16),
                      _ThemeModeTabBar(
                        tabs: _tabs,
                        groupValue: settings.themeMode,
                        onSelected: (value) {
                          unawaited(appearanceController.setThemeMode(value));
                        },
                      ),
                      const SizedBox(height: IdeSpacing.space12),
                      Text(
                        selectedTab.description,
                        key: const ValueKey('settings-theme-description'),
                        style: textStyles.bodySmall.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space24),
                      _AppearanceSettingRow(
                        key: const ValueKey('settings-ui-font-row'),
                        label: '界面字体',
                        description: '用于普通界面文本与非代码 markdown 正文。',
                        value: _fontChoiceLabel(settings.uiFontChoice),
                        onTap: () => _selectUiFont(
                          context,
                          currentChoice: settings.uiFontChoice,
                        ),
                      ),
                      const SizedBox(height: IdeSpacing.space12),
                      _AppearanceSettingRow(
                        key: const ValueKey('settings-code-font-row'),
                        label: '代码字体',
                        description: '仅用于代码块、命令、diff 和工具输出。',
                        value: _fontChoiceLabel(settings.codeFontChoice),
                        onTap: () => _selectCodeFont(
                          context,
                          currentChoice: settings.codeFontChoice,
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
    required this.description,
    required this.value,
  });

  final String keyName;
  final String title;
  final String description;
  final ThemeMode value;
}

class _ThemeModeTabBar extends StatelessWidget {
  const _ThemeModeTabBar({
    required this.tabs,
    required this.groupValue,
    required this.onSelected,
  });

  final List<_ThemeModeTabSpec> tabs;
  final ThemeMode groupValue;
  final ValueChanged<ThemeMode> onSelected;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return DecoratedBox(
      key: const ValueKey('settings-theme-tabs'),
      decoration: BoxDecoration(
        color: colors.surfaceElevated,
        borderRadius: const BorderRadius.all(Radius.circular(idePanelRadius)),
        border: Border.all(color: colors.border),
      ),
      child: Row(
        children: [
          for (var index = 0; index < tabs.length; index++) ...[
            Expanded(
              child: _ThemeModeTabButton(
                key: ValueKey<String>('settings-theme-${tabs[index].keyName}'),
                tab: tabs[index],
                selected: tabs[index].value == groupValue,
                onPressed: () => onSelected(tabs[index].value),
              ),
            ),
            if (index < tabs.length - 1)
              Container(width: 1, height: 40, color: colors.borderSubtle),
          ],
        ],
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
      padding: IdeSpacing.all12,
      borderColor: colors.border,
      hoverBackgroundColor: colors.border.withValues(alpha: 0.12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: textStyles.displaySmall.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: IdeSpacing.space4),
                Text(
                  description,
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: IdeSpacing.space16),
          Flexible(
            child: Row(
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
        ],
      ),
    );
  }
}

class _SettingsNavItem extends StatelessWidget {
  const _SettingsNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.onTap,
    super.key,
  });

  final String label;
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final activeBackground = colors.primaryMuted;
    final foreground = active ? colors.accent : colors.textSecondary;
    return PaneInteractiveSurface(
      onPressed: onTap,
      selected: active,
      height: 40,
      padding: IdeSpacing.horizontal12,
      selectedBackgroundColor: activeBackground,
      selectedBorderColor: colors.accent,
      hoverBackgroundColor: active
          ? activeBackground
          : colors.border.withValues(alpha: 0.12),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: IdeSpacing.space10),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.bodyMedium.copyWith(
                color: foreground,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThemeModeTabButton extends StatelessWidget {
  const _ThemeModeTabButton({
    required this.tab,
    required this.selected,
    required this.onPressed,
    super.key,
  });

  final _ThemeModeTabSpec tab;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final background = selected ? colors.primaryMuted : colors.surfaceElevated;
    return PaneInteractiveSurface(
      onPressed: onPressed,
      selected: selected,
      height: 40,
      borderRadius: BorderRadius.zero,
      backgroundColor: background,
      hoverBackgroundColor: selected
          ? background
          : colors.border.withValues(alpha: 0.12),
      semanticLabel: tab.title,
      child: Semantics(
        selected: selected,
        label: tab.title,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              tab.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: textStyles.titleSmall.copyWith(
                color: selected ? colors.accent : colors.textSecondary,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: IdeSpacing.space4),
            if (selected)
              Container(
                key: ValueKey<String>(
                  'settings-theme-${tab.keyName}-selected-indicator',
                ),
                width: 20,
                height: 2,
                decoration: BoxDecoration(
                  color: colors.accent,
                  borderRadius: const BorderRadius.all(Radius.circular(99)),
                ),
              )
            else
              const SizedBox(height: 2),
          ],
        ),
      ),
    );
  }
}

Future<AppearanceFontChoice?> _showFontPicker({
  required BuildContext context,
  required String title,
  required String searchHint,
  required Future<List<AppearanceFontChoice>> choicesFuture,
  required AppearanceFontChoice selectedChoice,
}) {
  return showShadDialog<AppearanceFontChoice>(
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
  final Future<List<AppearanceFontChoice>> choicesFuture;
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
    return ShadDialog(
      key: const ValueKey('settings-font-picker-dialog'),
      title: Text(widget.title),
      closeIconData: Icons.close_rounded,
      constraints: const BoxConstraints(maxWidth: 560, maxHeight: 520),
      scrollable: false,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      child: SizedBox(
        width: 528,
        height: 420,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ShadInput(
              key: const ValueKey('settings-font-search-field'),
              controller: _searchController,
              autofocus: true,
              onChanged: (value) {
                setState(() {
                  _query = value;
                });
              },
              placeholder: Text(widget.searchHint),
              leading: const Icon(Icons.search_rounded, size: 18),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: FutureBuilder<List<AppearanceFontChoice>>(
                future: widget.choicesFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return Center(
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
                      snapshot.data ?? const <AppearanceFontChoice>[];
                  final filtered = choices
                      .where((choice) => _matchesFontQuery(choice, _query))
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
                      final choice = filtered[index];
                      final selected = choice == widget.selectedChoice;
                      return ShadButton.ghost(
                        key: ValueKey<String>(
                          'settings-font-option-${choice.stableId}',
                        ),
                        onPressed: () => Navigator.of(context).pop(choice),
                        width: double.infinity,
                        height: 36,
                        expands: true,
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        backgroundColor: selected
                            ? colors.primaryMuted
                            : Colors.transparent,
                        hoverBackgroundColor: selected
                            ? colors.primaryMuted.withValues(alpha: 0.18)
                            : null,
                        trailing: selected
                            ? Icon(
                                Icons.check_rounded,
                                size: 18,
                                color: colors.accent,
                              )
                            : null,
                        child: Text(
                          _fontChoiceLabel(choice),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.bodyMedium,
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
    );
  }
}

bool _matchesFontQuery(AppearanceFontChoice choice, String query) {
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return true;
  }
  return _fontChoiceLabel(choice).toLowerCase().contains(normalizedQuery);
}

String _fontChoiceLabel(AppearanceFontChoice choice) {
  return switch (choice.kind) {
    AppearanceFontChoiceKind.systemDefault => '系统默认',
    AppearanceFontChoiceKind.bundledJetBrainsMono => 'JetBrainsMono（内置默认）',
    AppearanceFontChoiceKind.system => choice.fontFamily!,
  };
}

void _showFontSelectionError(BuildContext context, String message) {
  final sonner = ShadSonner.maybeOf(context);
  if (sonner == null) {
    return;
  }
  sonner.show(
    ShadToast.destructive(
      description: Text(message),
      duration: const Duration(seconds: 3),
    ),
  );
}

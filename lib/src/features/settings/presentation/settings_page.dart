import 'dart:async';

import 'package:flutter/material.dart';

import 'package:zeta/src/ui/core/app_theme.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/theme_mode_controller.dart';

enum SettingsSection { appearance }

class SettingsPage extends StatelessWidget {
  const SettingsPage({
    required this.activeSection,
    required this.themeModeController,
    required this.onBackPressed,
    required this.onSectionSelected,
    super.key,
  });

  final SettingsSection activeSection;
  final ThemeModeController themeModeController;
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
          themeModeController: themeModeController,
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
    return PanelCard(
      key: const ValueKey('settings-nav-panel'),
      child: DecoratedBox(
        decoration: BoxDecoration(color: colors.panel),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colors.border)),
              ),
              child: Row(
                children: [
                  Tooltip(
                    message: '返回主界面',
                    child: IconButton(
                      key: const ValueKey('settings-back-button'),
                      onPressed: onBackPressed,
                      icon: const Icon(Icons.arrow_back_rounded, size: 18),
                      color: colors.mutedText,
                      visualDensity: VisualDensity.compact,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '设置',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.all(8),
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
    required this.themeModeController,
  });

  final SettingsSection activeSection;
  final ThemeModeController themeModeController;

  @override
  Widget build(BuildContext context) {
    return switch (activeSection) {
      SettingsSection.appearance => _AppearanceSettingsPane(
        themeModeController: themeModeController,
      ),
    };
  }
}

class _AppearanceSettingsPane extends StatelessWidget {
  const _AppearanceSettingsPane({required this.themeModeController});

  final ThemeModeController themeModeController;

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
    return PanelCard(
      key: const ValueKey('settings-detail-panel'),
      child: Pane(
        title: '外观',
        subtitle: '切换窗口主题模式',
        trailing: Icon(
          Icons.palette_outlined,
          size: 16,
          color: IdeColors.of(context).mutedText,
        ),
        child: ValueListenableBuilder<ThemeMode>(
          valueListenable: themeModeController.listenable,
          builder: (context, mode, _) {
            final selectedTab = _tabs.firstWhere(
              (tab) => tab.value == mode,
              orElse: () => _tabs.first,
            );
            return SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 760),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        '主题模式',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '设置页会立即应用主题切换，并保留到下次启动。',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: IdeColors.of(context).mutedText,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _ThemeModeTabBar(
                        tabs: _tabs,
                        groupValue: mode,
                        onSelected: (value) {
                          unawaited(themeModeController.setMode(value));
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        selectedTab.description,
                        key: const ValueKey('settings-theme-description'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: IdeColors.of(context).mutedText,
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
        color: colors.surface,
        borderRadius: BorderRadius.circular(idePanelRadius),
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
              Container(width: 1, height: 40, color: colors.border),
          ],
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
    final activeBackground = colors.accent.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? 0.18 : 0.1,
    );
    final foreground = active ? colors.accentForeground : colors.mutedText;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(idePanelRadius),
        child: Ink(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: active ? activeBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(idePanelRadius),
            border: Border.all(
              color: active ? colors.accent : Colors.transparent,
            ),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: foreground),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: foreground,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),
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
    final background = selected
        ? colors.accent.withValues(
            alpha: Theme.of(context).brightness == Brightness.dark
                ? 0.16
                : 0.08,
          )
        : colors.surface;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onPressed,
        child: Ink(
          height: 40,
          decoration: BoxDecoration(color: background),
          child: Semantics(
            button: true,
            selected: selected,
            label: tab.title,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  tab.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: selected
                        ? colors.accentForeground
                        : colors.mutedText,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                if (selected)
                  Container(
                    key: ValueKey<String>(
                      'settings-theme-${tab.keyName}-selected-indicator',
                    ),
                    width: 20,
                    height: 2,
                    decoration: BoxDecoration(
                      color: colors.accent,
                      borderRadius: BorderRadius.circular(99),
                    ),
                  )
                else
                  const SizedBox(height: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

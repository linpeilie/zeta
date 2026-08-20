import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/settings/cubit/settings_cubit.dart';
import 'package:zeta/settings/cubit/settings_state.dart';

class SettingsView extends StatelessWidget {
  const SettingsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<SettingsCubit, SettingsState>(
      builder: (context, state) {
        if (state.status == SettingsStatus.loading ||
            state.status == SettingsStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(title: l10n.settingsNavGeneral),
            Expanded(
              child: IdePageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (state.failure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).settingsFailure(state.failure!.code),
                      ),
                    IdeSection(
                      title: l10n.settingsMessageSending,
                      child: IdeSettingsRow(
                        label: l10n.settingsSendShortcut,
                        description: l10n.settingsSendShortcutEnterHint,
                        control: Switch(
                          value:
                              state.general.sendMessageShortcut ==
                              MessageSendShortcut.enter,
                          onChanged: (value) {
                            unawaited(
                              context
                                  .read<SettingsCubit>()
                                  .setMessageSendShortcut(
                                    value
                                        ? MessageSendShortcut.enter
                                        : MessageSendShortcut
                                              .primaryModifierEnter,
                                  ),
                            );
                          },
                        ),
                      ),
                    ),
                    IdeSection(
                      title: l10n.settingsNotifications,
                      child: Column(
                        children: <Widget>[
                          IdeSettingsRow(
                            label: l10n.settingsSystemNotifications,
                            description: l10n.settingsSystemNotificationsHint,
                            control: Switch(
                              value: state.general.notifications.enabled,
                              onChanged: (value) {
                                unawaited(
                                  context
                                      .read<SettingsCubit>()
                                      .setNotificationsEnabled(
                                        enabled: value,
                                      ),
                                );
                              },
                            ),
                          ),
                          IdeSettingsRow(
                            label: l10n.settingsTurnTerminalNotifications,
                            control: Switch(
                              value: state
                                  .general
                                  .notifications
                                  .turnTerminalEnabled,
                              onChanged: (value) {
                                unawaited(
                                  context
                                      .read<SettingsCubit>()
                                      .setTurnTerminalNotificationsEnabled(
                                        enabled: value,
                                      ),
                                );
                              },
                            ),
                          ),
                          IdeSettingsRow(
                            label: l10n.settingsActionRequiredNotifications,
                            showDivider: false,
                            control: Switch(
                              value: state
                                  .general
                                  .notifications
                                  .actionRequiredEnabled,
                              onChanged: (value) {
                                unawaited(
                                  context
                                      .read<SettingsCubit>()
                                      .setActionRequiredNotificationsEnabled(
                                        enabled: value,
                                      ),
                                );
                              },
                            ),
                          ),
                        ],
                      ),
                    ),
                    IdeSection(
                      title: l10n.settingsLanguage,
                      subtitle: l10n.settingsLanguageHint,
                      child: Column(
                        children: <Widget>[
                          IdeSettingsRow(
                            label: l10n.settingsLanguageEnglish,
                            control: Switch(
                              value:
                                  state.general.appLanguage ==
                                  AppLanguage.english,
                              onChanged: (value) {
                                unawaited(
                                  context.read<SettingsCubit>().setAppLanguage(
                                    value
                                        ? AppLanguage.english
                                        : AppLanguage.simplifiedChinese,
                                  ),
                                );
                              },
                            ),
                          ),
                          if (state.languageRestartRequired)
                            EmptyState(
                              text: l10n.settingsLanguageRestartToApply,
                            ),
                        ],
                      ),
                    ),
                    IdeSection(
                      title: l10n.settingsTheme,
                      child: IdeSettingsRow(
                        label: l10n.settingsThemeDark,
                        description: l10n.settingsThemeDarkHint,
                        showDivider: false,
                        control: Switch(
                          value:
                              state.appearance.themeMode ==
                              SettingsThemeMode.dark,
                          onChanged: (value) {
                            context.read<SettingsCubit>().setThemeMode(
                              value
                                  ? SettingsThemeMode.dark
                                  : SettingsThemeMode.system,
                            );
                          },
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
}

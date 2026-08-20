import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/settings/cubit/settings_cubit.dart';
import 'package:zeta/settings/view/settings_view.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final dependencies = context.read<AppDependencies>();
    final language = resolveAppLanguageFromFirstSystemLocale(
      languageCode: dependencies.locale.languageCode,
      scriptCode: dependencies.locale.scriptCode,
      countryCode: dependencies.locale.countryCode,
    );
    return BlocProvider(
      create: (context) {
        final cubit = SettingsCubit(
          settingsRepository: context.read<SettingsRepository>(),
          processLanguage: language,
          fontLocaleName: dependencies.locale.toLanguageTag(),
        );
        unawaited(cubit.load());
        return cubit;
      },
      child: const SettingsView(),
    );
  }
}

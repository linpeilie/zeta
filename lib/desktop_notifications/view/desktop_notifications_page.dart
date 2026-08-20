import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/app/app_dependencies.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_bloc.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_event.dart';
import 'package:zeta/desktop_notifications/view/desktop_notifications_view.dart';

class DesktopNotificationsPage extends StatelessWidget {
  const DesktopNotificationsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DesktopNotificationsBloc(
        settingsRepository: context.read<SettingsRepository>(),
        notificationsRepository: context.read<DesktopNotificationsRepository>(),
        copyResolver: context
            .read<AppDependencies>()
            .desktopNotificationCopyResolver,
      )..add(const DesktopNotificationsSubscriptionRequested()),
      child: const DesktopNotificationsView(),
    );
  }
}

import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_bloc.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_event.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_state.dart';
import 'package:zeta/l10n/l10n.dart';

class DesktopNotificationsView extends StatelessWidget {
  const DesktopNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<DesktopNotificationsBloc, DesktopNotificationsState>(
      builder: (context, state) {
        final failure = state.failure;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(title: l10n.settingsNotifications),
            Expanded(
              child: IdePageBody(
                child: Column(
                  children: <Widget>[
                    if (failure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).desktopNotificationFailure(failure),
                      )
                    else
                      EmptyState(
                        text:
                            '${l10n.settingsNotifications}: '
                            '${state.badgeCount}',
                      ),
                    if (state.unread.isNotEmpty)
                      TextButton(
                        onPressed: () {
                          final attention = state.unread.values.first;
                          context.read<DesktopNotificationsBloc>().add(
                            DesktopNotificationsThreadMarkedRead(
                              providerId: attention.providerId,
                              threadId: attention.threadId,
                            ),
                          );
                        },
                        child: Text(l10n.agentCancel),
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

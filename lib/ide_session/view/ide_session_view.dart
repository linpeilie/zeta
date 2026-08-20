import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/ide_session/cubit/ide_session_cubit.dart';
import 'package:zeta/ide_session/cubit/ide_session_state.dart';
import 'package:zeta/l10n/l10n.dart';

class IdeSessionView extends StatelessWidget {
  const IdeSessionView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<IdeSessionCubit, IdeSessionState>(
      builder: (context, state) {
        if (state.status == IdeSessionStatus.restoring ||
            state.status == IdeSessionStatus.initial) {
          return const Center(child: CircularProgressIndicator());
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(
              title: l10n.homeOpenProject,
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    unawaited(context.read<IdeSessionCubit>().flush());
                  },
                  child: Text(l10n.projectRefreshSessions),
                ),
              ],
            ),
            Expanded(
              child: IdePageBody(
                child: Column(
                  children: <Widget>[
                    if (state.failure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).projectSessionFailure(state.failure!.code),
                      )
                    else
                      EmptyState(
                        text:
                            state.initialRoute.projectPath ??
                            l10n.homeWelcomeSubtitle,
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

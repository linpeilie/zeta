import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_bloc.dart';
import 'package:zeta/ide_shell/bloc/ide_shell_event.dart';
import 'package:zeta/l10n/l10n.dart';

class IdeHomePage extends StatelessWidget {
  const IdeHomePage({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IdePageHeader(title: l10n.homeOpenProject),
        Expanded(
          child: IdePageBody(
            child: TextButton(
              key: const Key('ide-home-open-project'),
              onPressed: () {
                context.read<IdeShellBloc>().add(
                  const IdeShellOpenProjectRequested(),
                );
              },
              child: Text(l10n.homeOpenProjectFolder),
            ),
          ),
        ),
      ],
    );
  }
}

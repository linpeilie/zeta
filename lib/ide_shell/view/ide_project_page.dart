import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:workspace_repository/workspace_repository.dart';
import 'package:zeta/l10n/l10n.dart';

class IdeProjectPage extends StatelessWidget {
  const IdeProjectPage({required this.projectId, super.key});

  final String projectId;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final path = context.read<WorkspaceRepository>().resolveProjectPath(
      projectId,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IdePageHeader(title: path ?? l10n.homeOpenProject),
        const Expanded(child: SizedBox.expand()),
      ],
    );
  }
}

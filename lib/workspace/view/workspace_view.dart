import 'dart:async';

import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/workspace/cubit/workspace_cubit.dart';
import 'package:zeta/workspace/cubit/workspace_state.dart';

class WorkspaceView extends StatelessWidget {
  const WorkspaceView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<WorkspaceCubit, WorkspaceState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(
              title: l10n.homeOpenProject,
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    unawaited(context.read<WorkspaceCubit>().pickRoot());
                  },
                  child: Text(l10n.homeOpenProjectFolder),
                ),
                if (state.selectedPath != null)
                  TextButton(
                    onPressed: () {
                      unawaited(
                        context.read<WorkspaceCubit>().reveal(
                          state.selectedPath!,
                        ),
                      );
                    },
                    child: Text(l10n.projectOpenInFileManager),
                  ),
              ],
            ),
            Expanded(child: _WorkspaceBody(state: state)),
          ],
        );
      },
    );
  }
}

class _WorkspaceBody extends StatelessWidget {
  const _WorkspaceBody({required this.state});

  final WorkspaceState state;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    if (state.status == WorkspaceStatus.loading && state.rootPath == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (state.rootPath == null) {
      return EmptyState(text: l10n.homeWelcomeSubtitle);
    }
    if (state.status == WorkspaceStatus.failure && state.failure != null) {
      return EmptyState(
        text: FailureMessages(l10n).workspaceFailure(state.failure!.code),
      );
    }
    final children = state.childrenOf(state.rootPath!);
    if (children.isEmpty) {
      return EmptyState(text: l10n.homeWelcomeSubtitle);
    }
    return ListView(
      children: <Widget>[
        for (final node in children) _WorkspaceNodeTile(node: node),
      ],
    );
  }
}

class _WorkspaceNodeTile extends StatelessWidget {
  const _WorkspaceNodeTile({required this.node});

  final WorkspaceNode node;

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<WorkspaceCubit>();
    final state = context.watch<WorkspaceCubit>().state;
    final selected = state.selectedPath == node.path;
    final expanded = state.isExpanded(node.path);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        IdeListRow(
          title: node.name,
          selected: selected,
          onPressed: () {
            cubit.select(node.path);
            if (node.isDirectory) {
              unawaited(cubit.toggle(node.path));
            }
          },
          leading: Icon(
            node.isDirectory
                ? (expanded ? Icons.folder_open : Icons.folder)
                : Icons.insert_drive_file_outlined,
          ),
        ),
        if (node.isDirectory && expanded)
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 16),
            child: Column(
              children: <Widget>[
                for (final child in state.childrenOf(node.path))
                  _WorkspaceNodeTile(node: child),
              ],
            ),
          ),
      ],
    );
  }
}

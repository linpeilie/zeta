import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/l10n/l10n.dart';
import 'package:zeta/project_threads/bloc/project_threads_bloc.dart';
import 'package:zeta/project_threads/bloc/project_threads_event.dart';
import 'package:zeta/project_threads/bloc/project_threads_state.dart';

class ProjectThreadsView extends StatelessWidget {
  const ProjectThreadsView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<ProjectThreadsBloc, ProjectThreadsState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(
              title: l10n.projectNewSession,
              actions: <Widget>[
                TextButton(
                  onPressed: () {
                    context.read<ProjectThreadsBloc>().add(
                      const ProjectThreadsRefreshRequested(),
                    );
                  },
                  child: Text(l10n.projectRefreshSessions),
                ),
              ],
            ),
            Expanded(
              child: IdePageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    TextField(
                      decoration: InputDecoration(
                        hintText: l10n.agentToolSearch,
                      ),
                      onChanged: (value) {
                        context.read<ProjectThreadsBloc>().add(
                          ProjectThreadsSearchChanged(value),
                        );
                      },
                    ),
                    IdeSettingsRow(
                      label: l10n.threadArchive,
                      showDivider: false,
                      control: Switch(
                        value: state.archived,
                        onChanged: (value) {
                          context.read<ProjectThreadsBloc>().add(
                            ProjectThreadsArchivedFilterChanged(
                              archived: value,
                            ),
                          );
                        },
                      ),
                    ),
                    if (state.sessionFailure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).projectSessionFailure(state.sessionFailure!.code),
                      )
                    else if (state.providerFailure != null)
                      EmptyState(
                        text: FailureMessages(l10n).agentProviderFailure(
                          state.providerFailure!.code,
                          providerName: l10n.projectNewSession,
                        ),
                      )
                    else if (state.status == ProjectThreadsStatus.loading)
                      const Center(child: CircularProgressIndicator())
                    else if (state.threads.isEmpty)
                      EmptyState(text: l10n.projectNoRecentSessions)
                    else
                      for (final thread in state.threads)
                        IdeListRow(
                          title: thread.displayName,
                          selected: state.selectedThreadId == thread.id,
                          onPressed: () {
                            context.read<ProjectThreadsBloc>().add(
                              ProjectThreadsThreadSelected(thread.id),
                            );
                          },
                        ),
                    if (state.hasMore)
                      TextButton(
                        onPressed: () {
                          context.read<ProjectThreadsBloc>().add(
                            const ProjectThreadsLoadMoreRequested(),
                          );
                        },
                        child: Text(l10n.projectRetryLoadSessions),
                      ),
                    if (state.selectedThreadId != null)
                      Wrap(
                        children: <Widget>[
                          TextButton(
                            onPressed: () {
                              context.read<ProjectThreadsBloc>().add(
                                ProjectThreadsRenameRequested(
                                  threadId: state.selectedThreadId!,
                                  name: l10n.agentRename,
                                ),
                              );
                            },
                            child: Text(l10n.threadRename),
                          ),
                          TextButton(
                            onPressed: () {
                              context.read<ProjectThreadsBloc>().add(
                                ProjectThreadsArchiveRequested(
                                  state.selectedThreadId!,
                                ),
                              );
                            },
                            child: Text(l10n.threadArchive),
                          ),
                          TextButton(
                            onPressed: () {
                              context.read<ProjectThreadsBloc>().add(
                                ProjectThreadsUnarchiveRequested(
                                  state.selectedThreadId!,
                                ),
                              );
                            },
                            child: Text(l10n.threadUnarchive),
                          ),
                          TextButton(
                            onPressed: () {
                              context.read<ProjectThreadsBloc>().add(
                                ProjectThreadsDeleteRequested(
                                  state.selectedThreadId!,
                                ),
                              );
                            },
                            child: Text(l10n.threadDelete),
                          ),
                        ],
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

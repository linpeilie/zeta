import 'package:app_ui/app_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:zeta/agent_management/bloc/agent_management_bloc.dart';
import 'package:zeta/agent_management/bloc/agent_management_event.dart';
import 'package:zeta/agent_management/bloc/agent_management_state.dart';
import 'package:zeta/l10n/l10n.dart';

class AgentManagementView extends StatelessWidget {
  const AgentManagementView({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return BlocBuilder<AgentManagementBloc, AgentManagementState>(
      builder: (context, state) {
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            IdePageHeader(title: l10n.settingsNavAgents),
            Expanded(
              child: IdePageBody(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    if (state.failure != null)
                      EmptyState(
                        text: FailureMessages(
                          l10n,
                        ).agentManagementFailure(state.failure!.code),
                      ),
                    for (final definition in state.definitions)
                      IdeListRow(
                        title: definition.displayName,
                        selected:
                            state.selectedProviderId == definition.providerId,
                        onPressed: () {
                          context.read<AgentManagementBloc>().add(
                            AgentManagementAgentSelected(
                              definition.providerId,
                            ),
                          );
                        },
                      ),
                    Wrap(
                      children: <Widget>[
                        TextButton(
                          onPressed: state.detecting
                              ? null
                              : () {
                                  context.read<AgentManagementBloc>().add(
                                    const AgentManagementDetectRequested(),
                                  );
                                },
                          child: Text(
                            state.detecting
                                ? l10n.mgmtDetecting
                                : l10n.mgmtDetectingShort,
                          ),
                        ),
                        TextButton(
                          onPressed: state.testing
                              ? null
                              : () {
                                  context.read<AgentManagementBloc>().add(
                                    const AgentManagementTestRequested(),
                                  );
                                },
                          child: Text(
                            state.testing
                                ? l10n.mgmtTesting
                                : l10n.mgmtTestConnection,
                          ),
                        ),
                        TextButton(
                          onPressed: state.saving
                              ? null
                              : () {
                                  context.read<AgentManagementBloc>().add(
                                    const AgentManagementConfigSaveRequested(),
                                  );
                                },
                          child: Text(
                            state.saving
                                ? l10n.mgmtSaving
                                : l10n.mgmtSaveConfig,
                          ),
                        ),
                        TextButton(
                          onPressed:
                              state.status == AgentManagementStatus.loading
                              ? null
                              : () {
                                  context.read<AgentManagementBloc>().add(
                                    const AgentManagementLogsRequested(),
                                  );
                                },
                          child: Text(
                            l10n.mgmtRuntimeLogsTitle(
                              state.selectedDefinition?.displayName ?? '',
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (state.detecting)
                      Semantics(
                        liveRegion: true,
                        child: EmptyState(text: l10n.mgmtDetecting),
                      ),
                    if (state.testing)
                      Semantics(
                        liveRegion: true,
                        child: EmptyState(text: l10n.mgmtTesting),
                      ),
                    if (state.saving)
                      Semantics(
                        liveRegion: true,
                        child: EmptyState(text: l10n.mgmtSaving),
                      ),
                    TextFormField(
                      key: ValueKey<String>(
                        '${state.selectedProviderId}-'
                        '${state.document?.signature}',
                      ),
                      initialValue: state.editorContents,
                      decoration: InputDecoration(
                        labelText: l10n.mgmtConfigFile,
                      ),
                      onChanged: (value) {
                        context.read<AgentManagementBloc>().add(
                          AgentManagementConfigEdited(value),
                        );
                      },
                    ),
                    if (state.detection != null)
                      EmptyState(
                        text: state.detection!.installed
                            ? l10n.mgmtFound(
                                state.selectedDefinition?.displayName ?? '',
                              )
                            : l10n.mgmtNotFound(
                                state.selectedDefinition?.displayName ?? '',
                              ),
                      ),
                    if (state.connectionTest case final test?)
                      EmptyState(
                        text: test.success
                            ? l10n.mgmtConnectionTestSuccess(
                                '${test.elapsed.inMilliseconds}',
                              )
                            : l10n.mgmtConnectionTestFailed(
                                l10n.mgmtNotUpdated,
                              ),
                      ),
                    if (!state.validation.isValid)
                      EmptyState(text: l10n.mgmtConfigExternallyModified),
                    for (final log in state.logs)
                      IdeListRow(title: log.message),
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

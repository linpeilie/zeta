import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  test('workbench snapshots compare structurally', () {
    final width = double.parse('300');
    final first = ProjectWorkbenchSnapshot(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: width,
      agentUsageHeightFraction: 0.4,
      selectedAgentUsageProviderId: 'p',
    );
    expect(
      first,
      ProjectWorkbenchSnapshot(
        leftSidebarVisible: false,
        agentUsageExpanded: true,
        leftSidebarWidth: width,
        agentUsageHeightFraction: 0.4,
        selectedAgentUsageProviderId: 'p',
      ),
    );
  });

  test('session snapshots deeply freeze and compare persisted fields', () {
    final paths = <String>['/repo'];
    final expanded = <String>{'/repo/lib'};
    final cachedThread = thread(id: 't', providerId: 'p');
    final cached = <String, List<AgentThreadSummary>>{
      '/repo': <AgentThreadSummary>[cachedThread],
    };
    final first = ProjectSessionSnapshot(
      projectPaths: paths,
      activeProjectPath: '/repo',
      currentFilePath: '/repo/a',
      expandedDirectoryPaths: expanded,
      selectedTreeKey: 'a',
      activeAgentProviderId: 'p',
      agentThreadIdsByProject: const <String, String>{'/repo': 't'},
      projectThreadExpansionByProject: const <String, bool>{'/repo': true},
      cachedThreadsByProject: cached,
      selectedThreadIdsByProject: const <String, String>{'/repo': 't'},
      projectLastOpenedAtByPath: <String, DateTime>{
        '/repo': DateTime.fromMillisecondsSinceEpoch(1),
      },
      projectHomeActive: true,
      workbench: const ProjectWorkbenchSnapshot(agentUsageExpanded: true),
    );
    paths.clear();
    expanded.clear();
    cached['/repo']!.clear();

    expect(first.projectPaths, <String>['/repo']);
    expect(first.expandedDirectoryPaths, <String>{'/repo/lib'});
    expect(first.cachedThreadsByProject['/repo'], <AgentThreadSummary>[
      cachedThread,
    ]);
    expect(
      first,
      ProjectSessionSnapshot(
        projectPaths: const <String>['/repo'],
        activeProjectPath: '/repo',
        currentFilePath: '/repo/a',
        expandedDirectoryPaths: const <String>{'/repo/lib'},
        selectedTreeKey: 'a',
        activeAgentProviderId: 'p',
        agentThreadIdsByProject: const <String, String>{'/repo': 't'},
        projectThreadExpansionByProject: const <String, bool>{'/repo': true},
        cachedThreadsByProject: <String, List<AgentThreadSummary>>{
          '/repo': <AgentThreadSummary>[cachedThread],
        },
        selectedThreadIdsByProject: const <String, String>{'/repo': 't'},
        projectLastOpenedAtByPath: <String, DateTime>{
          '/repo': DateTime.fromMillisecondsSinceEpoch(1),
        },
        projectHomeActive: true,
        workbench: const ProjectWorkbenchSnapshot(agentUsageExpanded: true),
      ),
    );
    expect(first.projectPaths.clear, throwsUnsupportedError);
    expect(first.expandedDirectoryPaths.clear, throwsUnsupportedError);
    expect(first.cachedThreadsByProject.clear, throwsUnsupportedError);
    expect(
      first.cachedThreadsByProject['/repo']!.clear,
      throwsUnsupportedError,
    );
  });

  test('thread queries and pages freeze and compare structurally', () {
    final kinds = <String>['local'];
    final firstQuery = ProjectThreadQuery(
      projectPath: '/repo',
      limit: 2,
      cursor: 'agg:1',
      archived: true,
      searchTerm: ' title ',
      sourceKinds: kinds,
    );
    kinds.clear();
    expect(firstQuery.searchTerm, 'title');
    expect(firstQuery.sourceKinds, <String>['local']);
    expect(
      firstQuery,
      ProjectThreadQuery(
        projectPath: '/repo',
        limit: 2,
        cursor: 'agg:1',
        archived: true,
        searchTerm: 'title',
        sourceKinds: const <String>['local'],
      ),
    );
    expect(
      ProjectThreadQuery(projectPath: '/repo', searchTerm: ' ').searchTerm,
      isNull,
    );

    final summary = thread(id: 't', providerId: 'p');
    final failures = <ProjectThreadProviderFailure>[
      const ProjectThreadProviderFailure(
        providerId: 'p',
        code: ProjectThreadProviderFailureCode.externalFailure,
      ),
    ];
    final firstPage = ProjectThreadPage(
      threads: <AgentThreadSummary>[summary],
      nextCursor: 'agg:1',
      failures: failures,
    );
    failures.clear();
    expect(
      firstPage,
      ProjectThreadPage(
        threads: <AgentThreadSummary>[summary],
        nextCursor: 'agg:1',
        failures: const <ProjectThreadProviderFailure>[
          ProjectThreadProviderFailure(
            providerId: 'p',
            code: ProjectThreadProviderFailureCode.externalFailure,
          ),
        ],
      ),
    );
    expect(firstPage.threads.clear, throwsUnsupportedError);
    expect(firstPage.failures.clear, throwsUnsupportedError);
  });

  test('Repository failures compare structurally', () {
    final diagnostic = <String>['project_session_restore_failed'].single;
    final first = ProjectSessionRepositoryFailure(
      operation: ProjectSessionRepositoryOperation.restore,
      code: ProjectSessionRepositoryFailureCode.externalFailure,
      diagnosticCode: diagnostic,
    );
    expect(
      first,
      ProjectSessionRepositoryFailure(
        operation: ProjectSessionRepositoryOperation.restore,
        code: ProjectSessionRepositoryFailureCode.externalFailure,
        diagnosticCode: diagnostic,
      ),
    );
  });
}

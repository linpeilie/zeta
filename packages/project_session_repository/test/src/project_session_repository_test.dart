import 'dart:async';
import 'dart:convert';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:project_session_client/project_session_client.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:test/test.dart';

import '../helpers/fakes.dart';

void main() {
  late FakeProjectSessionStorage storage;
  late ProjectSessionStore store;
  late ProjectSessionRepository repository;

  ProjectSessionRepository createRepository({
    Map<String, AgentThreadCatalogPort> catalogs =
        const <String, AgentThreadCatalogPort>{},
  }) {
    store = ProjectSessionStore(storage: storage, writeDelay: Duration.zero);
    return repository = ProjectSessionRepository(
      store: store,
      threadCatalogs: catalogs,
    );
  }

  setUp(() {
    storage = FakeProjectSessionStorage();
  });

  tearDown(() async {
    try {
      await repository.close();
    } on Object {
      // Close-failure tests assert the typed result.
    }
  });

  group('snapshot persistence', () {
    test(
      'restores and publishes the complete current-schema snapshot',
      () async {
        final response = sampleResponse();
        storage.source = jsonEncode(
          const SessionSnapshotCodec().encode(response),
        );
        final changes = <ProjectSessionSnapshot?>[];
        createRepository().snapshotChanges.listen(changes.add);

        final result = await repository.restore();

        expect(result, isNotNull);
        expect(result!.projectPaths, <String>['/repo']);
        expect(result.activeProjectPath, '/repo');
        expect(result.currentFilePath, '/repo/lib/main.dart');
        expect(result.expandedDirectoryPaths, <String>{'/repo/lib'});
        expect(result.selectedTreeKey, 'file:/repo/lib/main.dart');
        expect(result.activeAgentProviderId, 'p');
        expect(result.agentThreadIdsByProject, <String, String>{'/repo': 't'});
        expect(result.projectThreadExpansionByProject['/repo'], isTrue);
        final cached = result.cachedThreadsByProject['/repo']!.single;
        expect(cached.id, 't');
        expect(cached.status, AgentThreadRuntimeStatus.active);
        expect(cached.recencyAt!.millisecondsSinceEpoch, 30);
        expect(cached.waitingOnApproval, isTrue);
        expect(cached.waitingOnUserInput, isTrue);
        expect(cached.raw, <String, Object?>{'safe': true});
        expect(result.selectedThreadIdsByProject['/repo'], 't');
        expect(
          result.projectLastOpenedAtByPath['/repo']!.millisecondsSinceEpoch,
          40,
        );
        expect(result.projectHomeActive, isTrue);
        expect(result.workbench.leftSidebarVisible, isFalse);
        expect(result.workbench.agentUsageExpanded, isTrue);
        expect(result.workbench.leftSidebarWidth, 300);
        expect(result.workbench.agentUsageHeightFraction, 0.4);
        expect(result.workbench.selectedAgentUsageProviderId, 'p');
        expect(repository.snapshot, same(result));
        expect(repository.isRestored, isTrue);
        expect(changes, <ProjectSessionSnapshot?>[result]);
      },
    );

    test('publishes a missing snapshot as a successful restore', () async {
      final changes = <ProjectSessionSnapshot?>[];
      createRepository().snapshotChanges.listen(changes.add);

      expect(await repository.restore(), isNull);

      expect(repository.snapshot, isNull);
      expect(repository.isRestored, isTrue);
      expect(changes, <ProjectSessionSnapshot?>[null]);
    });

    test('translates all current-schema decode failures', () async {
      final sources = <ProjectSessionRepositoryFailureCode, String>{
        ProjectSessionRepositoryFailureCode.malformedJson: '{',
        ProjectSessionRepositoryFailureCode.invalidRoot: '[]',
        ProjectSessionRepositoryFailureCode.unsupportedVersion: jsonEncode(
          <String, Object?>{'version': 3},
        ),
        ProjectSessionRepositoryFailureCode.invalidField: jsonEncode(
          <String, Object?>{'version': 4},
        ),
      };
      for (final entry in sources.entries) {
        storage.source = entry.value;
        createRepository();
        await expectFailureAsync(
          repository.restore(),
          ProjectSessionRepositoryOperation.restore,
          entry.key,
        );
        await repository.close();
        storage = FakeProjectSessionStorage();
      }
      createRepository();
    });

    test('translates restore IO and an externally closed store', () async {
      storage.readError = StateError('read');
      createRepository();
      await expectFailureAsync(
        repository.restore(),
        ProjectSessionRepositoryOperation.restore,
        ProjectSessionRepositoryFailureCode.externalFailure,
      );
      await repository.close();

      storage = FakeProjectSessionStorage();
      createRepository();
      await store.close();
      await expectFailureAsync(
        repository.restore(),
        ProjectSessionRepositoryOperation.restore,
        ProjectSessionRepositoryFailureCode.closed,
      );
    });

    test('saves every field before publishing and serializes writes', () async {
      final gate = Completer<void>();
      storage.writeGates.add(gate);
      final changes = <ProjectSessionSnapshot?>[];
      createRepository().snapshotChanges.listen(changes.add);
      final first = sampleSnapshot();
      final second = ProjectSessionSnapshot(
        projectPaths: const <String>['/other'],
      );

      final firstSave = repository.save(first);
      final secondSave = repository.save(second);
      await Future<void>.delayed(Duration.zero);
      expect(storage.writeCount, 1);
      expect(changes, isEmpty);
      gate.complete();
      await firstSave;
      await secondSave;

      expect(storage.writes, hasLength(2));
      final decoded = const SessionSnapshotCodec().decode(
        jsonDecode(storage.writes.first),
      );
      expect(decoded.projectPaths, first.projectPaths);
      expect(decoded.cachedThreadsByProject['/repo']!.single.status, 'active');
      expect(decoded.workbench.leftSidebarWidth, 300);
      expect(changes, <ProjectSessionSnapshot?>[first, second]);
      expect(repository.snapshot, same(second));
      expect(repository.isRestored, isTrue);
    });

    test('does not publish failed saves and translates closed store', () async {
      final changes = <ProjectSessionSnapshot?>[];
      storage.writeError = StateError('write');
      createRepository().snapshotChanges.listen(changes.add);
      await expectFailureAsync(
        repository.save(sampleSnapshot()),
        ProjectSessionRepositoryOperation.save,
        ProjectSessionRepositoryFailureCode.externalFailure,
      );
      expect(changes, isEmpty);
      expect(repository.snapshot, isNull);

      storage.writeError = null;
      await store.close();
      await expectFailureAsync(
        repository.save(sampleSnapshot()),
        ProjectSessionRepositoryOperation.save,
        ProjectSessionRepositoryFailureCode.closed,
      );
    });
  });

  group('thread catalog', () {
    test(
      'lists canonical catalog ids and aggregates stable global pages',
      () async {
        final a = FakeThreadCatalogPort()
          ..pages.addAll(<AgentThreadPage>[
            AgentThreadPage(
              threads: <AgentThreadSummary>[
                thread(id: '2', providerId: 'a', updatedAt: 20),
                thread(id: '1', providerId: 'a', updatedAt: 10),
              ],
              nextCursor: 'a-next',
            ),
            AgentThreadPage(
              threads: <AgentThreadSummary>[
                thread(id: '1', providerId: 'a', updatedAt: 10),
                thread(id: '3', providerId: 'a', updatedAt: 30),
              ],
              nextCursor: null,
            ),
          ]);
        final b = FakeThreadCatalogPort()
          ..pages.add(
            AgentThreadPage(
              threads: <AgentThreadSummary>[
                thread(id: '1', providerId: 'b', updatedAt: 20, recencyAt: 40),
              ],
              nextCursor: null,
            ),
          );
        createRepository(
          catalogs: <String, AgentThreadCatalogPort>{'b': b, 'a': a},
        );

        expect(repository.threadCatalog(), <String>['a', 'b']);
        final first = await repository.threadPage(
          ProjectThreadQuery(
            projectPath: ' /repo ',
            limit: 2,
            archived: true,
            searchTerm: ' title ',
            sourceKinds: const <String>['local'],
          ),
        );

        expect(
          first.threads.map((value) => '${value.providerId}:${value.id}'),
          <String>[
            'b:1',
            'a:3',
          ],
        );
        expect(first.nextCursor, 'agg:2');
        expect(first.failures, isEmpty);
        expect(a.queries, hasLength(2));
        expect(a.queries.first.projectPath, '/repo');
        expect(a.queries.first.cursor, isNull);
        expect(a.queries.last.cursor, 'a-next');
        expect(a.queries.first.archived, isTrue);
        expect(a.queries.first.searchTerm, 'title');
        expect(a.queries.first.sourceKinds, <String>['local']);

        a.pages.addAll(<AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              thread(id: '2', providerId: 'a', updatedAt: 20),
              thread(id: '3', providerId: 'a', updatedAt: 30),
            ],
            nextCursor: null,
          ),
        ]);
        b.pages.add(
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              thread(id: '1', providerId: 'b', updatedAt: 20, recencyAt: 40),
            ],
            nextCursor: null,
          ),
        );
        final second = await repository.threadPage(
          ProjectThreadQuery(
            projectPath: '/repo',
            limit: 2,
            cursor: first.nextCursor,
          ),
        );
        expect(second.threads.single.id, '2');
        expect(second.nextCursor, isNull);
      },
    );

    test(
      'returns deterministic partial external and invalid-data failures',
      () async {
        final external = FakeThreadCatalogPort()
          ..error = StateError('provider');
        final invalid = FakeThreadCatalogPort()
          ..pages.add(
            AgentThreadPage(
              threads: <AgentThreadSummary>[
                thread(id: 'x', providerId: 'wrong'),
              ],
              nextCursor: null,
            ),
          );
        final success = FakeThreadCatalogPort()
          ..pages.add(
            AgentThreadPage(
              threads: <AgentThreadSummary>[
                thread(id: 'ok', providerId: 'success'),
              ],
              nextCursor: null,
            ),
          );
        createRepository(
          catalogs: <String, AgentThreadCatalogPort>{
            'success': success,
            'external': external,
            'invalid': invalid,
          },
        );

        final page = await repository.threadPage(
          ProjectThreadQuery(projectPath: '/repo'),
        );

        expect(page.threads.single.id, 'ok');
        expect(page.failures, <ProjectThreadProviderFailure>[
          const ProjectThreadProviderFailure(
            providerId: 'external',
            code: ProjectThreadProviderFailureCode.externalFailure,
          ),
          const ProjectThreadProviderFailure(
            providerId: 'invalid',
            code: ProjectThreadProviderFailureCode.invalidData,
          ),
        ]);
      },
    );

    test('rejects invalid query and aggregate cursor inputs', () async {
      createRepository();
      for (final query in <ProjectThreadQuery>[
        ProjectThreadQuery(projectPath: ' '),
        ProjectThreadQuery(projectPath: '/repo', limit: 0),
        ProjectThreadQuery(projectPath: '/repo', cursor: 'vendor'),
        ProjectThreadQuery(projectPath: '/repo', cursor: 'agg:nope'),
        ProjectThreadQuery(projectPath: '/repo', cursor: 'agg:-1'),
      ]) {
        await expectFailureAsync(
          repository.threadPage(query),
          ProjectSessionRepositoryOperation.threadPage,
          ProjectSessionRepositoryFailureCode.invalidInput,
        );
      }
      final page = await repository.threadPage(
        ProjectThreadQuery(projectPath: '/repo', cursor: 'agg:0'),
      );
      expect(page.threads, isEmpty);
    });

    test('rejects repeated Provider cursors as invalid Data', () async {
      final port = FakeThreadCatalogPort()
        ..pages.addAll(<AgentThreadPage>[
          AgentThreadPage(
            threads: <AgentThreadSummary>[thread(id: '1', providerId: 'p')],
            nextCursor: 'same',
          ),
          AgentThreadPage(
            threads: <AgentThreadSummary>[thread(id: '2', providerId: 'p')],
            nextCursor: 'same',
          ),
        ]);
      createRepository(catalogs: <String, AgentThreadCatalogPort>{'p': port});

      final page = await repository.threadPage(
        ProjectThreadQuery(projectPath: '/repo'),
      );

      expect(page.threads, isEmpty);
      expect(
        page.failures.single.code,
        ProjectThreadProviderFailureCode.invalidData,
      );
    });

    test('uses Provider id then thread id as recency tie-breakers', () async {
      final a = FakeThreadCatalogPort()
        ..pages.add(
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              thread(id: 'z', providerId: 'a', updatedAt: 10),
              thread(id: 'a', providerId: 'a', updatedAt: 10),
            ],
            nextCursor: null,
          ),
        );
      final b = FakeThreadCatalogPort()
        ..pages.add(
          AgentThreadPage(
            threads: <AgentThreadSummary>[
              thread(id: 'a', providerId: 'b', updatedAt: 10),
            ],
            nextCursor: null,
          ),
        );
      createRepository(
        catalogs: <String, AgentThreadCatalogPort>{'b': b, 'a': a},
      );

      final page = await repository.threadPage(
        ProjectThreadQuery(projectPath: '/repo'),
      );

      expect(
        page.threads.map((value) => '${value.providerId}:${value.id}'),
        <String>['a:a', 'a:z', 'b:a'],
      );
    });
  });

  test('validates catalog identity and closes idempotently', () async {
    expect(
      () => ProjectSessionRepository(
        store: ProjectSessionStore(storage: storage),
        threadCatalogs: <String, AgentThreadCatalogPort>{
          ' ': FakeThreadCatalogPort(),
        },
      ),
      throwsArgumentError,
    );
    createRepository();
    final done = expectLater(repository.snapshotChanges, emitsDone);
    final first = repository.close();
    final second = repository.close();
    expect(identical(first, second), isTrue);
    await first;
    await done;
    expect(storage.closeCount, 1);
    expectFailure(
      repository.restore,
      ProjectSessionRepositoryOperation.restore,
      ProjectSessionRepositoryFailureCode.closed,
    );
    expectFailure(
      () => repository.save(ProjectSessionSnapshot()),
      ProjectSessionRepositoryOperation.save,
      ProjectSessionRepositoryFailureCode.closed,
    );
    expectFailure(
      () => repository.threadPage(ProjectThreadQuery(projectPath: '/repo')),
      ProjectSessionRepositoryOperation.threadPage,
      ProjectSessionRepositoryFailureCode.closed,
    );
  });

  test('translates store close failure after closing the stream', () async {
    storage.closeError = StateError('close');
    createRepository();
    final done = expectLater(repository.snapshotChanges, emitsDone);

    await expectFailureAsync(
      repository.close(),
      ProjectSessionRepositoryOperation.close,
      ProjectSessionRepositoryFailureCode.externalFailure,
    );
    await done;
  });
}

SessionSnapshotResponse sampleResponse() {
  return SessionSnapshotResponse(
    projectPaths: const <String>['/repo'],
    activeProjectPath: '/repo',
    currentFilePath: '/repo/lib/main.dart',
    expandedDirectoryPaths: const <String>{'/repo/lib'},
    selectedTreeKey: 'file:/repo/lib/main.dart',
    activeAgentProviderId: 'p',
    agentThreadIdsByProject: const <String, String>{'/repo': 't'},
    projectThreadExpansionByProject: const <String, bool>{'/repo': true},
    cachedThreadsByProject: <String, List<SessionThreadSummaryResponse>>{
      '/repo': <SessionThreadSummaryResponse>[
        const SessionThreadSummaryResponse(
          id: 't',
          providerId: 'p',
          projectPath: '/repo',
          title: 'Title',
          sessionPath: '/session',
          preview: 'Preview',
          createdAtMilliseconds: 10,
          updatedAtMilliseconds: 20,
          recencyAtMilliseconds: 30,
          status: 'active',
          waitingOnApproval: true,
          waitingOnUserInput: true,
          raw: <String, Object?>{'safe': true},
        ),
      ],
    },
    selectedThreadIdsByProject: const <String, String>{'/repo': 't'},
    projectLastOpenedAtByPath: <String, DateTime>{
      '/repo': DateTime.fromMillisecondsSinceEpoch(40),
    },
    projectHomeActive: true,
    workbench: const SessionWorkbenchResponse(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: 300,
      agentUsageHeightFraction: 0.4,
      selectedAgentUsageProviderId: 'p',
    ),
  );
}

ProjectSessionSnapshot sampleSnapshot() {
  final response = sampleResponse();
  final cached = response.cachedThreadsByProject['/repo']!.single;
  return ProjectSessionSnapshot(
    projectPaths: response.projectPaths,
    activeProjectPath: response.activeProjectPath,
    currentFilePath: response.currentFilePath,
    expandedDirectoryPaths: response.expandedDirectoryPaths,
    selectedTreeKey: response.selectedTreeKey,
    activeAgentProviderId: response.activeAgentProviderId,
    agentThreadIdsByProject: response.agentThreadIdsByProject,
    projectThreadExpansionByProject: response.projectThreadExpansionByProject,
    cachedThreadsByProject: <String, List<AgentThreadSummary>>{
      '/repo': <AgentThreadSummary>[
        AgentThreadSummary(
          id: cached.id,
          providerId: cached.providerId,
          projectPath: cached.projectPath,
          title: cached.title,
          sessionPath: cached.sessionPath,
          preview: cached.preview,
          createdAt: DateTime.fromMillisecondsSinceEpoch(
            cached.createdAtMilliseconds,
          ),
          updatedAt: DateTime.fromMillisecondsSinceEpoch(
            cached.updatedAtMilliseconds,
          ),
          recencyAt: DateTime.fromMillisecondsSinceEpoch(
            cached.recencyAtMilliseconds!,
          ),
          status: AgentThreadRuntimeStatus.active,
          waitingOnApproval: true,
          waitingOnUserInput: true,
          raw: cached.raw,
        ),
      ],
    },
    selectedThreadIdsByProject: response.selectedThreadIdsByProject,
    projectLastOpenedAtByPath: response.projectLastOpenedAtByPath,
    projectHomeActive: response.projectHomeActive,
    workbench: const ProjectWorkbenchSnapshot(
      leftSidebarVisible: false,
      agentUsageExpanded: true,
      leftSidebarWidth: 300,
      agentUsageHeightFraction: 0.4,
      selectedAgentUsageProviderId: 'p',
    ),
  );
}

void expectFailure(
  Object? Function() action,
  ProjectSessionRepositoryOperation operation,
  ProjectSessionRepositoryFailureCode code,
) {
  expect(action, throwsProjectSessionFailure(operation, code));
}

Future<void> expectFailureAsync(
  Future<Object?> future,
  ProjectSessionRepositoryOperation operation,
  ProjectSessionRepositoryFailureCode code,
) async {
  await expectLater(future, throwsProjectSessionFailure(operation, code));
}

Matcher throwsProjectSessionFailure(
  ProjectSessionRepositoryOperation operation,
  ProjectSessionRepositoryFailureCode code,
) {
  return throwsA(
    isA<ProjectSessionRepositoryException>()
        .having((error) => error.failure.operation, 'operation', operation)
        .having((error) => error.failure.code, 'code', code),
  );
}

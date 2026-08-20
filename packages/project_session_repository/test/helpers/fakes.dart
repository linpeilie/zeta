import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:project_session_client/project_session_client.dart';

final class FakeProjectSessionStorage implements ProjectSessionDocumentStorage {
  String? source;
  Object? readError;
  Object? writeError;
  Object? closeError;
  final List<String> writes = <String>[];
  final List<Completer<void>> writeGates = <Completer<void>>[];
  int readCount = 0;
  int writeCount = 0;
  int closeCount = 0;

  @override
  Future<String?> read() async {
    readCount += 1;
    final error = readError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    return source;
  }

  @override
  Future<void> write(String contents) async {
    final invocation = writeCount++;
    if (invocation < writeGates.length) {
      await writeGates[invocation].future;
    }
    final error = writeError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
    writes.add(contents);
  }

  @override
  Future<void> close() async {
    closeCount += 1;
    final error = closeError;
    if (error != null) {
      Error.throwWithStackTrace(error, StackTrace.current);
    }
  }
}

final class FakeThreadCatalogPort implements AgentThreadCatalogPort {
  final List<AgentThreadPage> pages = <AgentThreadPage>[];
  Object? error;
  final List<AgentThreadListQuery> queries = <AgentThreadListQuery>[];

  @override
  Future<AgentThreadPage> listThreads({
    required AgentThreadListQuery query,
  }) async {
    queries.add(query);
    final failure = error;
    if (failure != null) {
      Error.throwWithStackTrace(failure, StackTrace.current);
    }
    if (pages.isEmpty) {
      return AgentThreadPage(
        threads: const <AgentThreadSummary>[],
        nextCursor: null,
      );
    }
    return pages.removeAt(0);
  }

  @override
  Future<AgentThreadHistorySnapshot> readThreadHistory({
    required String threadId,
    String? sessionPath,
    String? projectPath,
  }) {
    throw UnimplementedError();
  }
}

AgentThreadSummary thread({
  required String id,
  required String providerId,
  String projectPath = '/repo',
  int updatedAt = 1,
  int? recencyAt,
  AgentThreadRuntimeStatus status = AgentThreadRuntimeStatus.idle,
}) {
  return AgentThreadSummary(
    id: id,
    providerId: providerId,
    projectPath: projectPath,
    title: 'Title $id',
    sessionPath: '/sessions/$id',
    preview: 'Preview $id',
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    updatedAt: DateTime.fromMillisecondsSinceEpoch(updatedAt),
    recencyAt: recencyAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(recencyAt),
    status: status,
    waitingOnApproval: status == AgentThreadRuntimeStatus.active,
    raw: <String, Object?>{'id': id},
  );
}

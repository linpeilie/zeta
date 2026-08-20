import 'dart:async';

// Package-internal persistence collaborator shared with the repository library.
// ignore_for_file: prefer_initializing_formals, public_member_api_docs

import 'package:agent_config_client/agent_config_client.dart';
import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:clock/clock.dart';
import 'package:zeta_logging/zeta_logging.dart';

const Duration turnContextTimeMatchWindow = Duration(seconds: 5);

/// Overlays allowlisted local turn metadata onto a provider history snapshot.
AgentThreadHistorySnapshot overlayTurnContext(
  AgentThreadHistorySnapshot snapshot,
  AgentThreadTurnContext? local,
) {
  if (local == null || local.turns.isEmpty) {
    return snapshot;
  }
  final matches = _matchTurns(snapshot.turns, local.turns);
  final turns = <AgentHistoryTurn>[
    for (var index = 0; index < snapshot.turns.length; index += 1)
      _overlayTurn(snapshot.turns[index], matches[index]),
  ];
  final currentId = snapshot.currentTurn?.id;
  AgentHistoryTurn? current;
  if (currentId != null) {
    for (final turn in turns) {
      if (turn.id == currentId) {
        current = turn;
        break;
      }
    }
  }
  return AgentThreadHistorySnapshot(
    threadId: snapshot.threadId,
    turns: turns,
    currentTurn: current,
    raw: snapshot.raw,
  );
}

List<AgentTurnContextRecord?> _matchTurns(
  List<AgentHistoryTurn> history,
  List<AgentTurnContextRecord> local,
) {
  final matches = List<AgentTurnContextRecord?>.filled(history.length, null);
  final claimedLocalIndexes = <int>{};
  for (var historyIndex = 0; historyIndex < history.length; historyIndex += 1) {
    for (var localIndex = 0; localIndex < local.length; localIndex += 1) {
      if (!claimedLocalIndexes.contains(localIndex) &&
          local[localIndex].turnId == history[historyIndex].id) {
        matches[historyIndex] = local[localIndex];
        claimedLocalIndexes.add(localIndex);
        break;
      }
    }
  }

  final candidates = <_TimeCandidate>[];
  for (var historyIndex = 0; historyIndex < history.length; historyIndex += 1) {
    if (matches[historyIndex] != null) {
      continue;
    }
    final historyTime =
        history[historyIndex].startedAt ?? history[historyIndex].completedAt;
    if (historyTime == null) {
      continue;
    }
    for (var localIndex = 0; localIndex < local.length; localIndex += 1) {
      if (claimedLocalIndexes.contains(localIndex)) {
        continue;
      }
      final localTime =
          local[localIndex].startedAt ?? local[localIndex].completedAt;
      if (localTime == null) {
        continue;
      }
      final delta = historyTime.difference(localTime).abs();
      if (delta <= turnContextTimeMatchWindow) {
        candidates.add(
          _TimeCandidate(
            historyIndex: historyIndex,
            localIndex: localIndex,
            delta: delta,
          ),
        );
      }
    }
  }

  final bestHistory = <int, _TimeCandidate>{};
  final ambiguousHistory = <int>{};
  final bestLocal = <int, _TimeCandidate>{};
  final ambiguousLocal = <int>{};
  for (final candidate in candidates) {
    _selectBest(
      candidate: candidate,
      index: candidate.historyIndex,
      best: bestHistory,
      ambiguous: ambiguousHistory,
    );
    _selectBest(
      candidate: candidate,
      index: candidate.localIndex,
      best: bestLocal,
      ambiguous: ambiguousLocal,
    );
  }
  for (final entry in bestHistory.entries) {
    final candidate = entry.value;
    if (ambiguousHistory.contains(entry.key) ||
        ambiguousLocal.contains(candidate.localIndex) ||
        bestLocal[candidate.localIndex]?.historyIndex != entry.key) {
      continue;
    }
    matches[entry.key] = local[candidate.localIndex];
  }
  return matches;
}

void _selectBest({
  required _TimeCandidate candidate,
  required int index,
  required Map<int, _TimeCandidate> best,
  required Set<int> ambiguous,
}) {
  final current = best[index];
  if (current == null || candidate.delta < current.delta) {
    best[index] = candidate;
    ambiguous.remove(index);
  } else if (candidate.delta == current.delta &&
      (candidate.historyIndex != current.historyIndex ||
          candidate.localIndex != current.localIndex)) {
    ambiguous.add(index);
  }
}

final class _TimeCandidate {
  const _TimeCandidate({
    required this.historyIndex,
    required this.localIndex,
    required this.delta,
  });

  final int historyIndex;
  final int localIndex;
  final Duration delta;
}

AgentHistoryTurn _overlayTurn(
  AgentHistoryTurn turn,
  AgentTurnContextRecord? local,
) {
  if (local == null) {
    return turn;
  }
  final localEffort = _nonEmpty(local.reasoningEffort);
  return AgentHistoryTurn(
    id: turn.id,
    entries: turn.entries,
    status: local.status ?? turn.status,
    startedAt: local.startedAt ?? turn.startedAt,
    completedAt: local.completedAt ?? turn.completedAt,
    duration: turn.duration,
    timeToFirstToken: turn.timeToFirstToken,
    cwd: turn.cwd,
    modelId: _nonEmpty(local.modelId) ?? turn.modelId,
    reasoningEffort: localEffort == null
        ? turn.reasoningEffort
        : AgentHistoryReasoningEffort.explicit(localEffort),
    serviceTierId: _nonEmpty(local.serviceTierId) ?? turn.serviceTierId,
    explicitFast: local.explicitFast ?? turn.explicitFast,
    modelContextWindow: turn.modelContextWindow,
    collaborationMode: turn.collaborationMode,
    tokenUsage: turn.tokenUsage,
    tokenUsageIsSessionCumulative: turn.tokenUsageIsSessionCumulative,
    errorMessage: turn.errorMessage,
    errorCode: turn.errorCode,
    raw: turn.raw,
  );
}

String? _nonEmpty(String? value) {
  final trimmed = value?.trim();
  return trimmed == null || trimmed.isEmpty ? null : trimmed;
}

/// Serialized, best-effort persistence for allowlisted live turn metadata.
final class TurnContextRecorder {
  TurnContextRecorder({
    required AgentTurnContextStore store,
    required AppLogger logger,
    Clock clock = const Clock(),
  }) : _store = store,
       _logger = logger,
       _clock = clock;

  final AgentTurnContextStore _store;
  final AppLogger _logger;
  final Clock _clock;
  final Map<String, Future<void>> _tails = <String, Future<void>>{};

  void recordStarted({
    required String providerId,
    required AgentTurnStartedEvent event,
  }) {
    unawaited(
      _enqueue(
        providerId: providerId,
        threadId: event.turn.sessionId,
        incoming: AgentTurnContextRecord(
          turnId: event.turn.id,
          modelId: event.modelId,
          reasoningEffort: event.reasoningEffort,
          serviceTierId: event.serviceTierId,
          explicitFast: event.explicitFast,
          startedAt: event.startedAt,
        ),
        fillStartedAt: true,
      ),
    );
  }

  void recordCompleted({
    required String providerId,
    required AgentTurnCompletedEvent event,
  }) {
    unawaited(
      _enqueue(
        providerId: providerId,
        threadId: event.sessionId,
        incoming: AgentTurnContextRecord(
          turnId: event.turnId,
          completedAt: event.completedAt,
          status: event.status,
        ),
        fillCompletedAt: true,
      ),
    );
  }

  Future<void> _enqueue({
    required String providerId,
    required String threadId,
    required AgentTurnContextRecord incoming,
    bool fillStartedAt = false,
    bool fillCompletedAt = false,
  }) {
    final normalizedProvider = providerId.trim();
    final normalizedThread = threadId.trim();
    final normalizedTurn = incoming.turnId.trim();
    if (normalizedProvider.isEmpty ||
        normalizedThread.isEmpty ||
        normalizedTurn.isEmpty) {
      return Future<void>.value();
    }
    final key = '$normalizedProvider\u0000$normalizedThread';
    final operation = (_tails[key] ?? Future<void>.value()).then((_) async {
      try {
        final existing =
            await _store.load(
              providerId: normalizedProvider,
              threadId: normalizedThread,
            ) ??
            AgentThreadTurnContext(
              providerId: normalizedProvider,
              threadId: normalizedThread,
            );
        var next = existing.upsertTurn(
          AgentTurnContextRecord(
            turnId: normalizedTurn,
            modelId: incoming.modelId,
            reasoningEffort: incoming.reasoningEffort,
            serviceTierId: incoming.serviceTierId,
            explicitFast: incoming.explicitFast,
            startedAt: incoming.startedAt,
            completedAt: incoming.completedAt,
            status: incoming.status,
          ),
        );
        final merged = next.turnById(normalizedTurn);
        if (merged != null &&
            ((fillStartedAt && merged.startedAt == null) ||
                (fillCompletedAt && merged.completedAt == null))) {
          next = next.upsertTurn(
            AgentTurnContextRecord(
              turnId: normalizedTurn,
              startedAt: fillStartedAt && merged.startedAt == null
                  ? _clock.now()
                  : null,
              completedAt: fillCompletedAt && merged.completedAt == null
                  ? _clock.now()
                  : null,
            ),
          );
        }
        await _store.save(next);
      } on Object catch (error, stackTrace) {
        _logger.w(
          'Turn-context persistence failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    });
    _tails[key] = operation.catchError((Object _) {});
    return operation;
  }

  Future<void> flush() => Future.wait(_tails.values);
}

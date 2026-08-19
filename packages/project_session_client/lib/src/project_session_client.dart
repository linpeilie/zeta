import 'dart:async';
import 'dart:convert';

import 'package:project_session_client/src/project_session_document_storage.dart';
import 'package:project_session_client/src/project_session_exceptions.dart';
import 'package:project_session_client/src/session_snapshot_codec.dart';
import 'package:project_session_client/src/session_snapshot_response.dart';

/// Current-schema IDE session persistence with cancellable debounced writes.
final class ProjectSessionStore {
  /// Creates a project session store.
  ProjectSessionStore({
    required this.storage,
    this.writeDelay = const Duration(milliseconds: 250),
    this.codec = const SessionSnapshotCodec(),
  });

  /// External text storage.
  final ProjectSessionDocumentStorage storage;

  /// Delay used to coalesce scheduled writes.
  final Duration writeDelay;

  /// Current-schema snapshot codec.
  final SessionSnapshotCodec codec;

  Timer? _writeTimer;
  SessionSnapshotResponse? _scheduledSnapshot;
  Future<void> _writeTail = Future<void>.value();
  Object? _backgroundFailure;
  StackTrace? _backgroundFailureStackTrace;
  bool _isClosed = false;

  /// Loads the current snapshot, or returns `null` for a missing/blank file.
  Future<SessionSnapshotResponse?> load() async {
    _ensureOpen();
    final source = await storage.read();
    if (source == null || source.trim().isEmpty) {
      return null;
    }

    Object? raw;
    try {
      raw = jsonDecode(source);
    } on FormatException {
      throw const ProjectSessionDecodeException(
        code: ProjectSessionDecodeFailureCode.malformedJson,
      );
    }
    return codec.decode(raw);
  }

  /// Immediately queues [snapshot], replacing any not-yet-started debounce.
  Future<void> save(SessionSnapshotResponse snapshot) {
    _ensureOpen();
    cancelScheduledSave();
    return _queueWrite(snapshot);
  }

  /// Schedules [snapshot], replacing the previous not-yet-started write.
  void scheduleSave(SessionSnapshotResponse snapshot) {
    _ensureOpen();
    cancelScheduledSave();
    _scheduledSnapshot = snapshot;
    _writeTimer = Timer(writeDelay, _startScheduledWrite);
  }

  /// Cancels a write that is still waiting for its debounce timer.
  ///
  /// Returns whether a pending write was cancelled. An already-started atomic
  /// write is deliberately not interrupted.
  bool cancelScheduledSave() {
    final hadScheduledWrite = _scheduledSnapshot != null;
    _writeTimer?.cancel();
    _writeTimer = null;
    _scheduledSnapshot = null;
    return hadScheduledWrite;
  }

  /// Flushes the latest scheduled snapshot and all started writes, then closes.
  Future<void> close() async {
    if (_isClosed) {
      return;
    }
    _isClosed = true;

    _writeTimer?.cancel();
    _writeTimer = null;
    final snapshot = _scheduledSnapshot;
    _scheduledSnapshot = null;
    Object? flushFailure;
    StackTrace? flushFailureStackTrace;
    if (snapshot != null) {
      try {
        await _queueWrite(snapshot);
      } on Object catch (error, stackTrace) {
        flushFailure = error;
        flushFailureStackTrace = stackTrace;
      }
    }

    await _writeTail;
    Object? closeFailure;
    StackTrace? closeFailureStackTrace;
    try {
      await storage.close();
    } on Object catch (error, stackTrace) {
      closeFailure = error;
      closeFailureStackTrace = stackTrace;
    }

    if (_backgroundFailure case final failure?) {
      Error.throwWithStackTrace(
        failure,
        _backgroundFailureStackTrace ?? StackTrace.current,
      );
    }
    if (flushFailure != null) {
      Error.throwWithStackTrace(flushFailure, flushFailureStackTrace!);
    }
    if (closeFailure != null) {
      Error.throwWithStackTrace(closeFailure, closeFailureStackTrace!);
    }
  }

  void _startScheduledWrite() {
    _writeTimer = null;
    final snapshot = _scheduledSnapshot;
    _scheduledSnapshot = null;
    if (snapshot == null) {
      return;
    }
    unawaited(_captureBackgroundFailure(_queueWrite(snapshot)));
  }

  Future<void> _captureBackgroundFailure(Future<void> write) async {
    try {
      await write;
    } on Object catch (error, stackTrace) {
      _backgroundFailure ??= error;
      _backgroundFailureStackTrace ??= stackTrace;
    }
  }

  Future<void> _queueWrite(SessionSnapshotResponse snapshot) {
    final encoded = jsonEncode(codec.encode(snapshot));
    final operation = _writeTail.then((_) => storage.write(encoded));
    _writeTail = operation.then<void>(
      (_) {},
      onError: (Object _, StackTrace _) {},
    );
    return operation;
  }

  void _ensureOpen() {
    if (_isClosed) {
      throw const ProjectSessionClosedException();
    }
  }
}

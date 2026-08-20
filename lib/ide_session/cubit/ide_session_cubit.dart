import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:project_session_repository/project_session_repository.dart';
import 'package:zeta/ide_session/cubit/ide_session_state.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class IdeSessionCubit extends Cubit<IdeSessionState> {
  IdeSessionCubit({
    required ProjectSessionRepository projectSessionRepository,
  }) : _projectSessionRepository = projectSessionRepository,
       super(const IdeSessionState()) {
    _snapshotSubscription = _projectSessionRepository.snapshotChanges.listen(
      _onSnapshot,
    );
  }

  final ProjectSessionRepository _projectSessionRepository;
  late final StreamSubscription<ProjectSessionSnapshot?> _snapshotSubscription;
  Future<void> _writeQueue = Future<void>.value();

  Future<void> restore() async {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        status: IdeSessionStatus.restoring,
        clearFailure: true,
      ),
    );
    try {
      final snapshot = await _projectSessionRepository.restore();
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: IdeSessionStatus.ready,
          snapshot: snapshot,
          initialRoute: _routeFrom(snapshot),
          clearSnapshot: snapshot == null,
          clearFailure: true,
        ),
      );
    } on ProjectSessionRepositoryException catch (error) {
      if (isClosed) {
        return;
      }
      emit(
        state.copyWith(
          status: IdeSessionStatus.failure,
          failure: error.failure,
        ),
      );
    }
  }

  Future<void> save(ProjectSessionSnapshot snapshot) {
    return _enqueue(() async {
      if (isClosed) {
        return;
      }
      try {
        await _projectSessionRepository.save(snapshot);
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            status: IdeSessionStatus.ready,
            snapshot: snapshot,
            initialRoute: _routeFrom(snapshot),
            clearFailure: true,
          ),
        );
      } on ProjectSessionRepositoryException catch (error) {
        if (isClosed) {
          return;
        }
        emit(
          state.copyWith(
            status: IdeSessionStatus.failure,
            failure: error.failure,
          ),
        );
      }
    });
  }

  Future<void> flush() {
    final snapshot = state.snapshot;
    if (snapshot == null) {
      return Future<void>.value();
    }
    return save(snapshot);
  }

  Future<void> _enqueue(Future<void> Function() action) {
    final completer = Completer<void>();
    _writeQueue = _writeQueue.then((_) async {
      try {
        await action();
        completer.complete();
      } on Object catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  void _onSnapshot(ProjectSessionSnapshot? snapshot) {
    if (isClosed) {
      return;
    }
    emit(
      state.copyWith(
        status: IdeSessionStatus.ready,
        snapshot: snapshot,
        initialRoute: _routeFrom(snapshot),
        clearSnapshot: snapshot == null,
      ),
    );
  }

  IdeSessionInitialRoute _routeFrom(ProjectSessionSnapshot? snapshot) {
    if (snapshot == null) {
      return const IdeSessionInitialRoute();
    }
    final projectPath = snapshot.activeProjectPath;
    return IdeSessionInitialRoute(
      projectPath: projectPath,
      filePath: snapshot.currentFilePath,
      threadId: projectPath == null
          ? null
          : snapshot.selectedThreadIdsByProject[projectPath] ??
                snapshot.agentThreadIdsByProject[projectPath],
      projectHomeActive: snapshot.projectHomeActive,
    );
  }

  @override
  Future<void> close() async {
    await _snapshotSubscription.cancel();
    return super.close();
  }
}

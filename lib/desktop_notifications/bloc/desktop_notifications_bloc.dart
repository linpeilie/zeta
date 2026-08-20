import 'dart:async';

import 'package:agent_provider_contracts/agent_provider_contracts.dart';
import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:settings_repository/settings_repository.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_event.dart';
import 'package:zeta/desktop_notifications/bloc/desktop_notifications_state.dart';
import 'package:zeta/l10n/desktop_notification_copy_resolver.dart';

// Named public constructor parameters initialize private fields.
// ignore_for_file: prefer_initializing_formals

class DesktopNotificationsBloc
    extends Bloc<DesktopNotificationsEvent, DesktopNotificationsState> {
  DesktopNotificationsBloc({
    required SettingsRepository settingsRepository,
    required DesktopNotificationsRepository notificationsRepository,
    required DesktopNotificationCopyResolver copyResolver,
  }) : _settingsRepository = settingsRepository,
       _notificationsRepository = notificationsRepository,
       _copyResolver = copyResolver,
       super(const DesktopNotificationsState()) {
    on<DesktopNotificationsSubscriptionRequested>(
      _onSubscriptionRequested,
      transformer: restartable(),
    );
    on<DesktopNotificationsSettingsChanged>(
      _onSettingsChanged,
      transformer: sequential(),
    );
    on<DesktopNotificationsAttentionReceived>(
      _onAttentionReceived,
      transformer: sequential(),
    );
    on<DesktopNotificationsVisibilityUpdated>(
      _onVisibilityUpdated,
      transformer: sequential(),
    );
    on<DesktopNotificationsThreadMarkedRead>(
      _onThreadMarkedRead,
      transformer: sequential(),
    );
    on<DesktopNotificationsActivationRequested>(
      _onActivationRequested,
      transformer: sequential(),
    );
  }

  final SettingsRepository _settingsRepository;
  final DesktopNotificationsRepository _notificationsRepository;
  final DesktopNotificationCopyResolver _copyResolver;
  StreamSubscription<SettingsSnapshot>? _settingsSubscription;

  Future<void> _onSubscriptionRequested(
    DesktopNotificationsSubscriptionRequested event,
    Emitter<DesktopNotificationsState> emit,
  ) async {
    await _settingsSubscription?.cancel();
    try {
      await _settingsRepository.ready;
    } on SettingsRepositoryException {
      emit(
        state.copyWith(
          status: DesktopNotificationsStatus.failure,
          failure: DesktopNotificationOperation.notify,
        ),
      );
      return;
    }
    final notifications = _settingsRepository.settings.general.notifications;
    emit(
      state.copyWith(
        status: DesktopNotificationsStatus.ready,
        notifications: notifications,
        clearFailure: true,
      ),
    );
    _settingsSubscription = _settingsRepository.settingsChanges.listen((
      snapshot,
    ) {
      add(DesktopNotificationsSettingsChanged(snapshot.general.notifications));
    });
  }

  Future<void> _onSettingsChanged(
    DesktopNotificationsSettingsChanged event,
    Emitter<DesktopNotificationsState> emit,
  ) async {
    final unread = Map<String, AgentWorkspaceAttention>.from(state.unread)
      ..removeWhere(
        (_, attention) =>
            !_isEnabled(attention.signal.kind, event.notifications),
      );
    emit(
      state.copyWith(
        status: DesktopNotificationsStatus.ready,
        notifications: event.notifications,
        unread: unread,
        clearFailure: true,
      ),
    );
    await _syncIndicator(emit, requestAttention: false);
  }

  Future<void> _onAttentionReceived(
    DesktopNotificationsAttentionReceived event,
    Emitter<DesktopNotificationsState> emit,
  ) async {
    final attention = event.attention;
    if (attention.signal.phase == AgentAttentionPhase.resolved) {
      final unread = Map<String, AgentWorkspaceAttention>.from(state.unread)
        ..remove(attention.identity);
      emit(state.copyWith(unread: unread, clearFailure: true));
      await _syncIndicator(emit, requestAttention: false);
      return;
    }
    if (!_isEnabled(attention.signal.kind, state.notifications) ||
        state.visibility.shows(attention) ||
        state.unread.containsKey(attention.identity)) {
      return;
    }
    final wasEmpty = state.unread.isEmpty;
    final unread = Map<String, AgentWorkspaceAttention>.from(state.unread)
      ..[attention.identity] = attention;
    emit(state.copyWith(unread: unread, clearFailure: true));
    await _syncIndicator(emit, requestAttention: wasEmpty);
    final copy = _copyResolver.resolve(attention);
    try {
      await _notificationsRepository.notify(
        NotificationRequest(
          title: copy.title,
          body: copy.body,
          tag: copy.tag,
        ),
      );
    } on DesktopNotificationException catch (error) {
      emit(
        state.copyWith(
          status: DesktopNotificationsStatus.failure,
          failure: error.operation,
        ),
      );
    }
  }

  Future<void> _onVisibilityUpdated(
    DesktopNotificationsVisibilityUpdated event,
    Emitter<DesktopNotificationsState> emit,
  ) async {
    emit(state.copyWith(visibility: event.visibility, clearFailure: true));
    final providerId = event.visibility.providerId;
    final threadId = event.visibility.threadId;
    if (event.visibility.windowFocused &&
        event.visibility.agentCanvasVisible &&
        providerId != null &&
        threadId != null) {
      await _removeThread(emit, providerId: providerId, threadId: threadId);
    }
  }

  Future<void> _onThreadMarkedRead(
    DesktopNotificationsThreadMarkedRead event,
    Emitter<DesktopNotificationsState> emit,
  ) {
    return _removeThread(
      emit,
      providerId: event.providerId,
      threadId: event.threadId,
    );
  }

  Future<void> _onActivationRequested(
    DesktopNotificationsActivationRequested event,
    Emitter<DesktopNotificationsState> emit,
  ) async {
    emit(
      state.copyWith(
        activation: DesktopNotificationsActivation(
          providerId: event.providerId,
          threadId: event.threadId,
        ),
        clearFailure: true,
      ),
    );
    await _removeThread(
      emit,
      providerId: event.providerId,
      threadId: event.threadId,
    );
    emit(state.copyWith(clearActivation: true));
  }

  Future<void> _removeThread(
    Emitter<DesktopNotificationsState> emit, {
    required String providerId,
    required String threadId,
  }) async {
    final unread = Map<String, AgentWorkspaceAttention>.from(state.unread)
      ..removeWhere(
        (_, attention) =>
            attention.providerId == providerId &&
            attention.threadId == threadId,
      );
    if (unread.length == state.unread.length) {
      return;
    }
    emit(state.copyWith(unread: unread));
    await _syncIndicator(emit, requestAttention: false);
  }

  Future<void> _syncIndicator(
    Emitter<DesktopNotificationsState> emit, {
    required bool requestAttention,
  }) async {
    try {
      await _notificationsRepository.setBadge(state.badgeCount);
      if (requestAttention && state.unread.isNotEmpty) {
        await _notificationsRepository.requestAttention();
      }
    } on DesktopNotificationException catch (error) {
      emit(
        state.copyWith(
          status: DesktopNotificationsStatus.failure,
          failure: error.operation,
        ),
      );
    }
  }

  bool _isEnabled(
    AgentAttentionKind kind,
    AgentNotificationSettings settings,
  ) {
    if (!settings.enabled) {
      return false;
    }
    return switch (kind) {
      AgentAttentionKind.turnCompleted ||
      AgentAttentionKind.turnFailed ||
      AgentAttentionKind.turnInterrupted => settings.turnTerminalEnabled,
      AgentAttentionKind.permissionRequired ||
      AgentAttentionKind.questionRequired ||
      AgentAttentionKind.planApprovalRequired ||
      AgentAttentionKind.planExecutionRequired =>
        settings.actionRequiredEnabled,
    };
  }

  @override
  Future<void> close() async {
    await _settingsSubscription?.cancel();
    return super.close();
  }
}

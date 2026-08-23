import 'dart:async';

import 'package:zeta_foundation/zeta_foundation.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_store.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/data/desktop_notification_payload_codec.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

/// target activator 在 MainApp 创建、IdeHome 首帧前绑定。
final class DesktopAttentionTargetActivatorRelay {
  DesktopAttentionTargetActivator? _activator;

  void bind(DesktopAttentionTargetActivator activator) {
    if (_activator != null && !identical(_activator, activator)) {
      throw StateError('Desktop attention target activator is already bound');
    }
    _activator = activator;
  }

  void unbind(DesktopAttentionTargetActivator activator) {
    if (identical(_activator, activator)) {
      _activator = null;
    }
  }

  Future<bool> call(String providerId, String threadId) async {
    final activator = _activator;
    return activator == null ? false : activator(providerId, threadId);
  }
}

/// Desktop Attention 的 app 组合：store 是唯一 owner，runner 独占副作用端口。
final class DesktopAttentionSliceComposition {
  DesktopAttentionSliceComposition._({
    required this.store,
    required this._runner,
  });

  factory DesktopAttentionSliceComposition.create({
    required DesktopNotificationService notificationService,
    required DesktopAttentionIndicator indicator,
    required AgentNotificationSettingsSource notificationSettingsSource,
    required DesktopAttentionTargetActivator activateTarget,
    required DesktopAttentionTextCatalog textCatalog,
  }) {
    late final DesktopAttentionSliceStore store;
    final runner = _DesktopAttentionSliceRunner(
      notificationService: notificationService,
      indicator: indicator,
      notificationSettingsSource: notificationSettingsSource,
      activateTarget: activateTarget,
      textCatalog: textCatalog,
      store: () => store,
    );
    store = DesktopAttentionSliceStore(effectRunner: runner);
    return DesktopAttentionSliceComposition._(store: store, runner: runner);
  }

  final DesktopAttentionSliceStore store;
  final _DesktopAttentionSliceRunner _runner;

  Future<void> initialize() => _runner.initialize();

  void dispose() {
    _runner.dispose();
    store.close();
  }
}

final class _DesktopAttentionSliceRunner
    implements DesktopAttentionSliceEffectRunner {
  _DesktopAttentionSliceRunner({
    required this.notificationService,
    required this.indicator,
    required this.notificationSettingsSource,
    required this.activateTarget,
    required this.textCatalog,
    required this._store,
  });

  static final _log = zetaLoggerFor('zeta.desktop_attention');

  final DesktopNotificationService notificationService;
  final DesktopAttentionIndicator indicator;
  final AgentNotificationSettingsSource notificationSettingsSource;
  final DesktopAttentionTargetActivator activateTarget;
  final DesktopAttentionTextCatalog textCatalog;
  final DesktopAttentionSliceStore Function() _store;

  bool _initialized = false;
  bool _disposed = false;
  void Function()? _unsubscribeSettings;

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    final settings = await notificationSettingsSource.load();
    _unsubscribeSettings = notificationSettingsSource.addListener(() {
      if (!_disposed) {
        unawaited(
          _store().settingsChanged(notificationSettingsSource.notifications),
        );
      }
    });

    String? initialPayload;
    try {
      initialPayload = await notificationService.initialize(
        onActivate: (payload) {
          unawaited(_store().handleActivation(payload));
        },
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not initialize desktop notifications',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _store().initialized(settings);
    await _store().handleActivation(initialPayload);
  }

  @override
  Future<void> run(DesktopAttentionSliceEffect effect) async {
    if (_disposed) {
      return;
    }
    switch (effect) {
      case DesktopAttentionRequestPermissionsEffect():
        await _requestPermissions();
      case DesktopAttentionShowNotificationEffect(:final unread):
        await _show(unread);
      case DesktopAttentionCancelNotificationsEffect(:final notificationIds):
        await _cancelAll(notificationIds);
      case DesktopAttentionSyncIndicatorEffect(
        :final unreadCount,
        :final requestAttention,
      ):
        await _syncIndicator(unreadCount, requestAttention: requestAttention);
      case DesktopAttentionActivateNotificationEffect(:final payload):
        await _activate(payload);
    }
  }

  Future<void> _show(DesktopUnreadAttention unread) async {
    final attention = unread.attention;
    try {
      await notificationService.show(
        DesktopNotificationRequest(
          id: unread.notificationId,
          title: textCatalog.titleFor(attention.signal.kind),
          body: _safeBody(attention),
          payload: DesktopNotificationPayloadCodec.encode(
            DesktopNotificationPayload(
              providerId: attention.providerId,
              threadId: attention.threadId,
              identity: attention.identity,
            ),
          ),
        ),
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not show desktop notification',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _activate(String rawPayload) async {
    final payload = DesktopNotificationPayloadCodec.tryDecode(rawPayload);
    if (payload == null) {
      return;
    }
    try {
      final activated = await activateTarget(
        payload.providerId,
        payload.threadId,
      );
      if (activated) {
        await _store().markThreadRead(payload.providerId, payload.threadId);
      } else if (payload.identity case final identity?) {
        await _store().removeIdentity(identity);
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not handle notification activation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _requestPermissions() async {
    try {
      await notificationService.requestPermissions();
    } catch (error, stackTrace) {
      _log.w(
        'Could not request desktop notification permissions',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  Future<void> _cancelAll(Iterable<int> notificationIds) async {
    for (final id in notificationIds) {
      try {
        await notificationService.cancel(id);
      } catch (error, stackTrace) {
        _log.t(
          'Could not cancel desktop notification',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _syncIndicator(
    int unreadCount, {
    required bool requestAttention,
  }) async {
    try {
      await indicator.setUnreadCount(unreadCount);
      if (requestAttention && unreadCount > 0) {
        await indicator.requestAttention();
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not update desktop attention indicator',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  String _safeBody(AgentWorkspaceAttention attention) {
    final normalized = attention.projectPath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    final projectName = segments.isEmpty
        ? textCatalog.currentProjectName
        : segments.last;
    return textCatalog.sessionBody(projectName);
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _unsubscribeSettings?.call();
    _unsubscribeSettings = null;
    notificationService.dispose();
  }
}

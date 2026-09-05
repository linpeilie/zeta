import 'dart:async';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_effect.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_notifier.dart';
import 'package:zeta/src/features/desktop_notifications/application/desktop_attention_slice_state.dart';
import 'package:zeta/src/features/desktop_notifications/data/desktop_notification_payload_codec.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_text_catalog.dart';
import 'package:zeta/src/features/settings/application/agent_notification_settings_source.dart';

/// Desktop Attention MVI 的 app 组合层 effect runner。
///
/// notifier 由 [DesktopAttentionSliceEffectRunnerFactory] 直接传进来，因此这里既
/// 不需要延迟绑定的空壳转发器，也不需要反向读 provider（工程规范 §3.0）。
final class DesktopAttentionSliceRunner
    implements DesktopAttentionSliceEffectRunner {
  DesktopAttentionSliceRunner(
    this._notifier, {
    required this.notificationService,
    required this.indicator,
    required this.notificationSettingsSource,
    required this.activateTarget,
    required this.textCatalog,
  });

  static final _log = zetaLoggerFor('zeta.desktop_attention');

  final DesktopAttentionSliceNotifier _notifier;
  final DesktopNotificationService notificationService;
  final DesktopAttentionIndicator indicator;
  final AgentNotificationSettingsSource notificationSettingsSource;
  final DesktopAttentionTargetActivator activateTarget;
  final DesktopAttentionTextCatalog textCatalog;

  bool _initialized = false;
  bool _closed = false;
  void Function()? _unsubscribeSettings;

  @override
  Future<void> initialize() async {
    if (_initialized || _closed) {
      return;
    }
    _initialized = true;
    final settings = await notificationSettingsSource.load();
    _unsubscribeSettings = notificationSettingsSource.addListener(() {
      if (!_closed) {
        unawaited(
          _notifier.settingsChanged(notificationSettingsSource.notifications),
        );
      }
    });

    String? initialPayload;
    try {
      initialPayload = await notificationService.initialize(
        onActivate: (payload) {
          unawaited(_notifier.handleActivation(payload));
        },
      );
    } catch (error, stackTrace) {
      _log.w(
        'Could not initialize desktop notifications',
        error: error,
        stackTrace: stackTrace,
      );
    }
    await _notifier.initialized(settings);
    await _notifier.handleActivation(initialPayload);
  }

  @override
  Future<void> run(DesktopAttentionSliceEffect effect) async {
    if (_closed) {
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
        await _notifier.markThreadRead(payload.providerId, payload.threadId);
      } else if (payload.identity case final identity?) {
        await _notifier.removeIdentity(identity);
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

  @override
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    _unsubscribeSettings?.call();
    _unsubscribeSettings = null;
    notificationService.dispose();
  }
}

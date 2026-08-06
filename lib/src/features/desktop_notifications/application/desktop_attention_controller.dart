import 'dart:async';
import 'dart:convert';

import 'package:zeta/src/core/logging/app_logging.dart';
import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/application/general_settings_controller.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// 合并 Agent 提醒、应用可见性、系统通知和任务栏未读状态。
final class DesktopAttentionController {
  DesktopAttentionController({
    required this.notificationService,
    required this.indicator,
    required this.generalSettingsController,
    required this.activateTarget,
  });

  static final _log = loggerFor('zeta.desktop_attention');

  final DesktopNotificationService notificationService;
  final DesktopAttentionIndicator indicator;
  final GeneralSettingsController generalSettingsController;
  final DesktopAttentionTargetActivator activateTarget;

  final Map<String, _UnreadAttention> _unread = <String, _UnreadAttention>{};
  DesktopAttentionVisibility _visibility = const DesktopAttentionVisibility();
  int _nextNotificationId = 1000;
  bool _initialized = false;
  bool _disposed = false;
  AgentNotificationSettings _lastNotificationSettings =
      const AgentNotificationSettings();

  int get unreadCount => _unread.length;

  Future<void> initialize() async {
    if (_initialized || _disposed) {
      return;
    }
    _initialized = true;
    await generalSettingsController.load();
    _lastNotificationSettings =
        generalSettingsController.settings.notifications;
    generalSettingsController.addListener(_handleSettingsChanged);
    try {
      final initialPayload = await notificationService.initialize(
        onActivate: (payload) {
          unawaited(handleActivation(payload));
        },
      );
      if (_lastNotificationSettings.enabled) {
        await _requestPermissions();
      }
      if (initialPayload != null) {
        unawaited(handleActivation(initialPayload));
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not initialize desktop notifications',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void updateVisibility(DesktopAttentionVisibility visibility) {
    if (_disposed) {
      return;
    }
    _visibility = visibility;
    if (visibility.windowFocused &&
        visibility.agentCanvasVisible &&
        visibility.providerId != null &&
        visibility.threadId != null) {
      unawaited(markThreadRead(visibility.providerId!, visibility.threadId!));
    }
  }

  Future<void> handleAttention(AgentWorkspaceAttention attention) async {
    if (_disposed) {
      return;
    }
    if (attention.signal.phase == AgentAttentionPhase.resolved) {
      await _removeIdentity(attention.identity);
      return;
    }
    final settings = generalSettingsController.settings.notifications;
    if (!_isEnabled(attention.signal.kind, settings) ||
        _visibility.shows(attention)) {
      return;
    }
    if (_unread.containsKey(attention.identity)) {
      return;
    }

    final notificationId = _nextNotificationId += 1;
    final unread = _UnreadAttention(
      attention: attention,
      notificationId: notificationId,
    );
    final wasEmpty = _unread.isEmpty;
    _unread[attention.identity] = unread;
    await _syncIndicator(requestAttention: wasEmpty);
    try {
      await notificationService.show(
        DesktopNotificationRequest(
          id: notificationId,
          title: _titleFor(attention.signal.kind),
          body: _safeBody(attention),
          payload: jsonEncode(<String, Object?>{
            'version': 1,
            'providerId': attention.providerId,
            'threadId': attention.threadId,
            'identity': attention.identity,
          }),
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

  Future<void> markThreadRead(String providerId, String threadId) async {
    final removed = <_UnreadAttention>[];
    _unread.removeWhere((_, value) {
      final matches =
          value.attention.providerId == providerId &&
          value.attention.threadId == threadId;
      if (matches) {
        removed.add(value);
      }
      return matches;
    });
    if (removed.isEmpty) {
      return;
    }
    await _cancelAll(removed);
    await _syncIndicator();
  }

  Future<void> handleActivation(String? payload) async {
    if (_disposed || payload == null || payload.trim().isEmpty) {
      return;
    }
    try {
      final raw = jsonDecode(payload);
      if (raw is! Map || raw['version'] != 1) {
        return;
      }
      final providerId = raw['providerId'];
      final threadId = raw['threadId'];
      final identity = raw['identity'];
      if (providerId is! String || threadId is! String) {
        return;
      }
      final activated = await activateTarget(providerId, threadId);
      if (activated) {
        await markThreadRead(providerId, threadId);
      } else if (identity is String) {
        await _removeIdentity(identity);
      }
    } catch (error, stackTrace) {
      _log.w(
        'Could not handle notification activation',
        error: error,
        stackTrace: stackTrace,
      );
    }
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    generalSettingsController.removeListener(_handleSettingsChanged);
    notificationService.dispose();
  }

  void _handleSettingsChanged() {
    if (_disposed) {
      return;
    }
    final settings = generalSettingsController.settings.notifications;
    final wasEnabled = _lastNotificationSettings.enabled;
    _lastNotificationSettings = settings;
    if (!wasEnabled && settings.enabled) {
      unawaited(_requestPermissions());
    }
    final removed = <_UnreadAttention>[];
    _unread.removeWhere((_, value) {
      final remove = !_isEnabled(value.attention.signal.kind, settings);
      if (remove) {
        removed.add(value);
      }
      return remove;
    });
    if (removed.isNotEmpty) {
      unawaited(_cancelAll(removed));
      unawaited(_syncIndicator());
    }
  }

  Future<void> _removeIdentity(String identity) async {
    final removed = _unread.remove(identity);
    if (removed == null) {
      return;
    }
    await _cancelAll(<_UnreadAttention>[removed]);
    await _syncIndicator();
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

  Future<void> _cancelAll(Iterable<_UnreadAttention> values) async {
    for (final value in values) {
      try {
        await notificationService.cancel(value.notificationId);
      } catch (error, stackTrace) {
        // Windows 非 MSIX 运行时可能无法撤回通知；内部未读仍是权威状态。
        _log.t(
          'Could not cancel desktop notification',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }
  }

  Future<void> _syncIndicator({bool requestAttention = false}) async {
    try {
      await indicator.setUnreadCount(_unread.length);
      if (requestAttention && _unread.isNotEmpty) {
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

  bool _isEnabled(AgentAttentionKind kind, AgentNotificationSettings settings) {
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

  String _titleFor(AgentAttentionKind kind) => switch (kind) {
    AgentAttentionKind.turnCompleted => '任务已完成',
    AgentAttentionKind.turnFailed => '任务执行失败',
    AgentAttentionKind.turnInterrupted => '任务已中断',
    AgentAttentionKind.permissionRequired => '需要确认权限',
    AgentAttentionKind.questionRequired => '需要回答问题',
    AgentAttentionKind.planApprovalRequired => '需要确认计划',
    AgentAttentionKind.planExecutionRequired => '计划可以执行',
  };

  String _safeBody(AgentWorkspaceAttention attention) {
    final normalized = attention.projectPath.replaceAll('\\', '/');
    final segments = normalized
        .split('/')
        .where((segment) => segment.trim().isNotEmpty)
        .toList(growable: false);
    final projectName = segments.isEmpty ? '当前项目' : segments.last;
    return '$projectName · Agent 会话';
  }
}

final class _UnreadAttention {
  const _UnreadAttention({
    required this.attention,
    required this.notificationId,
  });

  final AgentWorkspaceAttention attention;
  final int notificationId;
}

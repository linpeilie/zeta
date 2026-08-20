// Named public dependency parameters intentionally initialize private fields.
// ignore_for_file: prefer_initializing_formals

import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:equatable/equatable.dart';

/// A platform-neutral, already-localized desktop notification.
final class NotificationRequest extends Equatable {
  /// Creates a notification request.
  const NotificationRequest({
    required this.title,
    required this.body,
    this.tag,
  });

  /// Localized notification title.
  final String title;

  /// Localized notification body.
  final String body;

  /// Optional stable replacement/grouping identifier.
  final String? tag;

  @override
  List<Object?> get props => [title, body, tag];
}

/// The operation that failed at the desktop notification boundary.
enum DesktopNotificationOperation {
  /// Show a localized notification.
  notify,

  /// Update the desktop badge.
  setBadge,

  /// Request non-critical attention.
  requestAttention,
}

/// A typed failure from a desktop notification port.
final class DesktopNotificationException implements Exception {
  /// Creates a notification failure.
  const DesktopNotificationException({
    required this.operation,
    required this.cause,
  });

  /// Failed operation.
  final DesktopNotificationOperation operation;

  /// Original error retained for sanitized diagnostics.
  final Object cause;

  @override
  String toString() => 'DesktopNotificationException($operation)';
}

/// Domain boundary for already-localized desktop attention requests.
class DesktopNotificationsRepository {
  /// Creates a repository backed by platform-neutral ports.
  const DesktopNotificationsRepository({
    required DesktopNotificationApi notifications,
    required DesktopAttentionApi attention,
  }) : _notifications = notifications,
       _attention = attention;

  final DesktopNotificationApi _notifications;
  final DesktopAttentionApi _attention;

  /// Shows [request] without performing localization or reading settings.
  Future<void> notify(NotificationRequest request) async {
    try {
      await _notifications.show(
        title: request.title,
        body: request.body,
        tag: request.tag,
      );
    } on Object catch (error) {
      throw DesktopNotificationException(
        operation: DesktopNotificationOperation.notify,
        cause: error,
      );
    }
  }

  /// Sets the non-negative desktop badge count.
  Future<void> setBadge(int count) async {
    if (count < 0) {
      throw ArgumentError.value(count, 'count', 'must not be negative');
    }
    try {
      await _attention.setBadgeCount(count);
    } on Object catch (error) {
      throw DesktopNotificationException(
        operation: DesktopNotificationOperation.setBadge,
        cause: error,
      );
    }
  }

  /// Requests non-critical user attention.
  Future<void> requestAttention() async {
    try {
      await _attention.requestUserAttention();
    } on Object catch (error) {
      throw DesktopNotificationException(
        operation: DesktopNotificationOperation.requestAttention,
        cause: error,
      );
    }
  }
}

import 'package:desktop_notifications_repository/desktop_notifications_repository.dart';
import 'package:desktop_platform_api/desktop_platform_api.dart';
import 'package:mocktail/mocktail.dart';
import 'package:test/test.dart';

final class _Notifications extends Mock implements DesktopNotificationApi {}

final class _Attention extends Mock implements DesktopAttentionApi {}

void main() {
  late _Notifications notifications;
  late _Attention attention;
  late DesktopNotificationsRepository repository;

  setUp(() {
    notifications = _Notifications();
    attention = _Attention();
    repository = DesktopNotificationsRepository(
      notifications: notifications,
      attention: attention,
    );
  });

  group('DesktopNotificationsRepository', () {
    test('forwards already-localized notification copy', () async {
      when(
        () => notifications.show(
          title: any(named: 'title'),
          body: any(named: 'body'),
          tag: any(named: 'tag'),
        ),
      ).thenAnswer((_) async {});
      const request = NotificationRequest(
        title: 'Done',
        body: 'The task completed',
        tag: 'thread-1',
      );

      await repository.notify(request);

      verify(
        () => notifications.show(
          title: 'Done',
          body: 'The task completed',
          tag: 'thread-1',
        ),
      ).called(1);
      expect(
        request,
        const NotificationRequest(
          title: 'Done',
          body: 'The task completed',
          tag: 'thread-1',
        ),
      );
      expect(request.props, ['Done', 'The task completed', 'thread-1']);
    });

    test('forwards badge and attention commands', () async {
      when(() => attention.setBadgeCount(3)).thenAnswer((_) async {});
      when(attention.requestUserAttention).thenAnswer((_) async {});

      await repository.setBadge(3);
      await repository.requestAttention();

      verify(() => attention.setBadgeCount(3)).called(1);
      verify(attention.requestUserAttention).called(1);
    });

    test('rejects a negative badge count before platform IO', () async {
      await expectLater(repository.setBadge(-1), throwsArgumentError);
      verifyNever(() => attention.setBadgeCount(any()));
    });

    test('translates notification port failures', () async {
      when(
        () => notifications.show(
          title: any(named: 'title'),
          body: any(named: 'body'),
          tag: any(named: 'tag'),
        ),
      ).thenThrow(StateError('hidden'));

      final failure = await _failureOf(
        repository.notify(const NotificationRequest(title: 'x', body: 'y')),
      );

      expect(failure.operation, DesktopNotificationOperation.notify);
      expect(failure.cause, isA<StateError>());
      expect(
        failure.toString(),
        'DesktopNotificationException(DesktopNotificationOperation.notify)',
      );
    });

    test('translates badge port failures', () async {
      when(() => attention.setBadgeCount(2)).thenThrow(Exception('hidden'));
      final failure = await _failureOf(repository.setBadge(2));
      expect(failure.operation, DesktopNotificationOperation.setBadge);
    });

    test('translates attention port failures', () async {
      when(attention.requestUserAttention).thenThrow(Exception('hidden'));
      final failure = await _failureOf(repository.requestAttention());
      expect(
        failure.operation,
        DesktopNotificationOperation.requestAttention,
      );
    });
  });
}

Future<DesktopNotificationException> _failureOf(Future<void> future) async {
  try {
    await future;
  } on DesktopNotificationException catch (error) {
    return error;
  }
  throw StateError('Expected DesktopNotificationException');
}

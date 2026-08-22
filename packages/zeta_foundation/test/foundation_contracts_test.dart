import 'package:test/test.dart';
import 'package:zeta_foundation/zeta_foundation.dart';

void main() {
  group('Clock', () {
    test('systemClock 返回当前时间', () {
      final before = DateTime.now();
      final now = systemClock();

      expect(
        now.isBefore(before.subtract(const Duration(seconds: 1))),
        isFalse,
      );
    });

    test('fixedClock 每次返回同一时刻', () {
      final instant = DateTime.utc(2026, 8, 21, 10, 30);
      final clock = fixedClock(instant);

      expect(clock(), instant);
      expect(clock(), instant);
    });
  });

  group('OperationId', () {
    test('序号在同一生成器内单调递增', () {
      final generator = OperationIdGenerator(scope: 'conversation.send');

      final first = generator.next();
      final second = generator.next();

      expect(first.sequence, 1);
      expect(second.sequence, 2);
      expect(generator.issuedCount, 2);
      expect(first, isNot(second));
    });

    test('只有最新一次操作被认作 current', () {
      final generator = OperationIdGenerator(scope: 'threads.load');
      final stale = generator.next();
      final latest = generator.next();

      expect(generator.isCurrent(latest), isTrue);
      expect(generator.isCurrent(stale), isFalse);
      expect(generator.isCurrent(null), isFalse);
    });

    test('不同 scope 的同序号 id 不相等，避免跨切片撞车', () {
      const first = OperationId(scope: 'a', sequence: 1);
      const second = OperationId(scope: 'b', sequence: 1);

      expect(first, isNot(second));
      expect(generatorFor('a').next(), first);
    });

    test('toString 只含 scope 与序号，可安全进日志', () {
      const id = OperationId(scope: 'conversation.cancel', sequence: 7);

      expect('$id', 'conversation.cancel#7');
    });
  });

  group('集合相等', () {
    test('列表逐元素比较，长度或元素不同即不等', () {
      expect(zetaListEquals(<int>[1, 2], <int>[1, 2]), isTrue);
      expect(zetaListEquals(<int>[1, 2], <int>[2, 1]), isFalse);
      expect(zetaListEquals(<int>[1], <int>[1, 2]), isFalse);
      expect(zetaListEquals<int>(null, null), isTrue);
      expect(zetaListEquals(<int>[1], null), isFalse);
    });

    test('Map 比较键集合与逐键值', () {
      expect(
        zetaMapEquals(<String, int>{'a': 1}, <String, int>{'a': 1}),
        isTrue,
      );
      expect(
        zetaMapEquals(<String, int>{'a': 1}, <String, int>{'a': 2}),
        isFalse,
      );
      expect(
        zetaMapEquals(<String, int>{'a': 1}, <String, int>{'b': 1}),
        isFalse,
      );
      expect(zetaMapEquals<String, int>(null, null), isTrue);
    });
  });

  group('日志端口', () {
    tearDown(ZetaLogging.reset);

    test('未安装实现时全部丢弃且不抛异常', () {
      ZetaLogging.reset();
      final logger = zetaLoggerFor('zeta.test');

      // 未安装实现时写日志既不抛异常也不产生任何输出。
      logger
        ..t('trace')
        ..w('warn', error: StateError('x'));
    });

    test('install 之前拿到的 logger 在 install 之后也能写出日志', () {
      // 回归：顶层 `final _log = zetaLoggerFor(...)` 会在首次访问时求值。
      // 早期实现直接返回实例，一旦首次访问早于 install，该 scope 永久变成
      // no-op，之后所有日志静默消失。
      ZetaLogging.reset();
      final early = zetaLoggerFor('zeta.test.early');
      early.w('dropped before install');

      final written = <String>[];
      ZetaLogging.install((scope) => _RecordingLogger(scope, written));
      early.w('after install');

      expect(written, <String>['zeta.test.early:after install']);
    });

    test('安装后按 scope 分发', () {
      final scopes = <String>[];
      ZetaLogging.install((scope) {
        scopes.add(scope);
        return const NoopZetaLogger();
      });

      // 代理在**写日志时**才解析工厂，取 logger 本身不触发。
      final logger = zetaLoggerFor('zeta.agent.pipeline');
      expect(scopes, isEmpty);

      logger.i('ready');

      expect(scopes, <String>['zeta.agent.pipeline']);
    });
  });

  group('Transition', () {
    test('stateOnly 不携带副作用', () {
      final transition = Transition<int, String>.stateOnly(1);

      expect(transition.state, 1);
      expect(transition.effects, isEmpty);
      expect(transition.hasEffects, isFalse);
    });

    test('effects 是不可变副本', () {
      final effects = <String>['a'];
      final transition = Transition<int, String>(1, effects);
      effects.add('b');

      expect(transition.effects, <String>['a']);
      expect(() => transition.effects.add('c'), throwsUnsupportedError);
    });

    test('withEffects 追加而不改变状态', () {
      final transition = Transition<int, String>(1, const <String>[
        'a',
      ]).withEffects(const <String>['b']);

      expect(transition.state, 1);
      expect(transition.effects, <String>['a', 'b']);
    });
  });
}

OperationIdGenerator generatorFor(String scope) =>
    OperationIdGenerator(scope: scope);

final class _RecordingLogger implements ZetaLogger {
  _RecordingLogger(this.scope, this.written);

  final String scope;
  final List<String> written;

  void _record(String message) => written.add('$scope:$message');

  @override
  void t(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void d(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void i(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void w(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void e(String message, {Object? error, StackTrace? stackTrace}) =>
      _record(message);

  @override
  void failure(
    String message, {
    Map<String, Object?> context = const <String, Object?>{},
    Object? error,
    StackTrace? stackTrace,
  }) => _record(message);
}

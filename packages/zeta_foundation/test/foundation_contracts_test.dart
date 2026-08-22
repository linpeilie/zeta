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

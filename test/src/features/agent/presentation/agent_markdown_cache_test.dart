import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';

/// 等待保温信号微任务落盘。
Future<void> flushKeepAlive() => Future<void>.delayed(Duration.zero);

void main() {
  group('AgentMarkdownCache', () {
    test('复用历史 Markdown 控制器并限制渲染保温数量', () async {
      final cache = AgentMarkdownCache(
        maxWarmEntries: 2,
        maxControllerEntries: 3,
      );
      addTearDown(cache.dispose);

      final first = cache.acquire(messageId: 'a', data: '# A');
      final firstController = first.controller;
      final second = cache.acquire(messageId: 'b', data: '# B');
      await flushKeepAlive();

      expect(first.shouldKeepAlive, isTrue);
      expect(second.shouldKeepAlive, isTrue);
      expect(cache.warmEntryCount, 2);

      final third = cache.acquire(messageId: 'c', data: '# C');
      await flushKeepAlive();

      expect(first.shouldKeepAlive, isFalse);
      expect(second.shouldKeepAlive, isTrue);
      expect(third.shouldKeepAlive, isTrue);
      expect(cache.warmEntryCount, 2);

      first.release();
      second.release();
      third.release();
      await flushKeepAlive();
      expect(cache.warmEntryCount, 0);

      final firstAgain = cache.acquire(messageId: 'a', data: '# A');
      expect(firstAgain.controller, same(firstController));
      expect(cache.debugControllerHitCount, 1);
      firstAgain.release();
    });

    test('流式前缀追加复用控制器并按 LRU 释放旧解析结果', () {
      final cache = AgentMarkdownCache(
        maxWarmEntries: 1,
        maxControllerEntries: 2,
      );
      addTearDown(cache.dispose);

      final live = cache.acquire(messageId: 'live', data: 'hello');
      final liveController = live.controller;
      live.updateData('hello world', preferIncrementalUpdate: true);
      expect(live.controller, same(liveController));
      expect(live.controller.data, 'hello world');
      live.release();

      cache.acquire(messageId: 'history-1', data: 'one').release();
      cache.acquire(messageId: 'history-2', data: 'two').release();

      expect(cache.controllerCount, 2);
      expect(cache.debugDisposedControllerCount, 1);
      expect(cache.debugCreatedControllerCount, 3);
    });
  });
}

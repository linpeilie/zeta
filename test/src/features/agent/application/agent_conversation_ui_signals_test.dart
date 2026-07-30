import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';

void main() {
  group('AgentConversationUiSignals cadence', () {
    late AgentConversationTimelineStore timeline;
    late AgentConversationUiSignals signals;
    late List<VoidCallback> pendingFrames;
    var legacyNotifyCount = 0;

    setUp(() {
      timeline = AgentConversationTimelineStore();
      legacyNotifyCount = 0;
      pendingFrames = <VoidCallback>[];
      signals = AgentConversationUiSignals(
        timeline: timeline,
        onLegacyNotify: () => legacyNotifyCount += 1,
        isDisposed: () => false,
        scheduleAfterFrame: pendingFrames.add,
      );
    });

    tearDown(() {
      signals.dispose();
    });

    void releaseFrames() {
      final frames = List<VoidCallback>.of(pendingFrames);
      pendingFrames.clear();
      for (final frame in frames) {
        frame();
      }
    }

    test('scheduleStreamFlush coalesces into a single live publish', () async {
      final autoBefore = signals.autoScrollTick;
      final headerBefore = signals.headerVersion;

      signals.scheduleStreamFlush(autoScroll: true);
      signals.scheduleStreamFlush(autoScroll: true);
      signals.scheduleStreamFlush(header: true);

      expect(signals.autoScrollTick, autoBefore);
      await Future<void>.delayed(
        kAgentStreamFlushInterval + const Duration(milliseconds: 8),
      );

      expect(signals.headerVersion, headerBefore + 1);
      expect(signals.autoScrollTick, autoBefore + 1);
      expect(legacyNotifyCount, 1);
      releaseFrames();
    });

    test(
      'flushStreamChangesNow publishes immediately and absorbs schedule',
      () {
        signals.scheduleStreamFlush(autoScroll: true);
        signals.flushStreamChangesNow(history: true);

        expect(signals.historyVersion, 1);
        expect(signals.autoScrollTick, 1);
        expect(legacyNotifyCount, 1);
        // 关键路径不占用 stream in-flight。
        expect(pendingFrames, isEmpty);
      },
    );

    test(
      'timer stream flush defers while previous stream frame in flight',
      () async {
        signals.scheduleStreamFlush(autoScroll: true);
        await Future<void>.delayed(
          kAgentStreamFlushInterval + const Duration(milliseconds: 8),
        );
        expect(signals.autoScrollTick, 1);
        expect(pendingFrames, hasLength(1));

        // 帧未释放：再次 timer flush 应 defer。
        signals.scheduleStreamFlush(autoScroll: true);
        // 手动触发 timer 回调路径：直接 flushPending（模拟 timer 到期）。
        signals.flushPendingStreamChangesNow();
        expect(signals.debugSkippedInFlightStreamFlushCount, 1);
        expect(signals.autoScrollTick, 1);

        releaseFrames();
        await Future<void>.delayed(
          kAgentStreamFlushInterval + const Duration(milliseconds: 8),
        );
        expect(signals.autoScrollTick, 2);
      },
    );

    test('force flush is never blocked by stream in-flight', () async {
      signals.scheduleStreamFlush(autoScroll: true);
      await Future<void>.delayed(
        kAgentStreamFlushInterval + const Duration(milliseconds: 8),
      );
      expect(pendingFrames, hasLength(1));

      signals.flushStreamChangesNow(history: true, liveTurn: true);
      expect(signals.historyVersion, 1);
      // 不依赖 releaseFrames 也能立即成功。
    });
  });
}

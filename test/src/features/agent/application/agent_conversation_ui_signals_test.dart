import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';

void main() {
  group('AgentConversationUiSignals cadence', () {
    late AgentConversationTimelineStore timeline;
    late AgentConversationUiSignals signals;
    var legacyNotifyCount = 0;

    setUp(() {
      timeline = AgentConversationTimelineStore();
      legacyNotifyCount = 0;
      signals = AgentConversationUiSignals(
        timeline: timeline,
        onLegacyNotify: () => legacyNotifyCount += 1,
        isDisposed: () => false,
      );
    });

    tearDown(() {
      signals.dispose();
    });

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
    });

    test(
      'flushStreamChangesNow publishes immediately and absorbs schedule',
      () {
        signals.scheduleStreamFlush(autoScroll: true);
        signals.flushStreamChangesNow(history: true);

        expect(signals.historyVersion, 1);
        expect(signals.autoScrollTick, 1);
        expect(legacyNotifyCount, 1);
      },
    );
  });
}

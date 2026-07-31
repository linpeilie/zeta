import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

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
      timeline.dispose();
    });

    void releaseFrames() {
      final frames = List<VoidCallback>.of(pendingFrames);
      pendingFrames.clear();
      for (final frame in frames) {
        frame();
      }
    }

    AgentUiUpdateRequest streamRequest({
      Set<AgentUiRegion> regions = const <AgentUiRegion>{},
      List<AgentUiEffect> effects = const <AgentUiEffect>[],
    }) {
      return AgentUiUpdateRequest(
        regions: <AgentUiRegion>{AgentUiRegion.liveTurn, ...regions},
        effects: effects,
      );
    }

    AgentUiUpdateRequest immediateRequest({
      Set<AgentUiRegion> regions = const <AgentUiRegion>{},
      List<AgentUiEffect> effects = const <AgentUiEffect>[],
    }) {
      return AgentUiUpdateRequest(
        regions: regions,
        urgency: AgentUiUpdateUrgency.immediate,
        effects: effects,
      );
    }

    test('scheduleStreamFlush coalesces into a single live publish', () async {
      final autoBefore = signals.autoScrollTick;
      final headerBefore = signals.headerVersion;

      signals.scheduleStreamFlush(
        streamRequest(effects: const <AgentUiEffect>[AgentRequestAutoScroll()]),
      );
      signals.scheduleStreamFlush(
        streamRequest(effects: const <AgentUiEffect>[AgentRequestAutoScroll()]),
      );
      signals.scheduleStreamFlush(
        streamRequest(regions: const <AgentUiRegion>{AgentUiRegion.header}),
      );

      expect(signals.autoScrollTick, autoBefore);
      await Future<void>.delayed(
        kAgentStreamFlushInterval + const Duration(milliseconds: 8),
      );

      expect(signals.headerVersion, headerBefore + 1);
      expect(signals.autoScrollTick, autoBefore + 1);
      expect(legacyNotifyCount, 1);
      expect(
        signals.diagnostics,
        isA<AgentConversationUiSignalsDiagnostics>()
            .having(
              (value) => value.scheduledStreamFlushCount,
              'scheduledStreamFlushCount',
              3,
            )
            .having(
              (value) => value.immediateFlushCount,
              'immediateFlushCount',
              0,
            )
            .having(
              (value) => value.mergedRequestCount,
              'mergedRequestCount',
              2,
            )
            .having(
              (value) => value.actualPublishCount,
              'actualPublishCount',
              1,
            )
            .having((value) => value.legacyNotifyCount, 'legacyNotifyCount', 1),
      );
      releaseFrames();
    });

    test(
      'flushStreamChangesNow publishes immediately and absorbs schedule',
      () {
        signals.scheduleStreamFlush(
          streamRequest(
            effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
          ),
        );
        signals.flushStreamChangesNow(
          immediateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.history},
          ),
        );

        expect(signals.historyVersion, 1);
        expect(signals.autoScrollTick, 1);
        expect(legacyNotifyCount, 1);
        expect(signals.diagnostics.scheduledStreamFlushCount, 1);
        expect(signals.diagnostics.immediateFlushCount, 1);
        expect(signals.diagnostics.mergedRequestCount, 1);
        expect(signals.diagnostics.actualPublishCount, 1);
        expect(signals.diagnostics.legacyNotifyCount, 1);
        // 关键路径不占用 stream in-flight。
        expect(pendingFrames, isEmpty);
      },
    );

    test('scheduled composer request is promoted without changing cadence', () {
      signals.scheduleStreamFlush(
        streamRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );

      signals.flushPendingStreamChangesNow();

      expect(signals.composerVersion, 1);
      expect(signals.autoScrollTick, 1);
      expect(signals.diagnostics.scheduledStreamFlushCount, 1);
      expect(signals.diagnostics.immediateFlushCount, 1);
      expect(signals.diagnostics.mergedRequestCount, 1);
      expect(signals.diagnostics.actualPublishCount, 1);
      expect(signals.diagnostics.legacyNotifyCount, 1);
      expect(pendingFrames, isEmpty);
    });

    test(
      'timer stream flush defers while previous stream frame in flight',
      () async {
        signals.scheduleStreamFlush(
          streamRequest(
            effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
          ),
        );
        await Future<void>.delayed(
          kAgentStreamFlushInterval + const Duration(milliseconds: 8),
        );
        expect(signals.autoScrollTick, 1);
        expect(pendingFrames, hasLength(1));

        // 帧未释放：再次 timer flush 应 defer。
        signals.scheduleStreamFlush(
          streamRequest(
            effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
          ),
        );
        // 手动触发 timer 回调路径：直接 flushPending（模拟 timer 到期）。
        signals.flushPendingStreamChangesNow();
        expect(signals.debugSkippedInFlightStreamFlushCount, 1);
        expect(signals.autoScrollTick, 1);
        expect(signals.diagnostics.scheduledStreamFlushCount, 2);
        expect(signals.diagnostics.mergedRequestCount, 0);
        expect(signals.diagnostics.actualPublishCount, 1);
        expect(signals.diagnostics.skippedInFlightStreamFlushCount, 1);

        releaseFrames();
        await Future<void>.delayed(
          kAgentStreamFlushInterval + const Duration(milliseconds: 8),
        );
        expect(signals.autoScrollTick, 2);
        expect(signals.diagnostics.actualPublishCount, 2);
        expect(signals.diagnostics.legacyNotifyCount, 2);
      },
    );

    test('force flush is never blocked by stream in-flight', () async {
      signals.scheduleStreamFlush(
        streamRequest(effects: const <AgentUiEffect>[AgentRequestAutoScroll()]),
      );
      await Future<void>.delayed(
        kAgentStreamFlushInterval + const Duration(milliseconds: 8),
      );
      expect(pendingFrames, hasLength(1));

      signals.flushStreamChangesNow(
        immediateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.history,
            AgentUiRegion.liveTurn,
          },
        ),
      );
      expect(signals.historyVersion, 1);
      expect(signals.diagnostics.immediateFlushCount, 1);
      expect(signals.diagnostics.actualPublishCount, 2);
      expect(signals.diagnostics.legacyNotifyCount, 2);
      // 不依赖 releaseFrames 也能立即成功。
    });

    test('diagnostics returns an immutable point-in-time snapshot', () {
      final before = signals.diagnostics;

      signals.publish(
        immediateRequest(regions: const <AgentUiRegion>{AgentUiRegion.header}),
      );
      final after = signals.diagnostics;

      expect(before.scheduledStreamFlushCount, 0);
      expect(before.immediateFlushCount, 0);
      expect(before.mergedRequestCount, 0);
      expect(before.actualPublishCount, 0);
      expect(before.legacyNotifyCount, 0);
      expect(before.skippedInFlightStreamFlushCount, 0);
      expect(after.actualPublishCount, 1);
      expect(after.legacyNotifyCount, 1);
      expect(legacyNotifyCount, 1);
    });

    test('typed publish maps regions and consumes auto-scroll effect once', () {
      timeline.startPendingLiveTurn();
      var bindingNotifications = 0;
      var liveTurnNotifications = 0;
      timeline.liveTurnListenable.addListener(() {
        bindingNotifications += 1;
        timeline.liveTurnState?.addListener(() {
          liveTurnNotifications += 1;
        });
      });
      final request = immediateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
          AgentUiRegion.pendingInteraction,
          AgentUiRegion.expansion,
          AgentUiRegion.liveTurn,
        },
        effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
      );

      signals.publish(request);

      expect(signals.historyVersion, 1);
      expect(signals.headerVersion, 1);
      expect(signals.composerVersion, 1);
      expect(signals.pendingInteractionVersion, 1);
      expect(signals.expansionVersion, 1);
      expect(signals.autoScrollTick, 1);
      expect(bindingNotifications, 1);
      expect(liveTurnNotifications, 1);
      expect(signals.debugLastAcceptedRequest, request);
      expect(signals.diagnostics.actualPublishCount, 1);
      expect(signals.diagnostics.legacyNotifyCount, 1);
      expect(legacyNotifyCount, 1);
    });

    test('schedule and force flush enforce urgency contracts', () {
      expect(
        () => signals.scheduleStreamFlush(
          immediateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
          ),
        ),
        throwsAssertionError,
      );
      expect(
        () => signals.flushStreamChangesNow(streamRequest()),
        throwsAssertionError,
      );
    });
  });
}

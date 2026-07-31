import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_timeline_store.dart';
import 'package:zeta/src/features/agent/application/agent_conversation_ui_signals.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

void main() {
  group('AgentConversationUiSignals publish boundary', () {
    late AgentConversationTimelineStore timeline;
    late AgentConversationUiSignals signals;
    var disposed = false;
    var legacyNotifyCount = 0;

    setUp(() {
      timeline = AgentConversationTimelineStore();
      disposed = false;
      legacyNotifyCount = 0;
      signals = AgentConversationUiSignals(
        timeline: timeline,
        onLegacyNotify: () => legacyNotifyCount += 1,
        isDisposed: () => disposed,
      );
    });

    tearDown(() {
      signals.dispose();
      timeline.dispose();
    });

    test('typed publish updates regions and consumes auto-scroll once', () {
      timeline.startPendingLiveTurn();
      var bindingNotifications = 0;
      var liveTurnNotifications = 0;
      timeline.liveTurnListenable.addListener(() {
        bindingNotifications += 1;
        timeline.liveTurnState?.addListener(() {
          liveTurnNotifications += 1;
        });
      });
      final request = AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.history,
          AgentUiRegion.liveTurnBinding,
          AgentUiRegion.header,
          AgentUiRegion.composer,
          AgentUiRegion.pendingInteraction,
          AgentUiRegion.expansion,
          AgentUiRegion.liveTurn,
        },
        urgency: AgentUiUpdateUrgency.immediate,
        effects: const <AgentUiEffect>[
          AgentRequestAutoScroll(),
          AgentRequestAutoScroll(),
        ],
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

    test('empty requests do not publish or notify legacy listeners', () {
      signals.publish(AgentUiUpdateRequest.none);

      expect(signals.debugLastAcceptedRequest, isNull);
      expect(signals.diagnostics.actualPublishCount, 0);
      expect(signals.diagnostics.legacyNotifyCount, 0);
      expect(legacyNotifyCount, 0);
    });

    test('disposed owner rejects scheduler callbacks', () {
      disposed = true;

      signals.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );

      expect(signals.headerVersion, 0);
      expect(signals.diagnostics.actualPublishCount, 0);
      expect(signals.diagnostics.legacyNotifyCount, 0);
      expect(legacyNotifyCount, 0);
    });

    test('diagnostics is an immutable point-in-time snapshot', () {
      final before = signals.diagnostics;

      signals.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
      final after = signals.diagnostics;

      expect(before.scheduledStreamFlushCount, 0);
      expect(before.immediateFlushCount, 0);
      expect(before.mergedRequestCount, 0);
      expect(before.actualPublishCount, 0);
      expect(before.legacyNotifyCount, 0);
      expect(after.actualPublishCount, 1);
      expect(after.legacyNotifyCount, 1);
      expect(legacyNotifyCount, 1);
    });
  });
}

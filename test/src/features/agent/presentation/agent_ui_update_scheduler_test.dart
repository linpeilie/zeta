import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_ui_update_scheduler.dart';

import '../../../testing/fake_agent_frame_scheduler.dart';

void main() {
  group('AgentUiUpdateScheduler', () {
    late FakeAgentFrameScheduler frameScheduler;
    late List<AgentUiUpdateRequest> published;
    late AgentUiUpdateScheduler scheduler;

    setUp(() {
      frameScheduler = FakeAgentFrameScheduler();
      published = <AgentUiUpdateRequest>[];
      scheduler = AgentUiUpdateScheduler(
        published.add,
        frameScheduler: frameScheduler,
      );
    });

    tearDown(() {
      scheduler.dispose();
    });

    test('merges next-frame requests into one publish per frame', () {
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
          },
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );
      final pendingSnapshot = scheduler.diagnostics;

      expect(published, isEmpty);
      expect(frameScheduler.pendingCallbackCount, 1);
      expect(pendingSnapshot.hasPendingRequest, isTrue);
      expect(pendingSnapshot.pendingRegionCount, 2);
      expect(pendingSnapshot.pendingEffectCount, 1);

      frameScheduler.pumpFrame();

      expect(published, hasLength(1));
      expect(
        published.single,
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.liveTurn,
          },
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );
      expect(pendingSnapshot.hasPendingRequest, isTrue);
      expect(scheduler.diagnostics.hasPendingRequest, isFalse);
      expect(scheduler.diagnostics.nextFrameRequestCount, 2);
      expect(scheduler.diagnostics.mergedRequestCount, 1);
      expect(scheduler.diagnostics.scheduledFrames, 1);
      expect(scheduler.diagnostics.framePublishes, 1);
      expect(scheduler.diagnostics.publishedEffects, 1);
    });

    test('immediate absorbs pending and invalidates its callback without '
        'duplicating effects', () {
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );

      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.composer},
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );

      expect(published, hasLength(1));
      expect(
        published.single,
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.composer,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );
      expect(scheduler.diagnostics.mergedRequestCount, 1);
      expect(scheduler.diagnostics.immediatePublishes, 1);
      expect(scheduler.diagnostics.invalidatedFrameCallbacks, 1);

      frameScheduler.pumpFrame();

      expect(published, hasLength(1));
      expect(scheduler.diagnostics.ignoredFrameCallbacks, 1);
      expect(scheduler.diagnostics.publishedEffects, 1);
    });

    test(
      'empty immediate request only flushes an existing pending request',
      () {
        scheduler.publish(
          AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
        );

        expect(published, isEmpty);
        expect(scheduler.diagnostics.immediateRequestCount, 0);
        expect(scheduler.diagnostics.publishCount, 0);
        expect(frameScheduler.pendingCallbackCount, 0);

        scheduler.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
          ),
        );
        scheduler.publish(
          AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate),
        );

        expect(published, hasLength(1));
        expect(published.single.regions, const <AgentUiRegion>{
          AgentUiRegion.header,
        });
        expect(published.single.urgency, AgentUiUpdateUrgency.immediate);
        expect(scheduler.diagnostics.immediateRequestCount, 1);
        expect(scheduler.diagnostics.mergedRequestCount, 1);
        expect(scheduler.diagnostics.publishCount, 1);
      },
    );

    test('immediate request never publishes synchronously during build', () {
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );

      frameScheduler.runInBuildPhase(() {
        scheduler.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.pendingInteraction},
            urgency: AgentUiUpdateUrgency.immediate,
            effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
          ),
        );
        expect(published, isEmpty);
      });

      expect(frameScheduler.pendingCallbackCount, 2);
      expect(scheduler.diagnostics.buildPhaseDeferrals, 1);
      expect(scheduler.diagnostics.invalidatedFrameCallbacks, 1);

      frameScheduler.pumpFrame();

      expect(published, hasLength(1));
      expect(published.single.regions, const <AgentUiRegion>{
        AgentUiRegion.header,
        AgentUiRegion.pendingInteraction,
      });
      expect(published.single.urgency, AgentUiUpdateUrgency.immediate);
      expect(published.single.effects, const <AgentUiEffect>[
        AgentRequestAutoScroll(),
      ]);
      expect(scheduler.diagnostics.framePublishes, 1);
      expect(scheduler.diagnostics.immediatePublishes, 0);
      expect(scheduler.diagnostics.ignoredFrameCallbacks, 1);
    });

    test('dispose clears pending and makes scheduled callbacks inert', () {
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.liveTurn},
          effects: const <AgentUiEffect>[AgentRequestAutoScroll()],
        ),
      );

      scheduler.dispose();
      scheduler.publish(
        AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{AgentUiRegion.header},
          urgency: AgentUiUpdateUrgency.immediate,
        ),
      );
      frameScheduler.pumpFrame();

      expect(published, isEmpty);
      expect(scheduler.diagnostics.isDisposed, isTrue);
      expect(scheduler.diagnostics.hasPendingRequest, isFalse);
      expect(scheduler.diagnostics.hasScheduledFrame, isFalse);
      expect(scheduler.diagnostics.requestsIgnoredAfterDispose, 1);
      expect(scheduler.diagnostics.ignoredFrameCallbacks, 1);
    });

    test(
      'a publish scheduled by a frame callback waits for the next frame',
      () {
        late final AgentUiUpdateScheduler reentrantScheduler;
        reentrantScheduler = AgentUiUpdateScheduler((request) {
          published.add(request);
          if (published.length == 1) {
            reentrantScheduler.publish(
              AgentUiUpdateRequest(
                regions: const <AgentUiRegion>{AgentUiRegion.composer},
              ),
            );
          }
        }, frameScheduler: frameScheduler);
        addTearDown(reentrantScheduler.dispose);

        reentrantScheduler.publish(
          AgentUiUpdateRequest(
            regions: const <AgentUiRegion>{AgentUiRegion.header},
          ),
        );

        frameScheduler.pumpFrame();

        expect(published, hasLength(1));
        expect(frameScheduler.pendingCallbackCount, 1);

        frameScheduler.pumpFrame();

        expect(published, hasLength(2));
        expect(published[1].regions, const <AgentUiRegion>{
          AgentUiRegion.composer,
        });
      },
    );
  });
}

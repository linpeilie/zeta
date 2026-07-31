import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/agent_ui_update_request.dart';

void main() {
  group('AgentUiUpdateRequest', () {
    test(
      'uses structural equality for regions, urgency, and ordered effects',
      () {
        final first = AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.header,
            AgentUiRegion.liveTurn,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[
            _TestEffect(1),
            AgentRequestAutoScroll(),
          ],
        );
        final equal = AgentUiUpdateRequest(
          regions: const <AgentUiRegion>{
            AgentUiRegion.liveTurn,
            AgentUiRegion.header,
          },
          urgency: AgentUiUpdateUrgency.immediate,
          effects: const <AgentUiEffect>[
            _TestEffect(1),
            AgentRequestAutoScroll(),
          ],
        );
        final reorderedEffects = AgentUiUpdateRequest(
          regions: first.regions,
          urgency: first.urgency,
          effects: const <AgentUiEffect>[
            AgentRequestAutoScroll(),
            _TestEffect(1),
          ],
        );

        expect(first, equal);
        expect(first.hashCode, equal.hashCode);
        expect(first, isNot(reorderedEffects));
        expect(const AgentRequestAutoScroll(), const AgentRequestAutoScroll());
      },
    );

    test('defensively copies and exposes unmodifiable collections', () {
      final regions = <AgentUiRegion>[AgentUiRegion.header];
      final effects = <AgentUiEffect>[const _TestEffect(1)];

      final request = AgentUiUpdateRequest(regions: regions, effects: effects);
      regions.add(AgentUiRegion.composer);
      effects.add(const AgentRequestAutoScroll());

      expect(request.regions, const <AgentUiRegion>{AgentUiRegion.header});
      expect(request.effects, const <AgentUiEffect>[_TestEffect(1)]);
      expect(
        () => request.regions.add(AgentUiRegion.composer),
        throwsUnsupportedError,
      );
      expect(
        () => request.effects.add(const AgentRequestAutoScroll()),
        throwsUnsupportedError,
      );
    });

    test('merges region union and lets immediate urgency win', () {
      final scheduled = AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.liveTurn,
          AgentUiRegion.header,
        },
      );
      final immediate = AgentUiUpdateRequest(
        regions: const <AgentUiRegion>{
          AgentUiRegion.header,
          AgentUiRegion.pendingInteraction,
        },
        urgency: AgentUiUpdateUrgency.immediate,
      );

      final merged = scheduled.mergedWith(immediate);

      expect(merged.regions, const <AgentUiRegion>{
        AgentUiRegion.liveTurn,
        AgentUiRegion.header,
        AgentUiRegion.pendingInteraction,
      });
      expect(merged.urgency, AgentUiUpdateUrgency.immediate);
      expect(scheduled.urgency, AgentUiUpdateUrgency.nextFrame);
      expect(immediate.regions, isNot(same(merged.regions)));
    });

    test('deduplicates effects while preserving first occurrence order', () {
      final first = AgentUiUpdateRequest(
        effects: const <AgentUiEffect>[
          _TestEffect(1),
          AgentRequestAutoScroll(),
          _TestEffect(1),
        ],
      );
      final second = AgentUiUpdateRequest(
        effects: const <AgentUiEffect>[
          _TestEffect(2),
          AgentRequestAutoScroll(),
          _TestEffect(1),
        ],
      );

      final merged = first.mergedWith(second);

      expect(merged.effects, const <AgentUiEffect>[
        _TestEffect(1),
        AgentRequestAutoScroll(),
        _TestEffect(2),
      ]);
    });

    test('none is an empty next-frame value', () {
      expect(AgentUiUpdateRequest.none.isEmpty, isTrue);
      expect(AgentUiUpdateRequest.none, AgentUiUpdateRequest());
      expect(
        AgentUiUpdateRequest(urgency: AgentUiUpdateUrgency.immediate).isEmpty,
        isTrue,
      );
    });
  });
}

final class _TestEffect extends AgentUiEffect {
  const _TestEffect(this.id);

  final int id;

  @override
  bool operator ==(Object other) => other is _TestEffect && id == other.id;

  @override
  int get hashCode => id.hashCode;
}

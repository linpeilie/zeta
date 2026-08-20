import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('retained page view is lazy and preserves visited state', (
    tester,
  ) async {
    var selected = 'a';
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IdeRetainedPageView(
            selectedId: selected,
            pages: const <IdeRetainedPage>[
              IdeRetainedPage(
                id: 'a',
                child: _Probe(key: ValueKey('probe-a'), id: 'a'),
              ),
              IdeRetainedPage(
                id: 'b',
                child: _Probe(key: ValueKey('probe-b'), id: 'b'),
              ),
              IdeRetainedPage(
                id: 'c',
                child: _Probe(key: ValueKey('probe-c'), id: 'c'),
              ),
            ],
          );
        },
      ),
    );
    final stateA = tester.state<_ProbeState>(find.byType(_Probe));
    expect(find.text('probe-a-1'), findsOneWidget);
    expect(find.textContaining('probe-b'), findsNothing);

    update(() => selected = 'b');
    await tester.pump();
    await tester.pump();
    expect(find.text('probe-b-1'), findsOneWidget);

    update(() => selected = 'a');
    await tester.pump();
    await tester.pump();
    expect(
      tester.state<_ProbeState>(find.byKey(const ValueKey('probe-a'))),
      same(stateA),
    );
    expect(find.textContaining('probe-c'), findsNothing);
  });

  testWidgets('unknown and empty selections safely resolve to the first page', (
    tester,
  ) async {
    var pages = const <IdeRetainedPage>[
      IdeRetainedPage(id: 'a', child: Text('A')),
      IdeRetainedPage(id: 'b', child: Text('B')),
    ];
    var selected = 'missing';
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IdeRetainedPageView(pages: pages, selectedId: selected);
        },
      ),
    );
    expect(find.text('A'), findsOneWidget);

    update(() => pages = const <IdeRetainedPage>[]);
    await tester.pump();
    expect(find.byType(PageView), findsNothing);

    update(() {
      pages = const <IdeRetainedPage>[
        IdeRetainedPage(id: 'x', child: Text('X')),
      ];
      selected = 'x';
    });
    await tester.pump();
    await tester.pump();
    expect(find.text('X'), findsOneWidget);
  });

  testWidgets('page identity survives insertion and removal', (tester) async {
    var ids = <String>['b', 'c'];
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IdeRetainedPageView(
            selectedId: 'b',
            pages: <IdeRetainedPage>[
              for (final id in ids)
                IdeRetainedPage(
                  id: id,
                  child: _Probe(key: ValueKey<String>('probe-$id'), id: id),
                ),
            ],
          );
        },
      ),
    );
    final state = tester.state<_ProbeState>(
      find.byKey(const ValueKey('probe-b')),
    );
    update(() => ids = <String>['a', 'b', 'c']);
    await tester.pump();
    await tester.pump();
    expect(
      tester.state<_ProbeState>(find.byKey(const ValueKey('probe-b'))),
      same(state),
    );

    update(() => ids = <String>['b']);
    await tester.pump();
    await tester.pump();
    expect(find.textContaining('probe-b'), findsOneWidget);
  });

  testWidgets('same-length page identity changes realign the controller', (
    tester,
  ) async {
    var ids = <String>['a', 'b'];
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IdeRetainedPageView(
            selectedId: 'a',
            pages: <IdeRetainedPage>[
              for (final id in ids) IdeRetainedPage(id: id, child: Text(id)),
            ],
          );
        },
      ),
    );
    update(() => ids = <String>['a', 'c']);
    await tester.pump();
    await tester.pump();
    expect(find.text('a'), findsOneWidget);
  });
}

class _Probe extends StatefulWidget {
  const _Probe({required this.id, super.key});

  final String id;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  int builds = 0;

  @override
  Widget build(BuildContext context) {
    builds += 1;
    return Text('probe-${widget.id}-$builds');
  }
}

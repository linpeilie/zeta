import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdePulsingLabel updates its active state in place', (
    tester,
  ) async {
    await tester.pumpShadcnApp(const _PulsingLabelHost());
    expect(find.byKey(const ValueKey<String>('ide-tab-loading')), findsNothing);
    await tester.tap(find.text('Toggle pulse'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('ide-tab-loading')),
      findsOneWidget,
    );
    await tester.tap(find.text('Toggle pulse'));
    await tester.pump();
    expect(find.byKey(const ValueKey<String>('ide-tab-loading')), findsNothing);
  });

  testWidgets('IdePulsingLabel honors reduced motion', (tester) async {
    await tester.pumpShadcnApp(
      const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: IdePulsingLabel(label: 'Loading', active: true),
      ),
    );
    expect(
      find.byKey(
        const ValueKey<String>('ide-tab-loading-reduced-motion'),
      ),
      findsOneWidget,
    );
  });
}

class _PulsingLabelHost extends StatefulWidget {
  const _PulsingLabelHost();

  @override
  State<_PulsingLabelHost> createState() => _PulsingLabelHostState();
}

class _PulsingLabelHostState extends State<_PulsingLabelHost> {
  bool active = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IdePulsingLabel(label: 'Loading', active: active),
        TextButton(
          onPressed: () => setState(() => active = !active),
          child: const Text('Toggle pulse'),
        ),
      ],
    );
  }
}

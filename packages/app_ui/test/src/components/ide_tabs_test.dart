import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('IdeTabs renders scrollable options and reports selection', (
    tester,
  ) async {
    String? selected;
    await tester.pumpShadcnApp(
      SizedBox(
        width: 320,
        child: IdeTabs<String>(
          value: 'one',
          semanticLabel: 'Destinations',
          items: const <IdeTabItem<String>>[
            IdeTabItem<String>(
              value: 'one',
              label: 'One',
              leadingIcon: Icons.looks_one,
            ),
            IdeTabItem<String>(value: 'two', label: 'Two'),
          ],
          onChanged: (value) => selected = value,
        ),
      ),
    );

    expect(find.byIcon(Icons.looks_one), findsOneWidget);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
    await tester.tap(find.text('Two'));
    await tester.pump();
    expect(selected, 'two');
  });

  testWidgets('IdeTabs renders expanded loading and reduced-motion states', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      IdeTabs<int>(
        value: 1,
        expand: true,
        controlSize: AppControlSize.compact,
        items: const <IdeTabItem<int>>[
          IdeTabItem<int>(
            value: 1,
            label: 'Loading',
            loading: true,
            loadingSemanticLabel: 'Loading tab',
          ),
        ],
        onChanged: (_) {},
      ),
    );
    expect(
      find.byKey(const ValueKey<String>('ide-tab-loading')),
      findsOneWidget,
    );

    await tester.pumpShadcnApp(
      MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: IdeTabs<int>(
          value: 1,
          items: const <IdeTabItem<int>>[
            IdeTabItem<int>(
              value: 1,
              label: 'Loading',
              loading: true,
              loadingSemanticLabel: 'Loading tab',
            ),
          ],
          onChanged: (_) {},
        ),
      ),
    );
    expect(
      find.byKey(
        const ValueKey<String>('ide-tab-loading-reduced-motion'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('IdeTabs updates loading state and validates selection', (
    tester,
  ) async {
    await tester.pumpShadcnApp(const _TabsLoadingHost());
    expect(find.byKey(const ValueKey<String>('ide-tab-loading')), findsNothing);
    await tester.tap(find.text('Toggle'));
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('ide-tab-loading')),
      findsOneWidget,
    );

    expect(
      () => IdeTabs<int>(
        value: 1,
        items: const <IdeTabItem<int>>[],
        onChanged: (_) {},
      ),
      throwsAssertionError,
    );
    expect(
      () => IdeTabItem<int>(
        value: 1,
        label: 'Loading',
        loading: true,
      ),
      throwsAssertionError,
    );

    await tester.pumpShadcnApp(
      IdeTabs<int>(
        value: 2,
        items: const <IdeTabItem<int>>[
          IdeTabItem<int>(value: 1, label: 'One'),
        ],
        onChanged: (_) {},
      ),
    );
    expect(tester.takeException(), isA<FlutterError>());
  });
}

class _TabsLoadingHost extends StatefulWidget {
  const _TabsLoadingHost();

  @override
  State<_TabsLoadingHost> createState() => _TabsLoadingHostState();
}

class _TabsLoadingHostState extends State<_TabsLoadingHost> {
  bool loading = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        IdeTabs<int>(
          value: 1,
          items: <IdeTabItem<int>>[
            IdeTabItem<int>(
              key: const ValueKey<String>('host-tab'),
              value: 1,
              label: 'One',
              loading: loading,
              loadingSemanticLabel: loading ? 'Loading one' : null,
            ),
          ],
          onChanged: (_) {},
        ),
        TextButton(
          onPressed: () => setState(() => loading = true),
          child: const Text('Toggle'),
        ),
      ],
    );
  }
}

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('page body switches insets and honors width override', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 900,
        child: IdePageBody(maxWidth: 400, child: Text('Wide body')),
      ),
    );
    expect(
      tester.getSize(find.text('Wide body')).width,
      lessThanOrEqualTo(400),
    );

    await tester.pumpShadcnApp(
      const SizedBox(
        width: 500,
        child: IdePageBody(child: Text('Compact body')),
      ),
    );
    final scroll = tester.widget<SingleChildScrollView>(
      find.byType(SingleChildScrollView),
    );
    expect(scroll.padding, const EdgeInsets.all(12));
  });

  testWidgets('page header renders optional slots and scrollable actions', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 300,
        child: Column(
          children: <Widget>[
            IdePageHeader(
              title: 'Settings',
              subtitle: 'Appearance',
              leading: Icon(Icons.arrow_back),
              actions: <Widget>[Text('Reset'), Text('Save')],
            ),
            IdePageHeader(title: 'Simple'),
          ],
        ),
      ),
    );
    expect(find.byIcon(Icons.arrow_back), findsOneWidget);
    expect(
      find.byKey(const ValueKey('ide-page-header-actions')),
      findsOneWidget,
    );
    expect(
      tester.getSemantics(find.text('Settings')).flagsCollection.isHeader,
      isTrue,
    );
    semantics.dispose();
  });

  testWidgets('section adapts its trailing widget and exposes heading', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const Column(
        children: <Widget>[
          SizedBox(
            width: 700,
            child: IdeSection(
              title: 'Wide',
              subtitle: 'Details',
              trailing: Text('Action'),
              child: Text('Content'),
            ),
          ),
          SizedBox(
            width: 500,
            child: IdeSection(
              title: 'Compact',
              trailing: Text('Stacked action'),
              child: Text('Compact content'),
            ),
          ),
          IdeSection(title: 'Plain', child: Text('Plain content')),
        ],
      ),
    );
    expect(find.text('Action'), findsOneWidget);
    expect(find.text('Stacked action'), findsOneWidget);
    expect(find.text('Plain content'), findsOneWidget);
  });

  testWidgets('toolbar applies the themed minimum height and decoration', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const Align(
        alignment: Alignment.topCenter,
        child: IdeToolbar(child: Text('Search')),
      ),
    );
    expect(
      tester.getSize(find.byType(IdeToolbar)).height,
      greaterThanOrEqualTo(34),
    );
  });

  testWidgets('surface constructors cover decorations and overrides', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const Column(
        children: <Widget>[
          Expanded(
            child: IdeSurface.canvas(
              key: ValueKey('canvas'),
              padding: EdgeInsets.all(2),
              showBorder: true,
              child: Text('Canvas'),
            ),
          ),
          Expanded(
            child: IdeSurface.pane(
              key: ValueKey('pane'),
              showBorder: false,
              child: Text('Pane'),
            ),
          ),
          Expanded(
            child: IdeSurface.row(
              key: ValueKey('row'),
              child: Text('Row'),
            ),
          ),
          Expanded(
            child: IdeSurface.popover(
              key: ValueKey('popover'),
              child: Text('Popover'),
            ),
          ),
          Expanded(
            child: IdeSurface(
              level: IdeSurfaceLevel.canvas,
              borderRadius: BorderRadius.all(Radius.circular(3)),
              clipBehavior: Clip.hardEdge,
              child: Text('Custom'),
            ),
          ),
        ],
      ),
    );
    expect(_container(tester, 'pane').foregroundDecoration, isNull);
    expect(_container(tester, 'popover').decoration, isA<ShapeDecoration>());
    expect(_container(tester, 'canvas').foregroundDecoration, isNotNull);
    expect(find.text('Custom'), findsOneWidget);
  });
}

Container _container(WidgetTester tester, String key) {
  return tester.widget<Container>(
    find.descendant(
      of: find.byKey(ValueKey<String>(key)),
      matching: find.byType(Container),
    ),
  );
}

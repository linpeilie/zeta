import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  testWidgets('constraint buckets retain and invalidate the cached subtree', (
    tester,
  ) async {
    var width = 700.0;
    var revision = 0;
    var calls = 0;
    late StateSetter update;
    String bucket(BoxConstraints constraints) =>
        constraints.maxWidth < 640 ? 'compact' : 'regular';
    Widget buildBucket(BuildContext context, String value) {
      calls += 1;
      return Text('$revision-$value');
    }

    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return SizedBox(
            width: width,
            child: IdeConstraintBucketBuilder<String>(
              selectBucket: bucket,
              builder: buildBucket,
            ),
          );
        },
      ),
      size: const Size(1000, 600),
    );
    expect(calls, 1);

    update(() => width = 680);
    await tester.pump();
    expect(calls, 1);

    update(() => width = 600);
    await tester.pump();
    expect(calls, 2);
    expect(find.text('0-compact'), findsOneWidget);

    update(() => revision = 1);
    await tester.pump();
    expect(calls, 2);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: SizedBox.shrink(),
      ),
    );
  });

  testWidgets('constraint buckets invalidate when callbacks change', (
    tester,
  ) async {
    var calls = 0;
    var alternate = false;
    late StateSetter update;
    await tester.pumpShadcnApp(
      StatefulBuilder(
        builder: (context, setState) {
          update = setState;
          return IdeConstraintBucketBuilder<int>(
            selectBucket: alternate
                ? (constraints) => constraints.maxWidth.round()
                : (constraints) => 1,
            builder: (context, value) {
              calls += 1;
              return Text('$value');
            },
          );
        },
      ),
    );
    update(() => alternate = true);
    await tester.pump();
    expect(calls, 2);
  });

  testWidgets('compact metrics handle empty, fixed, equal, and interactive', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    var taps = 0;
    await tester.pumpShadcnApp(
      Column(
        children: <Widget>[
          const CompactMetricBar(items: <CompactMetricItem>[]),
          SizedBox(
            width: 900,
            child: CompactMetricBar(
              items: <CompactMetricItem>[
                CompactMetricItem(
                  label: 'Requests',
                  value: '128',
                  detail: 'Today',
                  icon: Icons.send,
                  tone: Colors.green,
                  semanticLabel: 'Open request details',
                  onPressed: () => taps += 1,
                ),
                const CompactMetricItem(label: 'Tokens', value: '42k'),
              ],
            ),
          ),
          const SizedBox(
            width: 300,
            child: CompactMetricBar(
              items: <CompactMetricItem>[
                CompactMetricItem(label: 'Cost', value: r'$12'),
                CompactMetricItem(label: 'Time', value: '2m'),
              ],
            ),
          ),
        ],
      ),
      size: const Size(1000, 600),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compact-metric-item-0')).first)
          .width,
      moreOrLessEquals(449.5),
    );
    expect(
      tester
          .getSize(find.byKey(const ValueKey('compact-metric-item-0')).last)
          .width,
      180,
    );
    expect(_semantics('Open request details'), findsOneWidget);
    await tester.tap(find.text('Requests'));
    expect(taps, 1);
    semantics.dispose();
  });

  testWidgets('data rows apply semantic column styles and interaction', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpShadcnApp(
      Column(
        children: <Widget>[
          IdeDataRow(
            values: const <String>['Model', 'Tokens'],
            flexes: const <int>[2, 1],
            header: true,
            numericColumns: const <int>{1},
            identifierColumns: const <int>{0},
            showDivider: false,
          ),
          IdeDataRow(
            values: const <String>['gpt-5', '120'],
            flexes: const <int>[2, 1],
            identifierColumns: const <int>{0},
            numericColumns: const <int>{1},
            semanticLabel: 'Open model',
            onPressed: () => taps += 1,
          ),
        ],
      ),
    );
    expect(tester.widget<Text>(find.text('120')).textAlign, TextAlign.end);
    expect(
      tester.widget<Text>(find.text('120')).style?.fontFeatures,
      contains(const FontFeature.tabularFigures()),
    );
    await tester.tap(find.text('gpt-5'));
    expect(taps, 1);
  });

  testWidgets('key value rows cover typography, selection, and trailing', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const Column(
        children: <Widget>[
          IdeKeyValueRow(label: 'Vendor', value: 'OpenAI'),
          IdeKeyValueRow(
            label: 'Model',
            value: 'gpt-5',
            tone: IdeKeyValueTone.identifier,
          ),
          IdeKeyValueRow(
            label: 'Path',
            value: '/bin/zeta',
            tone: IdeKeyValueTone.code,
            selectable: true,
            maxLines: 3,
          ),
          IdeKeyValueRow(
            label: 'Count',
            value: '120',
            tone: IdeKeyValueTone.numeric,
            valueColor: Colors.orange,
            trailing: Icon(Icons.copy),
          ),
        ],
      ),
    );
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.byIcon(Icons.copy), findsOneWidget);
    expect(tester.widget<Text>(find.text('120')).style?.color, Colors.orange);
  });

  testWidgets('list, settings, group, and divider variants render', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 700,
        child: Column(
          children: <Widget>[
            IdeListRow(
              title: 'Selected',
              subtitle: 'Now',
              leading: Icon(Icons.chat),
              trailing: Text('3'),
              selected: true,
              dividerIndent: 20,
            ),
            IdeListRow(
              title: 'Disabled',
              enabled: false,
              showDivider: false,
            ),
            IdeListRow(title: 'Available', showDivider: false),
            IdeRowDivider(indent: 4, endIndent: 8),
            IdeColumnDivider(),
            IdeRowGroup(
              title: 'Settings',
              children: <Widget>[Text('A'), Text('B')],
            ),
            IdeRowGroup(
              title: 'Facts',
              dividers: false,
              children: <Widget>[Text('C')],
            ),
            IdeSettingsRow(
              label: 'Theme',
              description: 'Choose appearance',
              control: Text('System'),
            ),
            IdeSettingsRow(
              label: 'Flat',
              control: Text('On'),
              showDivider: false,
              padding: EdgeInsets.zero,
            ),
          ],
        ),
      ),
    );
    expect(find.text('Settings'), findsOneWidget);
    expect(find.byType(IdeRowDivider), findsNWidgets(4));
    expect(_semantics('Selected'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('settings rows stack below the responsive breakpoint', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const SizedBox(
        width: 500,
        child: IdeSettingsRow(
          label: 'Theme',
          control: Text('System'),
          showDivider: false,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('ide-settings-row-stacked')),
      findsOneWidget,
    );
  });

  testWidgets('row divider resolves directional insets in RTL', (
    tester,
  ) async {
    await tester.pumpShadcnApp(
      const Directionality(
        textDirection: TextDirection.rtl,
        child: SizedBox(
          key: ValueKey('rtl-host'),
          width: 100,
          child: IdeRowDivider(indent: 10, endIndent: 20),
        ),
      ),
    );
    final host = tester.getRect(find.byKey(const ValueKey('rtl-host')));
    final line = tester.getRect(
      find.descendant(
        of: find.byType(IdeRowDivider),
        matching: find.byType(ColoredBox),
      ),
    );
    expect(line.left - host.left, 20);
    expect(host.right - line.right, 10);
  });
}

Finder _semantics(String label) {
  return find.byWidgetPredicate(
    (widget) => widget is Semantics && widget.properties.label == label,
  );
}

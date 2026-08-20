// The test metadata parser requires a literal rather than TestTag.golden.
@Tags(['golden'])
library;

import 'package:app_ui/app_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../helpers/helpers.dart';

void main() {
  setUpAll(() {
    expect(TestTag.golden, 'golden');
  });

  for (final brightness in Brightness.values) {
    testWidgets('component gallery renders ${brightness.name}', (tester) async {
      final goldenKey = ValueKey<String>('gallery-${brightness.name}');
      await tester.pumpShadcnApp(
        _GoldenGallery(key: goldenKey),
        brightness: brightness,
        size: const Size(760, 560),
      );
      await tester.pumpAndSettle();

      await expectLater(
        find.byKey(goldenKey),
        matchesGoldenFile('goldens/app_ui_gallery_${brightness.name}.png'),
      );
    });
  }
}

final class _GoldenGallery extends StatelessWidget {
  const _GoldenGallery({super.key});

  @override
  Widget build(BuildContext context) {
    final spacing = context.appSpacing;
    return RepaintBoundary(
      child: ColoredBox(
        color: context.appColors.editor,
        child: SizedBox(
          width: 720,
          height: 520,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const IdePageHeader(
                title: 'App UI visual baseline',
                subtitle: 'Desktop semantic tokens',
                leading: IdeIconBox(Icons.widgets_outlined),
              ),
              IdeToolbar(
                child: Row(
                  children: <Widget>[
                    const IdeChip(label: 'Ready', selected: true),
                    SizedBox(width: spacing.xs),
                    const IdeChip(label: 'Draft'),
                    const Spacer(),
                    IdeIconButton(
                      icon: Icons.refresh,
                      semanticLabel: 'Refresh preview',
                      onPressed: () {},
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: spacing.pagePadding,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: <Widget>[
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            const CompactMetricBar(
                              items: <CompactMetricItem>[
                                CompactMetricItem(label: 'Tests', value: '284'),
                                CompactMetricItem(
                                  label: 'Coverage',
                                  value: '100%',
                                ),
                                CompactMetricItem(
                                  label: 'Status',
                                  value: 'Green',
                                ),
                              ],
                            ),
                            SizedBox(height: spacing.sm),
                            const IdeStatusCard(
                              tone: IdeStatusCardTone.success,
                              title: 'Migration gate passed',
                              body: Text('All hand-written lines are covered.'),
                            ),
                            SizedBox(height: spacing.sm),
                            const IdeStatusCard(
                              tone: IdeStatusCardTone.warning,
                              title: 'Manual review',
                              body: Text('Verify desktop golden output.'),
                            ),
                          ],
                        ),
                      ),
                      SizedBox(width: spacing.sm),
                      Expanded(
                        child: IdeSurface.pane(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              const IdeRowGroup(
                                title: 'DETAILS',
                                children: <Widget>[
                                  IdeKeyValueRow(
                                    label: 'Platform',
                                    value: 'Desktop',
                                  ),
                                  IdeKeyValueRow(
                                    label: 'Standard',
                                    value: 'WCAG 2.2 AA',
                                  ),
                                  IdeKeyValueRow(
                                    label: 'Motion',
                                    value: 'Reduced-safe',
                                  ),
                                ],
                              ),
                              const Spacer(),
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: <Widget>[
                                  const IdeButton(label: 'Cancel'),
                                  SizedBox(width: spacing.xs),
                                  IdeButton(
                                    label: 'Continue',
                                    variant: IdeButtonVariant.primary,
                                    onPressed: () {},
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

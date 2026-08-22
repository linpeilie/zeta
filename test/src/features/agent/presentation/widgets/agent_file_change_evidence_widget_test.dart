import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_file_change_projection.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_card.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_file_change_evidence_views.dart';

import '../../../../ui/core/ide_component_test_harness.dart';

void main() {
  testWidgets('renders replacement, written content, and unified patch', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await _pumpCards(
      tester,
      <({AgentFileChangeItemProjection item, AgentToolStatus status})>[
        (
          item: _item(
            id: 'replace',
            detail: AgentTextReplacementDetailProjection(
              beforeLines: const <String>['old'],
              afterLines: const <String>['new'],
              replaceAll: true,
            ),
          ),
          status: AgentToolStatus.completed,
        ),
        (
          item: _item(
            id: 'write-running',
            detail: AgentWrittenContentDetailProjection(
              lines: const <String>['draft'],
            ),
          ),
          status: AgentToolStatus.inProgress,
        ),
        (
          item: _item(
            id: 'write-failed',
            detail: AgentWrittenContentDetailProjection(
              lines: const <String>['attempt'],
            ),
          ),
          status: AgentToolStatus.failed,
        ),
        (
          item: _item(
            id: 'patch',
            detail: AgentUnifiedPatchDetailProjection(
              lines: const <AgentUnifiedPatchLineProjection>[
                AgentUnifiedPatchLineProjection(
                  text: '@@ -1 +1 @@',
                  kind: AgentUnifiedPatchLineKind.hunkHeader,
                ),
                AgentUnifiedPatchLineProjection(
                  text: '-old',
                  kind: AgentUnifiedPatchLineKind.removed,
                ),
                AgentUnifiedPatchLineProjection(
                  text: '+new',
                  kind: AgentUnifiedPatchLineKind.added,
                ),
              ],
            ),
          ),
          status: AgentToolStatus.completed,
        ),
      ],
      size: const Size(900, 900),
    );

    expect(find.text('替换前'), findsOneWidget);
    expect(find.text('替换后'), findsOneWidget);
    expect(find.text('写入内容 · 进行中'), findsOneWidget);
    expect(find.text('写入内容 · 失败'), findsOneWidget);
    expect(find.text('统一差异'), findsWidgets);
    expect(find.bySemanticsLabel(RegExp(r'新增，第 3 行')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp(r'删除，第 2 行')), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  testWidgets('null evidence stays collapsed and labels live-only summary', (
    tester,
  ) async {
    var toggles = 0;
    final item = _item(
      id: 'summary',
      detail: null,
      replayability: AgentFileChangeReplayability.liveOnly,
    );
    await pumpIdeComponent(
      tester,
      child: SizedBox.expand(
        child: AgentFileChangeEvidenceCard(
          item: item,
          status: AgentToolStatus.completed,
          expanded: true,
          onToggle: () => toggles += 1,
        ),
      ),
    );
    await tester.tap(
      find.byKey(agentFileChangeEvidenceKey('owner', 'summary', 'header')),
    );
    await tester.pumpAndSettle();

    expect(toggles, 0);
    expect(find.text('Provider 未提供内容证据'), findsOneWidget);
    expect(find.text('本回合实时汇总'), findsOneWidget);
    expect(
      find.byKey(agentFileChangeEvidenceKey('owner', 'summary', 'detail')),
      findsNothing,
    );
  });

  testWidgets('replacement switches exactly at 640px and keeps panel state', (
    tester,
  ) async {
    final item = _item(
      id: 'responsive',
      detail: AgentTextReplacementDetailProjection(
        beforeLines: const <String>['old'],
        afterLines: const <String>['new'],
        replaceAll: false,
      ),
    );
    await _pumpCards(
      tester,
      <({AgentFileChangeItemProjection item, AgentToolStatus status})>[
        (item: item, status: AgentToolStatus.completed),
      ],
      size: const Size(639, 700),
    );
    final before = find.byKey(
      agentFileChangeEvidenceKey('owner', 'responsive', 'panel-before'),
    );
    final after = find.byKey(
      agentFileChangeEvidenceKey('owner', 'responsive', 'panel-after'),
    );
    final beforeElement = tester.element(before);
    expect(
      tester.getTopLeft(after).dy,
      greaterThan(tester.getTopLeft(before).dy),
    );

    await tester.binding.setSurfaceSize(const Size(640, 700));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(after).dy,
      closeTo(tester.getTopLeft(before).dy, 0.1),
    );
    expect(
      tester.getTopLeft(after).dx,
      greaterThan(tester.getTopLeft(before).dx),
    );
    expect(tester.element(before), same(beforeElement));

    await tester.binding.setSurfaceSize(const Size(641, 700));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(after).dy,
      closeTo(tester.getTopLeft(before).dy, 0.1),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('2x text stays bounded and 10000th line is keyboard reachable', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final lines = List<AgentUnifiedPatchLineProjection>.generate(
      10000,
      (index) => AgentUnifiedPatchLineProjection(
        text: '+line $index',
        kind: AgentUnifiedPatchLineKind.added,
      ),
      growable: false,
    );
    final item = _item(
      id: 'large',
      path: 'lib/src/a/very/long/path/that/must/stay/bounded/file.dart',
      detail: AgentUnifiedPatchDetailProjection(lines: lines),
    );
    await _pumpCards(
      tester,
      <({AgentFileChangeItemProjection item, AgentToolStatus status})>[
        (item: item, status: AgentToolStatus.completed),
      ],
      size: const Size(639, 700),
      textScaler: const TextScaler.linear(2),
    );
    final viewport = find.byKey(
      agentFileChangeEvidenceKey('owner', 'large', 'viewport-patch'),
    );
    final mountedLines = find.byWidgetPredicate(
      (widget) =>
          widget is Semantics &&
          (widget.properties.label?.startsWith('新增，第 ') ?? false),
    );
    expect(mountedLines.evaluate().length, lessThan(80));
    expect(find.bySemanticsLabel('统一差异，可滚动，10000 行'), findsOneWidget);

    await tester.tap(viewport);
    await tester.sendKeyEvent(LogicalKeyboardKey.end);
    await tester.pumpAndSettle();
    expect(find.text('+line 9999'), findsOneWidget);
    expect(mountedLines.evaluate().length, lessThan(80));
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });
}

AgentFileChangeItemProjection _item({
  required String id,
  required AgentFileChangeDetailProjection? detail,
  String path = 'lib/example.dart',
  AgentFileChangeReplayability replayability =
      AgentFileChangeReplayability.replayable,
}) => AgentFileChangeItemProjection(
  ownerEntryId: 'owner',
  snapshotRevision: 1,
  replayability: replayability,
  changeId: id,
  path: path,
  destinationPath: null,
  kind: AgentFileChangeKind.modified,
  statistics: const AgentFileChangeLineStatistics(
    totalLines: 2,
    addedLines: 1,
    removedLines: 1,
  ),
  detail: detail,
);

Future<void> _pumpCards(
  WidgetTester tester,
  List<({AgentFileChangeItemProjection item, AgentToolStatus status})> items, {
  required Size size,
  TextScaler textScaler = TextScaler.noScaling,
}) async {
  await pumpIdeComponent(
    tester,
    size: size,
    child: MediaQuery(
      data: MediaQueryData(textScaler: textScaler),
      child: SizedBox.expand(
        child: SingleChildScrollView(
          child: Column(
            children: <Widget>[
              for (final entry in items)
                AgentFileChangeEvidenceCard(
                  item: entry.item,
                  status: entry.status,
                  expanded: true,
                  onToggle: _noop,
                ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void _noop() {}

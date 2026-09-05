import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  const groupingPath =
      'lib/src/features/agent/presentation/agent_timeline_grouping.dart';
  const contextPath =
      'lib/src/features/agent/presentation/widgets/'
      'agent_pane_context_panel.dart';
  const typedPresentationFiles = <String>[
    groupingPath,
    'lib/src/features/agent/presentation/agent_file_change_projection.dart',
    'lib/src/features/agent/presentation/'
        'agent_file_change_projection_cache.dart',
    'lib/src/features/agent/presentation/widgets/'
        'agent_file_change_evidence_card.dart',
    'lib/src/features/agent/presentation/widgets/'
        'agent_file_change_evidence_views.dart',
  ];

  group('file change presentation purity', () {
    test('typed projection files stay Provider-neutral', () {
      final providerIdentifier = RegExp(
        r'\b(codex|grok|claudeCode|cursor)\b',
        caseSensitive: false,
      );
      for (final path in typedPresentationFiles) {
        final source = File(path).readAsStringSync();
        expect(
          providerIdentifier.hasMatch(_withoutLineComments(source)),
          isFalse,
          reason: '$path must not branch on a concrete Provider',
        );
        expect(
          source,
          isNot(contains('/data/datasources/')),
          reason: '$path must not import Provider protocol adapters',
        );
      }
    });

    test('grouping does not infer file changes from raw or patch headers', () {
      final source = File(groupingPath).readAsStringSync();
      for (final forbidden in const <String>[
        '_fileEditChangesFromToolCall',
        '_fallbackFilePathsFromToolCall',
        'rawInput',
        'rawOutput',
        '.locations',
        'unified_diff',
        'diff --git',
        '*** Begin Patch',
      ]) {
        expect(
          source,
          isNot(contains(forbidden)),
          reason: '$groupingPath must not contain $forbidden',
        );
      }
      expect(source, contains('toolCall.fileChanges'));
      expect(source, contains('AgentTurnFileChangesTimelineEntry'));
    });

    test(
      'context routes edit tools through typed data and keeps raw separate',
      () {
        final source = File(contextPath).readAsStringSync();
        final typedIndex = source.indexOf(
          'final fileChanges = toolCall.fileChanges;',
        );
        final editGuardIndex = source.indexOf(
          'if (toolCall.kind == AgentToolKind.edit)',
        );
        expect(typedIndex, isNonNegative);
        expect(editGuardIndex, greaterThan(typedIndex));
        expect(source, contains('_fileChangeSnapshotContextMap'));
        expect(source, isNot(contains('_toolCallRawMap')));
        // 原文只以独立段落附在 typed 摘要之后，且 edit 工具一律不附。
        expect(source, contains("_appendRawSection(buffer, 'rawInput'"));
        expect(source, contains('if (toolCall.kind != AgentToolKind.edit) {'));
        // 摘要 map 里不得再出现原文键：那会把报文二次转义塞进 JSON。
        final summaryStart = source.indexOf(
          'Map<String, Object?> _toolCallContextMap(',
        );
        final summaryEnd = source.indexOf(
          'Map<String, Object?> _fileChangeSnapshotContextMap(',
        );
        expect(summaryStart, isNonNegative);
        expect(summaryEnd, greaterThan(summaryStart));
        final summarySource = source.substring(summaryStart, summaryEnd);
        expect(summarySource, isNot(contains('rawInput')));
        expect(summarySource, isNot(contains('rawOutput')));
      },
    );
  });
}

String _withoutLineComments(String source) {
  return source
      .split('\n')
      .where((line) {
        final trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('///');
      })
      .join('\n');
}

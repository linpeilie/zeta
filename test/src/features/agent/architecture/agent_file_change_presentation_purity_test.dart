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
      'context routes edit tools through typed data before raw fallback',
      () {
        final source = File(contextPath).readAsStringSync();
        final typedIndex = source.indexOf(
          'final fileChanges = toolCall.fileChanges;',
        );
        final editGuardIndex = source.indexOf(
          'if (toolCall.kind == AgentToolKind.edit)',
        );
        // 原文只作为 typed 证据之后的兜底诊断，且只对非 edit 工具生效。
        final rawFallbackIndex = source.indexOf(
          'if (toolCall.rawInput.isNotEmpty)',
        );

        expect(typedIndex, isNonNegative);
        expect(editGuardIndex, greaterThan(typedIndex));
        expect(rawFallbackIndex, greaterThan(editGuardIndex));
        expect(source, contains('_fileChangeSnapshotContextMap'));
        expect(source, isNot(contains('_toolCallRawMap')));
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

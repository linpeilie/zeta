import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  group('left sidebar usage architecture contracts', () {
    test('Agent 首页只保留标题栏入口与单卡片统计内容', () {
      final home = File(
        'lib/src/ui/features/ide/views/ide_home.dart',
      ).readAsStringSync();
      final usage = File(
        'lib/src/features/usage_statistics/presentation/'
        'agent_usage_panel.dart',
      ).readAsStringSync();

      expect(home, contains("'titlebar-left-sidebar-action'"));
      expect(home, contains('ProjectAgentSidebar('));
      expect(home, contains('AgentUsagePanelContent('));
      for (final legacy in const <String>[
        '_buildLeadingRail',
        '_leftTopVisible',
        '_leftBottomVisible',
        '_leftTopRatio',
        '_toggleLeftPanel',
        "'left-projects-action'",
        "'left-context-action'",
      ]) {
        expect(home, isNot(contains(legacy)), reason: legacy);
      }
      expect(usage, isNot(contains('class AgentUsagePanel ')));
      expect(usage, isNot(contains("'context-panel-card'")));
    });

    test('左栏统计不进入 G1 共享层或形成具体 Provider 分支', () {
      final files = <File>[
        for (final path in _g1ApplicationFiles) File(path),
        ...Directory(
          'lib/src/features/agent/data/mappers',
        ).listSync().whereType<File>().where((file) {
          final name = file.uri.pathSegments.last;
          return name.startsWith('acp_') && name.endsWith('.dart');
        }),
      ];

      for (final file in files) {
        final code = _stripLineComments(file.readAsStringSync());
        expect(code, isNot(contains('usage_statistics')), reason: file.path);
        expect(code, isNot(contains('AgentUsage')), reason: file.path);
        expect(
          code,
          isNot(contains('selectedAgentUsageProviderId')),
          reason: file.path,
        );
        expect(
          _concreteProviderIdentifier.hasMatch(code),
          isFalse,
          reason: '${file.path} must stay Provider-neutral',
        );
      }
    });

    test('统计选择不会改写会话 active Provider', () {
      final controller = File(
        'lib/src/features/usage_statistics/application/'
        'agent_usage_panel_controller.dart',
      ).readAsStringSync();
      final home = File(
        'lib/src/ui/features/ide/views/ide_home.dart',
      ).readAsStringSync();
      final shell = File(
        'lib/src/app/shell/ide_shell_controller.dart',
      ).readAsStringSync();

      expect(controller, isNot(contains('AgentProviderSettingsController')));
      expect(controller, isNot(contains('activeProviderId')));

      final terminalHandler = _slice(
        home,
        'void _handleAgentTurnTerminal',
        'void _requestAgentUsageRefresh',
      );
      expect(terminalHandler, contains('selectProviderFromTurn'));
      expect(terminalHandler, isNot(contains('agentProviderController')));

      final selectionSetter = _slice(
        shell,
        'void setSelectedAgentUsageProviderId',
        'bool get initialRestoreCompleted',
      );
      expect(
        selectionSetter,
        contains('copyWith(selectedAgentUsageProviderId: providerId)'),
      );
      expect(selectionSetter, isNot(contains('agentProviderController')));
      expect(selectionSetter, isNot(contains('activeProviderId')));
    });
  });
}

const _g1ApplicationFiles = <String>[
  'packages/zeta_agent_core/lib/src/application/agent_event_pipeline.dart',
  'packages/zeta_agent_core/lib/src/application/agent_event_coalescing_policy.dart',
  'packages/zeta_agent_core/lib/src/application/coalescing_event_buffer.dart',
  'packages/zeta_agent_core/lib/src/application/bounded_event_dispatcher.dart',
  'packages/zeta_agent_core/lib/src/application/agent_conversation_timeline_store.dart',
];

final _concreteProviderIdentifier = RegExp(
  r'\b(codex|grok|cursor|claudeCode)\b',
  caseSensitive: false,
);

String _stripLineComments(String source) {
  final code = StringBuffer();
  for (final line in source.split('\n')) {
    final trimmed = line.trimLeft();
    if (trimmed.startsWith('//')) {
      continue;
    }
    final commentIndex = line.indexOf('//');
    code.writeln(commentIndex < 0 ? line : line.substring(0, commentIndex));
  }
  return code.toString();
}

String _slice(String source, String startMarker, String endMarker) {
  final start = source.indexOf(startMarker);
  final end = source.indexOf(endMarker, start + startMarker.length);
  if (start < 0 || end < 0) {
    throw StateError('Missing architecture marker: $startMarker -> $endMarker');
  }
  return source.substring(start, end);
}

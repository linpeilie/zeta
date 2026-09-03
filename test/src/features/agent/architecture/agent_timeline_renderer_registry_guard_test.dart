import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/timeline_rendering/agent_timeline_renderers.dart';

/// 「新增条目类型 = 新增一个 renderer 文件 + 一行注册」的守卫。
///
/// 反射不可行，改为对源码里的密封子类做静态盘点：新增一种 entry / block 而忘了
/// 登记 renderer 时，这里会直接失败——否则要等运行时抛 UnsupportedError。
void main() {
  final registry = buildAgentTimelineRendererRegistry();
  final registered = <String>{
    for (final type in registry.registeredPayloadTypes) type.toString(),
  };

  test('每个 AgentTimelineEntry 子类都有注册 renderer', () {
    final declared = _subclassesOf(
      File(
        'packages/zeta_agent_core/lib/src/application/'
        'agent_conversation_timeline_store.dart',
      ),
      'AgentTimelineEntry',
    );

    expect(declared, isNotEmpty, reason: '源码盘点失败，检查文件路径是否漂移');
    expect(
      declared.difference(registered),
      isEmpty,
      reason: '新增 entry 类型必须在 agent_timeline_renderers.dart 里登记 renderer',
    );
  });

  test('每个 AgentTimelineRenderBlock 子类都有注册 renderer（entry 包装块除外）', () {
    final declared =
        _subclassesOf(
            File(
              'lib/src/features/agent/presentation/agent_timeline_grouping.dart',
            ),
            'AgentTimelineRenderBlock',
          )
          // 该包装块由注册表解包成 entry，不自己登记。
          ..remove('AgentTimelineEntryRenderBlock');

    expect(declared, isNotEmpty, reason: '源码盘点失败，检查文件路径是否漂移');
    expect(
      declared.difference(registered),
      isEmpty,
      reason: '新增 block 类型必须在 agent_timeline_renderers.dart 里登记 renderer',
    );
  });

  test('注册表不含多余登记', () {
    final entries = _subclassesOf(
      File(
        'packages/zeta_agent_core/lib/src/application/'
        'agent_conversation_timeline_store.dart',
      ),
      'AgentTimelineEntry',
    );
    final blocks = _subclassesOf(
      File('lib/src/features/agent/presentation/agent_timeline_grouping.dart'),
      'AgentTimelineRenderBlock',
    )..remove('AgentTimelineEntryRenderBlock');

    expect(registered.difference(entries.union(blocks)), isEmpty);
  });

  test('每种 block 的 fixture 都能解析出 renderer', () {
    final blocks = <AgentTimelineRenderBlock>[
      AgentTimelineCommandGroupRenderBlock(
        group: const AgentTimelineCommandGroup(
          id: 'g1',
          items: <AgentTimelineCommandGroupItem>[],
        ),
      ),
      AgentTimelineFileEditGroupRenderBlock(
        group: const AgentTimelineFileEditGroup(
          id: 'g2',
          items: <AgentTimelineFileEditItem>[],
        ),
      ),
      AgentTimelineEntryRenderBlock(
        entry: AgentMessageTimelineEntry(
          message: const AgentConversationMessage(
            id: 'm1',
            role: AgentMessageRole.agent,
            text: 'hi',
          ),
        ),
      ),
    ];
    for (final block in blocks) {
      expect(() => registry.resolve(block), returnsNormally);
    }
  });
}

/// 从源码里盘点 [baseName] 的具体子类名。
Set<String> _subclassesOf(File source, String baseName) {
  expect(source.existsSync(), isTrue, reason: '找不到源码文件: ${source.path}');
  final pattern = RegExp(
    r'^(?:final |base |sealed )?class (\w+) extends ' + baseName + r'\b',
    multiLine: true,
  );
  return <String>{
    for (final match in pattern.allMatches(source.readAsStringSync()))
      match.group(1)!,
  };
}

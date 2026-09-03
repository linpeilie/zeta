import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_thread_selection_patch.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';

void main() {
  group('latestAgentThreadSelectionPatch', () {
    test('空历史返回 null', () {
      expect(
        latestAgentThreadSelectionPatch(const <AgentHistoryTurn>[]),
        isNull,
      );
    });

    test('从后往前取最近带 modelId 的 turn', () {
      final patch = latestAgentThreadSelectionPatch(const [
        AgentHistoryTurn(id: 't1', modelId: 'gpt-4'),
        AgentHistoryTurn(id: 't2', modelId: 'gpt-5'),
      ]);
      expect(patch?.modelId, 'gpt-5');
    });

    test('没有 modelId 时回退到最近任意非空补丁', () {
      final patch = latestAgentThreadSelectionPatch(const [
        AgentHistoryTurn(id: 't1', modelId: '  '),
        AgentHistoryTurn(
          id: 't2',
          reasoningEffort: AgentHistoryReasoningEffort.explicit('high'),
        ),
      ]);
      expect(patch?.modelId, isNull);
      expect(patch?.reasoningEffort, 'high');
    });
  });

  group('agentThreadSelectionPatchFromHistoryTurn', () {
    test('null turn 返回 null', () {
      expect(agentThreadSelectionPatchFromHistoryTurn(null), isNull);
    });

    test('投影 modelId / 推理 / 档位 / Fast', () {
      const turn = AgentHistoryTurn(
        id: 't1',
        modelId: ' gpt-5 ',
        reasoningEffort: AgentHistoryReasoningEffort.explicit('high'),
        serviceTierId: 'flex',
        explicitFast: true,
      );
      final patch = agentThreadSelectionPatchFromHistoryTurn(turn);
      expect(patch?.modelId, 'gpt-5');
      expect(patch?.reasoningEffort, 'high');
      expect(patch?.serviceTierId, 'flex');
      expect(patch?.fastEnabled, isTrue);
    });

    test('仅空白 modelId 且其余未知时返回 null', () {
      expect(
        agentThreadSelectionPatchFromHistoryTurn(
          const AgentHistoryTurn(id: 't1', modelId: '  '),
        ),
        isNull,
      );
    });
  });

  group('mergeAgentThreadSelectionPatches', () {
    test('双方都为空返回 null', () {
      expect(mergeAgentThreadSelectionPatches(null, null), isNull);
    });

    test('overlay 非空 modelId 覆盖 base，unset 字段保留 base', () {
      const base = AgentThreadSelectionPatch(
        modelId: 'gpt-4',
        reasoningEffort: 'medium',
      );
      const overlay = AgentThreadSelectionPatch(modelId: 'gpt-5');
      final merged = mergeAgentThreadSelectionPatches(base, overlay);
      expect(merged?.modelId, 'gpt-5');
      expect(merged?.reasoningEffort, 'medium');
      expect(
        identical(merged?.serviceTierId, kAgentThreadSelectionUnset),
        isTrue,
      );
    });

    test('overlay 空白 modelId 不覆盖；显式 null 清空推理', () {
      const base = AgentThreadSelectionPatch(
        modelId: 'gpt-4',
        reasoningEffort: 'high',
      );
      const overlay = AgentThreadSelectionPatch(
        modelId: '  ',
        reasoningEffort: null,
      );
      final merged = mergeAgentThreadSelectionPatches(base, overlay);
      expect(merged?.modelId, 'gpt-4');
      expect(merged?.reasoningEffort, isNull);
    });
  });
}

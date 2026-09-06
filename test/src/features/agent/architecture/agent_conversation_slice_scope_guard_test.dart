import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// 切片 effect 必须是 scope-aware 的（G3 / 目标架构 §6.2）。
///
/// 这条守卫存在的理由很具体：Phase 2 文档 §4.3 一度声明"切片 effect 沿用内核那套
/// scope 校验"，而代码里的 runner 一次校验都没有——**文档断言没有守卫**，所以
/// analyze 与全量测试都发现不了。这里把断言变成可证伪的。
void main() {
  const effectPath =
      'lib/src/features/agent/application/conversation_slice/'
      'agent_conversation_command_payload.dart';
  const runnerPath =
      'lib/src/features/agent/application/conversation_slice/'
      'agent_conversation_command_effect_runner.dart';
  const scopePath =
      'lib/src/features/agent/application/conversation_slice/'
      'agent_conversation_command_scope.dart';

  test('命令 effect 必须携带作用域快照', () {
    final source = File(effectPath).readAsStringSync();

    expect(
      source,
      contains('const AgentConversationCommandEnvelope({'),
      reason: '找不到命令信封，守卫的锚点失效了',
    );
    expect(
      source,
      contains('final AgentConversationCommandScope scope;'),
      reason:
          '命令 effect 只带 OperationId 是不够的：id 只能回答"是不是同一次操作"，'
          '回答不了"这次操作所属的 Binding / runtime 还在不在"',
    );
  });

  test('runner 在执行前与回写前各校验一次', () {
    final source = File(runnerPath).readAsStringSync();

    expect(
      source,
      contains('matchesForExecution'),
      reason: '缺少执行前校验：世界已经换代就不该再打这一枪',
    );
    expect(
      source,
      contains('matchesForCommit'),
      reason: 'await 期间 Provider 可能重启，结果回写前必须再校验一次',
    );

    final body = source.substring(source.indexOf('Future<void> _runAsync('));
    final executionIndex = body.indexOf('_canExecute(e)');
    final invokeIndex = body.indexOf('await _invokeAsync(');
    final commitIndex = body.indexOf('_canCommit(e)');
    expect(executionIndex, isNonNegative);
    expect(invokeIndex, greaterThan(executionIndex), reason: '执行前校验必须在调用之前');
    expect(commitIndex, greaterThan(invokeIndex), reason: '回写前校验必须在调用之后');
  });

  test('作用域比对覆盖 Binding / runtime / epoch / thread 四个维度', () {
    final source = File(scopePath).readAsStringSync();

    for (final dimension in const <String>[
      'bindingKey',
      'runtimeId',
      'connectionEpoch',
      'listenerGeneration',
      'threadId',
    ]) {
      expect(source, contains('final '), reason: '守卫锚点失效');
      expect(
        source.contains(dimension),
        isTrue,
        reason: '作用域快照缺少 $dimension 维度',
      );
    }
  });
}

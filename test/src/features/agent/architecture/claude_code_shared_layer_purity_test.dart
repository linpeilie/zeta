import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Claude Code 接入期间的共享层纯度守卫（G1 / G2）。
///
/// 共享适配层不得出现 Claude Code 路径或标识符；`AgentProviderBundle` 不得为
/// Claude Code 新增 `AgentProviderKind` 分支；G1 五文件内容冻结（T18）。
void main() {
  /// G1 范围内的共享机制层文件（不含 Provider 自有 adapter）。
  ///
  /// 与 `AGENTS.md` G1 列表对齐：Pipeline / CoalescingPolicy / Buffer /
  /// Dispatcher / TimelineStore，外加 capability 端口装配的 `AgentProviderBundle`
  /// （禁止按 kind 分支）。
  const sharedLayerFiles = <String>[
    'lib/src/features/agent/application/agent_event_pipeline.dart',
    'lib/src/features/agent/application/agent_event_coalescing_policy.dart',
    'lib/src/features/agent/application/coalescing_event_buffer.dart',
    'lib/src/features/agent/application/bounded_event_dispatcher.dart',
    'lib/src/features/agent/application/agent_conversation_timeline_store.dart',
    'lib/src/features/agent/domain/agent_provider_bundle.dart',
  ];

  /// T18：G1 五文件内容基线（lineCount + 规范化 byteLength + FNV-1a 指纹）。
  ///
  /// 接入 Claude Code 期间这些文件必须 `git diff` 为空；若实现不得不改共享层，
  /// 必须先停线取得明确批准并记录边界，批准后才能更新本基线。长度与指纹统一按
  /// LF 计算，避免不同平台的 checkout 行尾让守卫误报。
  /// TimelineStore 基线已按 2026-08-17 多语言步骤 12（其余 context-free
  /// 文案改走 `AgentUiTextCatalog`）刷新。
  const g1ContentBaselines = <String, _FileBaseline>{
    'lib/src/features/agent/application/agent_event_pipeline.dart':
        _FileBaseline(
          lineCount: 349,
          byteLength: 11823,
          fingerprint: '77d81121c8b9d9fd',
        ),
    'lib/src/features/agent/application/agent_event_coalescing_policy.dart':
        _FileBaseline(
          lineCount: 143,
          byteLength: 4569,
          fingerprint: '53fcea25bd7a52d0',
        ),
    'lib/src/features/agent/application/coalescing_event_buffer.dart':
        _FileBaseline(
          lineCount: 163,
          byteLength: 4407,
          fingerprint: '82eff5df2bcc5047',
        ),
    'lib/src/features/agent/application/bounded_event_dispatcher.dart':
        _FileBaseline(
          lineCount: 183,
          byteLength: 4779,
          fingerprint: 'fbbeb5ecb3de50e3',
        ),
    'lib/src/features/agent/application/agent_conversation_timeline_store.dart':
        _FileBaseline(
          lineCount: 2017,
          byteLength: 67491,
          fingerprint: '9a129dfe302117a4',
        ),
  };

  const bundlePath = 'lib/src/features/agent/domain/agent_provider_bundle.dart';

  /// 基线：bundle 当前不出现 `AgentProviderKind`（端口装配只靠 interface/`is`）。
  /// 接入 Claude Code 后此计数仍须保持；若上升说明有人加了 kind 分支。
  const expectedAgentProviderKindMentionsInBundle = 0;

  String stripLineComments(String source) {
    final out = StringBuffer();
    for (final line in source.split('\n')) {
      final trimmed = line.trimLeft();
      if (trimmed.startsWith('//') || trimmed.startsWith('///')) {
        continue;
      }
      final commentIndex = line.indexOf('//');
      if (commentIndex >= 0) {
        // 粗略去掉行尾注释；字符串内含 // 的假阳性在本守卫里可接受。
        out.writeln(line.substring(0, commentIndex));
      } else {
        out.writeln(line);
      }
    }
    return out.toString();
  }

  group('claude code shared layer purity', () {
    test('G1 shared files do not import claude_code paths', () {
      for (final path in sharedLayerFiles) {
        final file = File(path);
        expect(file.existsSync(), isTrue, reason: 'missing $path');
        final source = file.readAsStringSync();
        expect(
          source,
          isNot(contains('claude_code')),
          reason: '$path must not reference claude_code paths',
        );
        expect(
          source,
          isNot(contains('datasources/claude_code')),
          reason: '$path must not import datasources/claude_code',
        );
      }
    });

    test('G1 shared files do not contain claudeCode identifiers '
        '(comments excluded)', () {
      final identifier = RegExp(r'claudeCode');
      for (final path in sharedLayerFiles) {
        final codeOnly = stripLineComments(File(path).readAsStringSync());
        expect(
          identifier.hasMatch(codeOnly),
          isFalse,
          reason: '$path must not contain claudeCode (comments excluded)',
        );
      }
    });

    test('agent_provider_bundle keeps AgentProviderKind mention baseline', () {
      final source = File(bundlePath).readAsStringSync();
      final mentions = RegExp(r'AgentProviderKind').allMatches(source).length;
      expect(
        mentions,
        expectedAgentProviderKindMentionsInBundle,
        reason:
            'AgentProviderBundle must not grow AgentProviderKind branches; '
            'baseline=$expectedAgentProviderKindMentionsInBundle actual=$mentions',
      );
    });

    test('content baseline normalizes platform line endings', () {
      final lf = utf8.encode('first\nsecond\n');
      final crlf = utf8.encode('first\r\nsecond\r\n');
      final cr = utf8.encode('first\rsecond\r');

      expect(_normalizedUtf8Bytes(crlf), lf);
      expect(_normalizedUtf8Bytes(cr), lf);
    });

    test('G1 five application files keep frozen content baseline (T18)', () {
      for (final entry in g1ContentBaselines.entries) {
        final path = entry.key;
        final expected = entry.value;
        final bytes = _normalizedUtf8Bytes(File(path).readAsBytesSync());
        final source = utf8.decode(bytes);
        final lineCount = const LineSplitter().convert(source).length;
        final fingerprint = _fingerprintHex(bytes);
        expect(
          lineCount,
          expected.lineCount,
          reason: '$path lineCount drift (shared layer must not change)',
        );
        expect(
          bytes.length,
          expected.byteLength,
          reason: '$path byteLength drift (shared layer must not change)',
        );
        expect(
          fingerprint,
          expected.fingerprint,
          reason:
              '$path content fingerprint drift — Claude Code must not modify '
              'G1 shared application files (see AGENTS.md G1)',
        );
      }
    });
  });
}

List<int> _normalizedUtf8Bytes(List<int> bytes) {
  final source = utf8.decode(bytes);
  return utf8.encode(source.replaceAll('\r\n', '\n').replaceAll('\r', '\n'));
}

final class _FileBaseline {
  const _FileBaseline({
    required this.lineCount,
    required this.byteLength,
    required this.fingerprint,
  });

  final int lineCount;
  final int byteLength;
  final String fingerprint;
}

/// FNV-1a 64-bit fingerprint for freeze checks (not cryptographic).
String _fingerprintHex(List<int> bytes) {
  var hash = BigInt.parse('cbf29ce484222325', radix: 16);
  final prime = BigInt.parse('100000001b3', radix: 16);
  final mask = (BigInt.one << 64) - BigInt.one;
  for (final b in bytes) {
    hash = ((hash ^ BigInt.from(b)) * prime) & mask;
  }
  return hash.toRadixString(16).padLeft(16, '0');
}

import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';
import 'composer_document.dart';

/// Widget 卸载期间保留的内存草稿；不包含焦点、popover、IME composing 或 runtime。
final class AgentPaneRetainedState {
  AgentPaneRetainedState({
    required this.document,
    required this.imagePaths,
    required this.stagedPaths,
    required this.scrollMetrics,
    required this.freeScroll,
  });
  final ComposerDocumentSnapshot document;
  final List<String> imagePaths;
  final List<String> stagedPaths;
  final IdeVirtualScrollMetricsSnapshot? scrollMetrics;
  final bool freeScroll;
}

/// 弱身份存储不延长 entry 的寿命；entry 关闭后拒绝旧 Widget 的迟到写回。
final class AgentPaneRetention {
  AgentPaneRetention(this.discard);
  final Future<void> Function(List<String>) discard;
  final _states = Expando<AgentPaneRetainedState>();
  final _closed = Expando<bool>();
  bool accepts(Object identity) => _closed[identity] != true;
  AgentPaneRetainedState? take(Object identity) {
    final result = _states[identity];
    _states[identity] = null;
    return result;
  }

  void save(Object identity, AgentPaneRetainedState state) {
    if (accepts(identity)) _states[identity] = state;
  }

  Future<void> closeEntry(Object identity) async {
    _closed[identity] = true;
    final previous = take(identity);
    if (previous != null && previous.stagedPaths.isNotEmpty) {
      await discard(previous.stagedPaths);
    }
  }
}

final agentPaneRetentionProvider = Provider<AgentPaneRetention>(
  (ref) => AgentPaneRetention(
    (paths) => ref.read(agentComposerAttachmentPortProvider).discard(paths),
  ),
);

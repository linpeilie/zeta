import 'package:flutter/material.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';

/// 会话正文 Markdown：经 [AgentMarkdownCache] 复用控制器，支持流式增量。
class AgentMarkdownBody extends StatefulWidget {
  const AgentMarkdownBody({
    required this.message,
    required this.useStreamingMarkdown,
    required this.markdownCache,
    this.themeBuilder,
    super.key,
  });

  final AgentConversationMessage message;
  final bool useStreamingMarkdown;
  final AgentMarkdownCache markdownCache;

  /// 可选的主题构造器；缺省使用 Agent 正文主题。
  final MarkdownThemeData Function(BuildContext context)? themeBuilder;

  @override
  State<AgentMarkdownBody> createState() => _AgentMarkdownBodyState();
}

class _AgentMarkdownBodyState extends State<AgentMarkdownBody> {
  late AgentMarkdownCacheLease _lease;
  bool _streamCommitted = false;

  @override
  void initState() {
    super.initState();
    _attachLease();
    _syncMarkdownController();
  }

  @override
  void didUpdateWidget(covariant AgentMarkdownBody oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.markdownCache != widget.markdownCache ||
        oldWidget.message.id != widget.message.id) {
      _detachLease();
      _attachLease();
    }
    _syncMarkdownController();
  }

  void _attachLease() {
    final lease = widget.markdownCache.acquire(
      messageId: widget.message.id,
      data: widget.message.text,
      preferIncrementalUpdate: widget.useStreamingMarkdown,
    );
    _lease = lease;
  }

  void _detachLease() {
    _lease.release();
    _streamCommitted = false;
  }

  void _syncMarkdownController() {
    final lease = _lease;
    final nextText = widget.message.text;
    if (lease.controller.data != nextText) {
      lease.updateData(
        nextText,
        preferIncrementalUpdate: widget.useStreamingMarkdown,
      );
      _streamCommitted = false;
    }

    final isCompleted = widget.message.status == AgentMessageStatus.completed;
    if (isCompleted && !_streamCommitted) {
      lease.controller.commitStream();
      _streamCommitted = true;
    } else if (!isCompleted) {
      _streamCommitted = false;
    }
  }

  @override
  void dispose() {
    _detachLease();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // mixin_markdown 对普通文本使用 MouseCursor.defer，桌面端默认仍是箭头；
    // 外层声明 text 光标，链接仍会用包内 click 覆盖。
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: MarkdownWidget(
        controller: _lease.controller,
        theme: (widget.themeBuilder ?? agentMarkdownTheme)(context),
        useColumn: true,
        selectable: true,
        padding: EdgeInsets.zero,
        enableCopyFullDocumentShortcut: false,
        showCopyAllInContextMenu: false,
        // 包无 enableContextMenu 开关；返回空组件以完全不显示右键菜单。
        contextMenuBuilder: _suppressMarkdownContextMenu,
      ),
    );
  }
}

/// 非时间线消息使用的轻量 Markdown 渲染，不进入历史消息保温缓存。
class AgentRawMarkdownBody extends StatelessWidget {
  const AgentRawMarkdownBody({required this.data, super.key});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: MarkdownWidget(
        data: data,
        theme: agentMarkdownTheme(context),
        useColumn: true,
        selectable: true,
        padding: EdgeInsets.zero,
        enableCopyFullDocumentShortcut: false,
        showCopyAllInContextMenu: false,
        contextMenuBuilder: _suppressMarkdownContextMenu,
      ),
    );
  }
}

/// 抑制 mixin_markdown 右键菜单：仍会走 show，但不渲染任何菜单项。
Widget _suppressMarkdownContextMenu(
  BuildContext context,
  MarkdownSelectionController selectionController,
  List<ContextMenuButtonItem> buttonItems,
  TextSelectionToolbarAnchors anchors,
) {
  return const SizedBox.shrink();
}

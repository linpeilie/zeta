import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:zeta_markdown/zeta_markdown.dart';

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/agent_markdown_cache.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_code_block_toolbar.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_styles.dart';
import 'package:zeta/src/ui/core/system_url_opener.dart';

/// 会话正文 Markdown：经 [AgentMarkdownCache] 复用控制器，支持流式增量。
class AgentMarkdownBody extends ConsumerStatefulWidget {
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
  ConsumerState<AgentMarkdownBody> createState() => _AgentMarkdownBodyState();
}

class _AgentMarkdownBodyState extends ConsumerState<AgentMarkdownBody> {
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
    // zeta_markdown 对普通文本使用 MouseCursor.defer，桌面端默认仍是箭头；
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
        // 必须传稳定引用：MarkdownDocumentView.didUpdateWidget 按引用比较
        // onTapLink，不等就清空整份 block 行缓存，而 block 的 GlobalKey 仍被
        // 复用——每帧重建一次会把渲染对象在帧中拆装，直接炸布局断言。
        onTapLink: _handleTapLink,
        codeBlockToolbarBuilder: agentCodeBlockToolbar,
      ),
    );
  }

  void _handleTapLink(String destination, String? title, String label) {
    openAgentMarkdownLink(ref, destination);
  }
}

/// 非时间线消息使用的轻量 Markdown 渲染，不进入历史消息保温缓存。
class AgentRawMarkdownBody extends ConsumerStatefulWidget {
  const AgentRawMarkdownBody({required this.data, super.key});

  final String data;

  @override
  ConsumerState<AgentRawMarkdownBody> createState() =>
      _AgentRawMarkdownBodyState();
}

class _AgentRawMarkdownBodyState extends ConsumerState<AgentRawMarkdownBody> {
  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.text,
      child: MarkdownWidget(
        data: widget.data,
        theme: agentMarkdownTheme(context),
        useColumn: true,
        selectable: true,
        padding: EdgeInsets.zero,
        enableCopyFullDocumentShortcut: false,
        showCopyAllInContextMenu: false,
        contextMenuBuilder: _suppressMarkdownContextMenu,
        // 同上：稳定引用，别在这里写闭包。
        onTapLink: _handleTapLink,
        codeBlockToolbarBuilder: agentCodeBlockToolbar,
      ),
    );
  }

  void _handleTapLink(String destination, String? title, String label) {
    openAgentMarkdownLink(ref, destination);
  }
}

/// 把正文里点中的外链交给系统浏览器。
///
/// 打开器只在点击时解析：从不点链接的用例不会碰到 fail-closed 的 provider。
/// 非 http(s) 由打开器自身拒绝，这里不做二次判断，避免两处白名单漂移。
void openAgentMarkdownLink(WidgetRef ref, String destination) {
  unawaited(ref.read(systemUrlOpenerProvider).openUrl(destination));
}

/// 抑制 zeta_markdown 右键菜单：仍会走 show，但不渲染任何菜单项。
Widget _suppressMarkdownContextMenu(
  BuildContext context,
  MarkdownSelectionController selectionController,
  List<ContextMenuButtonItem> buttonItems,
  TextSelectionToolbarAnchors anchors,
) {
  return const SizedBox.shrink();
}

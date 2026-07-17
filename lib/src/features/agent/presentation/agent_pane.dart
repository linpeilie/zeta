import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_highlight/flutter_highlight.dart';
import 'package:mixin_markdown_widget/mixin_markdown_widget.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta/src/ui/core/ide_tabs.dart';
import 'package:zeta/src/ui/core/ide_collapsible_card.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_context_menu.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_motion.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_popover.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/surfaces/ide_surface.dart';
import 'package:zeta/src/features/agent/presentation/agent_conversation_view_model.dart';
import 'package:zeta/src/features/agent/presentation/agent_timeline_grouping.dart';
import 'package:zeta/src/features/agent/presentation/model_config_ui_state.dart';

part 'widgets/agent_pane_cards.dart';
part 'widgets/agent_pane_composer.dart';
part 'widgets/agent_pane_context_panel.dart';
part 'widgets/agent_pane_header.dart';
part 'widgets/agent_pane_messages.dart';
part 'widgets/agent_model_config.dart';
part 'widgets/agent_pane_sections.dart';
part 'widgets/agent_pane_styles.dart';

const int _markdownCollapseLineThreshold = 12;
const int _markdownCollapseLengthThreshold = 420;
const int _diffPreviewLineCount = 24;

typedef _TurnSectionBuilder = Widget Function(AgentConversationTurnGroup turn);

/// 中间 Agent 面板。
///
/// 当前文件只保留页面壳、滚动协作与组合关系；实际 header、timeline、
/// composer 以及各类卡片都已拆到独立组件文件。
class AgentPane extends StatefulWidget {
  const AgentPane({required this.viewModel, super.key});

  final AgentConversationViewModel viewModel;

  @override
  State<AgentPane> createState() => _AgentPaneState();
}

class _AgentPaneState extends State<AgentPane> {
  static const double _autoScrollBottomThreshold = 48;
  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  );

  final TextEditingController _inputController = TextEditingController();
  final FocusNode _composerFocusNode = FocusNode();
  final ScrollController _scrollController = ScrollController();
  final ValueNotifier<bool> _canSendNotifier = ValueNotifier<bool>(false);
  final List<String> _draftImagePaths = <String>[];
  final List<({String name, String path})> _draftMentions =
      <({String name, String path})>[];
  bool _stickToBottom = true;
  late int _lastAutoScrollTick;

  @override
  void initState() {
    super.initState();
    _inputController.addListener(_handleInputChanged);
    _scrollController.addListener(_handleScrollChanged);
    _lastAutoScrollTick = widget.viewModel.autoScrollTick;
    widget.viewModel.autoScrollTickListenable.addListener(
      _handleAutoScrollTickChanged,
    );
  }

  @override
  void didUpdateWidget(covariant AgentPane oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewModel == widget.viewModel) {
      return;
    }
    oldWidget.viewModel.autoScrollTickListenable.removeListener(
      _handleAutoScrollTickChanged,
    );
    _stickToBottom = true;
    _lastAutoScrollTick = widget.viewModel.autoScrollTick;
    widget.viewModel.autoScrollTickListenable.addListener(
      _handleAutoScrollTickChanged,
    );
  }

  @override
  void dispose() {
    widget.viewModel.autoScrollTickListenable.removeListener(
      _handleAutoScrollTickChanged,
    );
    _inputController.removeListener(_handleInputChanged);
    _scrollController.removeListener(_handleScrollChanged);
    _inputController.dispose();
    _composerFocusNode.dispose();
    _scrollController.dispose();
    _canSendNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return IdeSurface.canvas(
      key: const ValueKey('agent-canvas'),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final pagePadding =
                    constraints.maxWidth < IdeMetrics.stackedRowBreakpoint
                    ? IdeSpacing.pagePaddingCompact
                    : IdeSpacing.pagePadding;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _AgentContentAlign(
                      child: Padding(
                        padding: pagePadding,
                        child: ListenableBuilder(
                          listenable: widget.viewModel.headerVersionListenable,
                          builder: (context, _) {
                            return _AgentHeader(viewModel: widget.viewModel);
                          },
                        ),
                      ),
                    ),
                    Expanded(
                      child: ListenableBuilder(
                        listenable: Listenable.merge(<Listenable>[
                          widget.viewModel.historyVersionListenable,
                          widget.viewModel.liveTurnListenable,
                        ]),
                        builder: (context, _) {
                          final hasConversation =
                              widget.viewModel.visibleHistoryTurns.isNotEmpty ||
                              widget.viewModel.liveTurnState != null;
                          return _AgentConversationLayout(
                            hasConversation: hasConversation,
                            reduceMotion: MediaQuery.disableAnimationsOf(
                              context,
                            ),
                            timeline: _AgentConversationTimeline(
                              viewModel: widget.viewModel,
                              scrollController: _scrollController,
                              pagePadding: pagePadding,
                              onLoadOlder: _loadOlderTurns,
                              buildTurnSection: _buildTurnSection,
                            ),
                            footer: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                // 阻塞交互始终固定在输入框上方，并沿用原最大高度。
                                _AgentPendingInteractionSection(
                                  viewModel: widget.viewModel,
                                  panelHeight: constraints.maxHeight,
                                  pagePadding: pagePadding,
                                ),
                                ListenableBuilder(
                                  listenable: widget
                                      .viewModel
                                      .composerVersionListenable,
                                  builder: (context, _) {
                                    return Column(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment:
                                          CrossAxisAlignment.stretch,
                                      children: [
                                        if (widget
                                                .viewModel
                                                .unavailableProviderReason
                                            case final reason?)
                                          _AgentProviderUnavailableNotice(
                                            reason: reason,
                                            pagePadding: pagePadding,
                                          ),
                                        if (widget.viewModel.isReadOnly)
                                          _AgentReadOnlyNotice(
                                            pagePadding: pagePadding,
                                          )
                                        else
                                          _AgentComposerSection(
                                            key: const ValueKey(
                                              'agent-composer-section',
                                            ),
                                            viewModel: widget.viewModel,
                                            inputController: _inputController,
                                            composerFocusNode:
                                                _composerFocusNode,
                                            canSendListenable: _canSendNotifier,
                                            draftImagePaths:
                                                List<String>.unmodifiable(
                                                  _draftImagePaths,
                                                ),
                                            pagePadding: pagePadding,
                                            onAttachImages: _pickImages,
                                            onRemoveImage: _removeDraftImage,
                                            onPasteImages:
                                                _pasteImagesFromClipboard,
                                            onSend: _sendMessage,
                                            onInsertMention: _insertMention,
                                          ),
                                      ],
                                    );
                                  },
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          // 头栏「上下文」菜单触发的详情面板，默认隐藏。
          ValueListenableBuilder<bool>(
            valueListenable: widget.viewModel.contextPanelVisible,
            builder: (context, visible, _) {
              if (!visible) {
                return const SizedBox.shrink();
              }
              return _AgentContextPanel(viewModel: widget.viewModel);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTurnSection(AgentConversationTurnGroup turn) {
    return _AgentTurnSection(
      key: ValueKey<String>('turn-${turn.id}'),
      turn: turn,
      viewModel: widget.viewModel,
    );
  }

  void _handleInputChanged() {
    _syncCanSend();
  }

  void _syncCanSend() {
    final canSend =
        _inputController.text.trim().isNotEmpty || _draftImagePaths.isNotEmpty;
    if (canSend == _canSendNotifier.value) {
      return;
    }
    _canSendNotifier.value = canSend;
  }

  Future<void> _pickImages() async {
    if (!widget.viewModel.canAttachImages) {
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_imageTypeGroup],
    );
    if (files.isEmpty || !mounted) {
      return;
    }
    _addDraftImages(files.map((file) => file.path));
  }

  /// Ctrl/Cmd+V：优先粘贴剪贴板图片；无图时回退插入纯文本。
  Future<bool> _pasteImagesFromClipboard() async {
    if (widget.viewModel.canAttachImages) {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final path = await _persistClipboardImage(imageBytes);
        if (!mounted) {
          return true;
        }
        _addDraftImages(<String>[path]);
        return true;
      }

      final files = await Pasteboard.files();
      final imagePaths = files
          .where(_looksLikeImagePath)
          .toList(growable: false);
      if (imagePaths.isNotEmpty) {
        if (!mounted) {
          return true;
        }
        _addDraftImages(imagePaths);
        return true;
      }
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !mounted) {
      return false;
    }
    final selection = _inputController.selection;
    final value = _inputController.text;
    final start = selection.isValid ? selection.start : value.length;
    final end = selection.isValid ? selection.end : value.length;
    final next = value.replaceRange(start, end, text);
    _inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    return true;
  }

  void _addDraftImages(Iterable<String> paths) {
    var changed = false;
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || _draftImagePaths.contains(trimmed)) {
        continue;
      }
      _draftImagePaths.add(trimmed);
      changed = true;
    }
    if (!changed) {
      return;
    }
    setState(() {});
    _syncCanSend();
  }

  void _removeDraftImage(String path) {
    if (!_draftImagePaths.remove(path)) {
      return;
    }
    setState(() {});
    _syncCanSend();
  }

  Future<String> _persistClipboardImage(Uint8List bytes) async {
    final root = Directory(
      '${Directory.systemTemp.path}${Platform.pathSeparator}zeta-agent-images',
    );
    await root.create(recursive: true);
    final file = File(
      '${root.path}${Platform.pathSeparator}'
      'paste-${DateTime.now().microsecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }

  bool _looksLikeImagePath(String path) {
    final lower = path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.gif') ||
        lower.endsWith('.webp') ||
        lower.endsWith('.bmp');
  }

  void _loadOlderTurns() {
    if (!widget.viewModel.hasOlderTurns) {
      return;
    }
    final controller = _scrollController;
    final hasClients = controller.hasClients;
    final oldPixels = hasClients ? controller.position.pixels : 0.0;
    final oldMaxScrollExtent = hasClients
        ? controller.position.maxScrollExtent
        : 0.0;
    final changed = widget.viewModel.loadOlderTurns();
    if (!changed || !hasClients) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!controller.hasClients) {
        return;
      }
      final delta = controller.position.maxScrollExtent - oldMaxScrollExtent;
      final targetOffset = (oldPixels + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );
      controller.jumpTo(targetOffset);
    });
  }

  void _sendMessage() {
    if (!_canSendNotifier.value || !widget.viewModel.canSubmitMessage) {
      return;
    }
    final text = _inputController.text;
    final images = List<String>.from(_draftImagePaths);
    final mentions = List<({String name, String path})>.from(_draftMentions);
    if (text.trim().isEmpty && images.isEmpty && mentions.isEmpty) {
      return;
    }
    _inputController.clear();
    if (_draftImagePaths.isNotEmpty || _draftMentions.isNotEmpty) {
      setState(() {
        _draftImagePaths.clear();
        _draftMentions.clear();
      });
    }
    _syncCanSend();
    widget.viewModel.sendMessage(
      text,
      localImagePaths: images,
      mentions: mentions,
    );
  }

  /// 从工作区文件列表插入 @mention。
  void _insertMention(WorkspaceNode file) {
    if (!widget.viewModel.canMentionResources) {
      return;
    }
    final mention = (name: file.name, path: file.path);
    final text = _inputController.text;
    final selection = _inputController.selection;
    final atIndex = text.lastIndexOf(
      '@',
      selection.start > 0 ? selection.start - 1 : 0,
    );
    String nextText;
    int cursor;
    if (atIndex >= 0 &&
        (atIndex == 0 || text[atIndex - 1].trim().isEmpty) &&
        !text
            .substring(atIndex + 1, selection.start.clamp(0, text.length))
            .contains(' ')) {
      // 替换当前 @query 片段。
      nextText =
          '${text.substring(0, atIndex)}@${file.name} ${text.substring(selection.start.clamp(0, text.length))}';
      cursor = atIndex + file.name.length + 2;
    } else {
      final insertAt = selection.start.clamp(0, text.length);
      nextText =
          '${text.substring(0, insertAt)}@${file.name} ${text.substring(insertAt)}';
      cursor = insertAt + file.name.length + 2;
    }
    _inputController
      ..text = nextText
      ..selection = TextSelection.collapsed(offset: cursor);
    setState(() {
      if (!_draftMentions.any((item) => item.path == file.path)) {
        _draftMentions.add(mention);
      }
    });
    _syncCanSend();
  }

  void _handleAutoScrollTickChanged() {
    final nextTick = widget.viewModel.autoScrollTick;
    if (nextTick == _lastAutoScrollTick) {
      return;
    }
    final shouldScrollToEnd = _shouldStickToBottom();
    _lastAutoScrollTick = nextTick;
    if (shouldScrollToEnd) {
      _scrollToEnd();
    }
  }

  void _handleScrollChanged() {
    _stickToBottom = _shouldStickToBottom();
  }

  bool _shouldStickToBottom() {
    if (!_scrollController.hasClients) {
      return _stickToBottom;
    }
    return _distanceToBottom() <= _autoScrollBottomThreshold;
  }

  double _distanceToBottom() {
    final position = _scrollController.position;
    return position.maxScrollExtent - position.pixels;
  }

  void _scrollToEnd() {
    // 新消息/工具卡出现后自动滚到底部，但不阻塞当前 build。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) {
        return;
      }
      if (MediaQuery.disableAnimationsOf(context)) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        return;
      }
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
      );
    });
  }
}

class _AgentProviderUnavailableNotice extends StatelessWidget {
  const _AgentProviderUnavailableNotice({
    required this.reason,
    required this.pagePadding,
  });

  final String reason;
  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: IdeStatusCard(
          key: const ValueKey('agent-provider-unavailable-notice'),
          tone: IdeStatusCardTone.warning,
          title: 'Cursor Agent unavailable',
          margin: EdgeInsets.zero,
          body: Text(
            reason,
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

class _AgentReadOnlyNotice extends StatelessWidget {
  const _AgentReadOnlyNotice({required this.pagePadding});

  final EdgeInsets pagePadding;

  @override
  Widget build(BuildContext context) {
    final textStyles = IdeTextStyles.of(context);
    final colors = IdeColors.of(context);
    return _AgentContentAlign(
      child: Padding(
        padding: pagePadding.copyWith(top: IdeSpacing.space8),
        child: IdeStatusCard(
          key: const ValueKey('agent-read-only-notice'),
          tone: IdeStatusCardTone.warning,
          title: '此会话为只读模式',
          margin: EdgeInsets.zero,
          body: Text(
            '该会话所属的 Agent 已被禁用。你仍可查看历史数据，但不能继续发送消息。',
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
      ),
    );
  }
}

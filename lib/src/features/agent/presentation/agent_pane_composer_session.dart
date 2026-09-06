import 'dart:async';
import 'agent_pane_retention.dart';
import 'dart:math' as math;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:flutter/services.dart';
import 'package:pasteboard/pasteboard.dart';

import 'package:zeta/src/features/agent/application/agent_composer_attachment_port.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';
import 'package:zeta/src/features/workspace/domain/workspace_node.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_runtime_controller.dart';
import 'package:zeta/src/features/agent/presentation/composer_document.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_mention_file_picker.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_skill_picker.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_slash_command_picker.dart';

/// Composer 提交回调：由壳把文本交给会话命令面。
typedef AgentPaneSubmitMessage =
    void Function(
      String text, {
      required List<String> localImagePaths,
      required List<({String name, String path})> mentions,
      required List<AgentSkillRef> skills,
    });

/// Agent 主列的 Composer 交互会话：输入、选择器、发送与图片草稿。
///
/// 页面组合仍由 [AgentPane] 持有；本对象只承接 Composer 热路径，避免壳文件膨胀。
final class AgentPaneComposerSession {
  AgentPaneComposerSession({
    required this._runtime,
    required this.messageSendShortcut,
    required this.isMounted,
    required this.attachments,
    required this.submitMessage,
    required this.hostContext,
  }) {
    focusNode = FocusNode(
      debugLabel: 'AgentMessageComposer',
      onKeyEvent: handleComposerKeyEvent,
    );
    skillPopoverController = IdePopoverController(
      triggerFocusNode: focusNode,
      onOpenChanged: _handleSkillPopoverOpenChanged,
    );
    slashPopoverController = IdePopoverController(
      triggerFocusNode: focusNode,
      onOpenChanged: _handleSlashPopoverOpenChanged,
    );
    mentionPopoverController = IdePopoverController(
      triggerFocusNode: focusNode,
      onOpenChanged: _handleMentionPopoverOpenChanged,
    );
    inputController.addListener(_handleInputChanged);
    inputController.addListener(_handleSkillQueryChanged);
    inputController.addListener(_handleSlashQueryChanged);
    inputController.addListener(_handleMentionQueryChanged);
  }

  static const XTypeGroup _imageTypeGroup = XTypeGroup(
    label: 'Images',
    extensions: <String>['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp'],
  );

  AgentConversationRuntimeController _runtime;
  MessageSendShortcut messageSendShortcut;
  final bool Function() isMounted;
  final AgentComposerAttachmentPort Function() attachments;
  final AgentPaneSubmitMessage submitMessage;
  final BuildContext Function() hostContext;

  final ComposerDocumentController inputController =
      ComposerDocumentController();
  late final FocusNode focusNode;
  final GlobalKey composerAnchorKey = GlobalKey(
    debugLabel: 'agent-composer-skill-anchor',
  );
  final ValueNotifier<bool> canSendNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<List<String>> draftImagePaths =
      ValueNotifier<List<String>>(const <String>[]);
  final Set<String> _stagedClipboardPaths = <String>{};

  late final IdePopoverController skillPopoverController;
  final SkillPickerListController skillPickerListController =
      SkillPickerListController();
  late final IdePopoverController slashPopoverController;
  final SlashMenuListController slashMenuListController =
      SlashMenuListController();
  late final IdePopoverController mentionPopoverController;
  final MentionFileListController mentionFileListController =
      MentionFileListController();

  bool _skillQueryArmed = true;
  bool _skillPickerOpening = false;
  bool _slashQueryArmed = true;
  bool _slashPickerOpening = false;
  bool _mentionQueryArmed = true;
  bool _mentionPickerOpening = false;

  AgentConversationRuntimeController get runtime => _runtime;

  bool get skillPickerOpen => skillPopoverController.isOpen;

  bool get slashPickerOpen => slashPopoverController.isOpen;

  bool get mentionPickerOpen => mentionPopoverController.isOpen;

  bool get _hasSlashPlanCommand {
    if (!_runtime.canSelectConversationMode) {
      return false;
    }
    return _runtime.conversationModeOptions.any(
      (preset) =>
          preset.id == AgentConversationModeId.plan && preset.isSelectable,
    );
  }

  bool get _canOpenSlashMenu =>
      _hasSlashPlanCommand ||
      _runtime.canCompactCurrentThread ||
      _runtime.canUseSkills;

  void updateRuntime(AgentConversationRuntimeController runtime) {
    _runtime = runtime;
  }

  List<String> get stagedClipboardPaths =>
      List.unmodifiable(_stagedClipboardPaths);
  void restoreDraft(AgentPaneRetainedState snapshot) {
    inputController.restore(snapshot.document);
    draftImagePaths.value = snapshot.imagePaths;
    _stagedClipboardPaths.addAll(snapshot.stagedPaths);
    syncCanSend();
  }

  void dispose({bool retainDraft = false}) {
    inputController.removeListener(_handleInputChanged);
    inputController.removeListener(_handleSkillQueryChanged);
    inputController.removeListener(_handleSlashQueryChanged);
    inputController.removeListener(_handleMentionQueryChanged);
    skillPopoverController.dispose();
    skillPickerListController.dispose();
    slashPopoverController.dispose();
    slashMenuListController.dispose();
    mentionPopoverController.dispose();
    mentionFileListController.dispose();
    inputController.dispose();
    focusNode.dispose();
    canSendNotifier.dispose();
    final leftover = List<String>.of(_stagedClipboardPaths);
    draftImagePaths.dispose();
    if (!retainDraft && leftover.isNotEmpty) {
      unawaited(discardStaged(leftover));
    }
  }

  void _handleInputChanged() {
    syncCanSend();
  }

  void _handleSkillQueryChanged() {
    if (!_runtime.canUseSkills) {
      return;
    }
    final query = inputController.activeSkillQuery;
    if (query == null) {
      if (skillPickerOpen) {
        skillPopoverController.dismiss();
      }
      _skillQueryArmed = true;
      return;
    }
    if (skillPickerOpen) {
      return;
    }
    if (!_skillQueryArmed) {
      return;
    }
    if (slashPickerOpen) {
      slashPopoverController.dismiss();
    }
    if (mentionPickerOpen) {
      mentionPopoverController.dismiss();
    }
    _skillQueryArmed = false;
    unawaited(_showSkillPicker());
  }

  void _handleSkillPopoverOpenChanged() {
    if (!skillPickerOpen) {
      skillPickerListController.reset();
      if (inputController.activeSkillQuery == null) {
        _skillQueryArmed = true;
      }
    }
  }

  void _handleSlashQueryChanged() {
    if (!_canOpenSlashMenu) {
      return;
    }
    final query = inputController.activeSlashQuery;
    if (query == null) {
      if (slashPickerOpen) {
        slashPopoverController.dismiss();
      }
      _slashQueryArmed = true;
      return;
    }
    if (slashPickerOpen) {
      return;
    }
    if (!_slashQueryArmed) {
      return;
    }
    if (skillPickerOpen) {
      skillPopoverController.dismiss();
    }
    if (mentionPickerOpen) {
      mentionPopoverController.dismiss();
    }
    _slashQueryArmed = false;
    unawaited(_showSlashCommandPicker());
  }

  void _handleSlashPopoverOpenChanged() {
    if (!slashPickerOpen) {
      slashMenuListController.reset();
      if (inputController.activeSlashQuery == null) {
        _slashQueryArmed = true;
      }
    }
  }

  void _handleMentionQueryChanged() {
    if (!_runtime.canMentionResources) {
      return;
    }
    final query = inputController.activeMentionQuery;
    if (query == null) {
      if (mentionPickerOpen) {
        mentionPopoverController.dismiss();
      }
      _mentionQueryArmed = true;
      return;
    }
    if (mentionPickerOpen) {
      return;
    }
    if (!_mentionQueryArmed) {
      return;
    }
    if (skillPickerOpen) {
      skillPopoverController.dismiss();
    }
    if (slashPickerOpen) {
      slashPopoverController.dismiss();
    }
    _mentionQueryArmed = false;
    unawaited(_showMentionFilePicker());
  }

  void _handleMentionPopoverOpenChanged() {
    if (!mentionPickerOpen) {
      mentionFileListController.reset();
      if (inputController.activeMentionQuery == null) {
        _mentionQueryArmed = true;
      }
    }
  }

  void syncCanSend() {
    final canSend =
        inputController.hasContent || draftImagePaths.value.isNotEmpty;
    if (canSend == canSendNotifier.value) {
      return;
    }
    canSendNotifier.value = canSend;
  }

  KeyEventResult handleComposerKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }

    if (slashPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        slashPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        slashMenuListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        slashMenuListController.move(-1);
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final item = slashMenuListController.highlighted;
        if (item != null) {
          _activateSlashMenuItem(item);
        }
        return KeyEventResult.handled;
      }
    }

    if (skillPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        skillPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        skillPickerListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        skillPickerListController.move(-1);
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final skill = skillPickerListController.highlighted;
        if (skill != null) {
          _selectSkillFromPicker(skill);
        }
        return KeyEventResult.handled;
      }
    }

    if (mentionPickerOpen) {
      if (event.logicalKey == LogicalKeyboardKey.escape) {
        mentionPopoverController.dismiss();
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
        mentionFileListController.move(1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
        mentionFileListController.move(-1);
        return KeyEventResult.handled;
      }
      if (event.logicalKey == LogicalKeyboardKey.tab) {
        final file = mentionFileListController.highlighted;
        if (file != null) {
          _selectMentionFromPicker(file);
        }
        return KeyEventResult.handled;
      }
      final isEnter =
          event.logicalKey == LogicalKeyboardKey.enter ||
          event.logicalKey == LogicalKeyboardKey.numpadEnter;
      if (isEnter) {
        final composing = inputController.value.composing;
        if (composing.isValid && !composing.isCollapsed) {
          return KeyEventResult.ignored;
        }
        final file = mentionFileListController.highlighted;
        if (file != null) {
          _selectMentionFromPicker(file);
        }
        return KeyEventResult.handled;
      }
    }

    final isEnter =
        event.logicalKey == LogicalKeyboardKey.enter ||
        event.logicalKey == LogicalKeyboardKey.numpadEnter;
    if (isEnter) {
      final composing = inputController.value.composing;
      if (composing.isValid && !composing.isCollapsed) {
        return KeyEventResult.ignored;
      }
      if (_matchesMessageSendShortcut(Theme.of(hostContext()).platform)) {
        if (canSendNotifier.value && _runtime.canSubmitMessage) {
          sendMessage();
        }
      } else {
        _insertComposerNewline();
      }
      return KeyEventResult.handled;
    }

    final isPaste =
        (HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed) &&
        event.logicalKey == LogicalKeyboardKey.keyV;
    if (!isPaste) {
      return KeyEventResult.ignored;
    }
    unawaited(pasteImagesFromClipboard());
    return KeyEventResult.handled;
  }

  bool _matchesMessageSendShortcut(TargetPlatform platform) {
    final keyboard = HardwareKeyboard.instance;
    final controlPressed = keyboard.isControlPressed;
    final metaPressed = keyboard.isMetaPressed;
    final shiftPressed = keyboard.isShiftPressed;
    final altPressed = keyboard.isAltPressed;
    return switch (messageSendShortcut) {
      MessageSendShortcut.enter =>
        !controlPressed && !metaPressed && !shiftPressed && !altPressed,
      MessageSendShortcut.primaryModifierEnter =>
        !shiftPressed &&
            !altPressed &&
            (platform == TargetPlatform.macOS
                ? metaPressed && !controlPressed
                : controlPressed && !metaPressed),
    };
  }

  void _insertComposerNewline() {
    final value = inputController.value;
    final selection = value.selection;
    final start = selection.isValid ? selection.start : value.text.length;
    final end = selection.isValid ? selection.end : value.text.length;
    final nextText = value.text.replaceRange(start, end, '\n');
    inputController.value = value.copyWith(
      text: nextText,
      selection: TextSelection.collapsed(offset: start + 1),
      composing: TextRange.empty,
    );
  }

  Future<void> pickImages() async {
    if (!_runtime.canAttachImages) {
      return;
    }
    final files = await openFiles(
      acceptedTypeGroups: <XTypeGroup>[_imageTypeGroup],
    );
    if (files.isEmpty || !isMounted()) {
      return;
    }
    addDraftImages(files.map((file) => file.path));
  }

  Future<bool> pasteImagesFromClipboard() async {
    if (_runtime.canAttachImages) {
      final imageBytes = await Pasteboard.image;
      if (imageBytes != null && imageBytes.isNotEmpty) {
        final path = await stageClipboardImage(imageBytes);
        if (!isMounted()) {
          unawaited(discardStaged(<String>[path]));
          return true;
        }
        addDraftImages(<String>[path]);
        return true;
      }

      final files = await Pasteboard.files();
      final imagePaths = files
          .where(looksLikeAgentComposerImagePath)
          .toList(growable: false);
      if (imagePaths.isNotEmpty) {
        if (!isMounted()) {
          return true;
        }
        addDraftImages(imagePaths);
        return true;
      }
    }

    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty || !isMounted()) {
      return false;
    }
    final selection = inputController.selection;
    final value = inputController.text;
    final start = selection.isValid ? selection.start : value.length;
    final end = selection.isValid ? selection.end : value.length;
    final next = value.replaceRange(start, end, text);
    inputController.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: start + text.length),
    );
    return true;
  }

  void addDraftImages(Iterable<String> paths) {
    final next = List<String>.of(draftImagePaths.value);
    var changed = false;
    for (final path in paths) {
      final trimmed = path.trim();
      if (trimmed.isEmpty || next.contains(trimmed)) {
        continue;
      }
      next.add(trimmed);
      changed = true;
    }
    if (!changed) {
      return;
    }
    draftImagePaths.value = List<String>.unmodifiable(next);
    syncCanSend();
  }

  void removeDraftImage(String path) {
    final current = draftImagePaths.value;
    if (!current.contains(path)) {
      return;
    }
    draftImagePaths.value = List<String>.unmodifiable(
      current.where((item) => item != path),
    );
    unawaited(discardStaged(<String>[path]));
    syncCanSend();
  }

  Future<String> stageClipboardImage(Uint8List bytes) async {
    final path = await attachments().stageClipboardImage(
      bytes,
      extension: 'png',
    );
    _stagedClipboardPaths.add(path);
    return path;
  }

  Future<void> discardStaged(List<String> paths) {
    final staged = <String>[
      for (final path in paths)
        if (_stagedClipboardPaths.remove(path)) path,
    ];
    if (staged.isEmpty) {
      return Future<void>.value();
    }
    return attachments().discard(staged);
  }

  void sendMessage() {
    if (!canSendNotifier.value || !_runtime.canSubmitMessage) {
      return;
    }
    final serialized = inputController.serialize();
    final images = List<String>.of(draftImagePaths.value);
    final mentions = serialized.mentions;
    if (serialized.text.trim().isEmpty &&
        images.isEmpty &&
        mentions.isEmpty &&
        serialized.skills.isEmpty) {
      return;
    }
    inputController.clear();
    if (draftImagePaths.value.isNotEmpty) {
      draftImagePaths.value = const <String>[];
    }
    _stagedClipboardPaths.removeAll(images);
    syncCanSend();
    submitMessage(
      serialized.text,
      localImagePaths: images,
      mentions: mentions,
      skills: serialized.skills,
    );
  }

  void _insertSkill(AgentSkillMetadata skill) {
    if (!_runtime.canUseSkills) {
      return;
    }
    inputController.insertSkill(skill);
    syncCanSend();
    focusNode.requestFocus();
  }

  void _selectSkillFromPicker(AgentSkillMetadata skill) {
    skillPopoverController.dismiss();
    _insertSkill(skill);
  }

  void _activateSlashMenuItem(SlashMenuItem item) {
    switch (item) {
      case final SlashCommandMenuItem command:
        _selectSlashCommand(command.id);
      case final SlashSkillMenuItem skill:
        _selectSkillFromSlashMenu(skill.skill);
    }
  }

  void _selectSlashCommand(SlashCommandId id) {
    slashPopoverController.dismiss();
    inputController.consumeActiveSlashQuery();
    switch (id) {
      case SlashCommandId.plan:
        if (_runtime.selectedConversationMode != AgentConversationModeId.plan) {
          _runtime.selectConversationMode(AgentConversationModeId.plan);
        }
      case SlashCommandId.compact:
        unawaited(_runtime.compactCurrentThread());
    }
    focusNode.requestFocus();
  }

  void _selectSkillFromSlashMenu(AgentSkillMetadata skill) {
    slashPopoverController.dismiss();
    _insertSkill(skill);
  }

  void openSkillPickerFromMenu() {
    if (!_runtime.canUseSkills || skillPickerOpen || _skillPickerOpening) {
      return;
    }
    _skillQueryArmed = false;
    if (slashPickerOpen) {
      slashPopoverController.dismiss();
    }
    _ensureSkillQueryTrigger();
    unawaited(_showSkillPicker());
  }

  void _ensureSkillQueryTrigger() {
    if (inputController.activeSkillQuery != null) {
      return;
    }
    final text = inputController.text;
    final selection = inputController.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : cursor;
    final left = math.min(start, cursor);
    final right = math.max(start, cursor);
    final before = text.substring(0, left);
    final after = text.substring(right);
    final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    final insert = needsSpace ? r' $' : r'$';
    inputController.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: before.length + insert.length),
      composing: TextRange.empty,
    );
  }

  Future<void> _showSkillPicker() async {
    if (!_runtime.canUseSkills ||
        skillPickerOpen ||
        _skillPickerOpening ||
        !isMounted()) {
      return;
    }
    if (composerAnchorKey.currentContext == null) {
      return;
    }
    _skillPickerOpening = true;
    try {
      try {
        await _runtime.ensureSkillsCatalog();
      } catch (_) {
        // 目录失败时仍展示 picker，由空态提示用户。
      }
      if (!isMounted() || skillPickerOpen) {
        return;
      }
      final openContext = composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      skillPopoverController.show(
        context: openContext,
        preferredWidth: agentSkillPickerPreferredWidth,
        preferredMaxHeight: agentSkillPickerPreferredMaxHeight,
        key: const ValueKey('agent-skill-picker-overlay'),
        builder: (context, layout) => AgentSkillPickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: inputController,
          listController: skillPickerListController,
          candidatesFor: (query) => _runtime.skillCandidates(query: query),
          onSelect: _selectSkillFromPicker,
          onRequestClose: skillPopoverController.dismiss,
        ),
      );
    } finally {
      _skillPickerOpening = false;
    }
  }

  Future<void> _showSlashCommandPicker() async {
    if (!_canOpenSlashMenu ||
        slashPickerOpen ||
        _slashPickerOpening ||
        !isMounted()) {
      return;
    }
    if (composerAnchorKey.currentContext == null) {
      return;
    }
    _slashPickerOpening = true;
    try {
      if (_runtime.canUseSkills) {
        try {
          await _runtime.ensureSkillsCatalog();
        } catch (_) {
          // 目录失败时仍展示菜单；Skills 可为空，命令仍可用。
        }
      }
      if (!isMounted() || slashPickerOpen) {
        return;
      }
      final openContext = composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      slashPopoverController.show(
        context: openContext,
        preferredWidth: agentSlashCommandPickerPreferredWidth,
        preferredMaxHeight: agentSlashCommandPickerPreferredMaxHeight,
        key: const ValueKey('agent-slash-command-picker-overlay'),
        builder: (context, layout) => AgentSlashCommandPickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: inputController,
          listController: slashMenuListController,
          showPlanCommand: _hasSlashPlanCommand,
          showCompactCommand: _runtime.canCompactCurrentThread,
          planSelected:
              _runtime.selectedConversationMode == AgentConversationModeId.plan,
          skillCandidatesFor: (query) => _runtime.canUseSkills
              ? _runtime.skillCandidates(query: query)
              : const <AgentSkillMetadata>[],
          onSelectCommand: _selectSlashCommand,
          onSelectSkill: _selectSkillFromSlashMenu,
          onRequestClose: slashPopoverController.dismiss,
        ),
      );
    } finally {
      _slashPickerOpening = false;
    }
  }

  void _selectMentionFromPicker(WorkspaceNode file) {
    mentionPopoverController.dismiss();
    _insertMention(file);
  }

  Future<void> _showMentionFilePicker() async {
    if (!_runtime.canMentionResources ||
        mentionPickerOpen ||
        _mentionPickerOpening ||
        !isMounted()) {
      return;
    }
    if (composerAnchorKey.currentContext == null) {
      return;
    }
    _mentionPickerOpening = true;
    try {
      if (!isMounted() || mentionPickerOpen) {
        return;
      }
      final openContext = composerAnchorKey.currentContext;
      if (openContext == null || !openContext.mounted) {
        return;
      }
      mentionPopoverController.show(
        context: openContext,
        preferredWidth: agentMentionFilePickerPreferredWidth,
        preferredMaxHeight: agentMentionFilePickerPreferredMaxHeight,
        key: const ValueKey('agent-mention-picker-overlay'),
        builder: (context, layout) => AgentMentionFilePickerPopover(
          width: layout.width,
          maxHeight: layout.maxHeight,
          documentController: inputController,
          listController: mentionFileListController,
          candidatesFor: (query) =>
              _runtime.mentionCandidateFiles(query: query),
          fileCorpus: _runtime.workspaceFileCorpus,
          isIndexReady: () => _runtime.isWorkspaceFileIndexReady,
          onSelect: _selectMentionFromPicker,
          onRequestClose: mentionPopoverController.dismiss,
        ),
      );
    } finally {
      _mentionPickerOpening = false;
    }
  }

  void openMentionPickerFromMenu() {
    if (!_runtime.canMentionResources ||
        mentionPickerOpen ||
        _mentionPickerOpening) {
      return;
    }
    _mentionQueryArmed = false;
    if (slashPickerOpen) {
      slashPopoverController.dismiss();
    }
    if (skillPickerOpen) {
      skillPopoverController.dismiss();
    }
    _ensureMentionQueryTrigger();
    unawaited(_showMentionFilePicker());
  }

  void _ensureMentionQueryTrigger() {
    if (inputController.activeMentionQuery != null) {
      return;
    }
    final text = inputController.text;
    final selection = inputController.selection;
    final cursor = selection.isValid
        ? selection.extentOffset.clamp(0, text.length)
        : text.length;
    final start = selection.isValid
        ? selection.baseOffset.clamp(0, text.length)
        : cursor;
    final left = math.min(start, cursor);
    final right = math.max(start, cursor);
    final before = text.substring(0, left);
    final after = text.substring(right);
    final needsSpace = before.isNotEmpty && !RegExp(r'\s$').hasMatch(before);
    final insert = needsSpace ? ' @' : '@';
    inputController.value = TextEditingValue(
      text: '$before$insert$after',
      selection: TextSelection.collapsed(offset: before.length + insert.length),
      composing: TextRange.empty,
    );
  }

  void _insertMention(WorkspaceNode file) {
    if (!_runtime.canMentionResources) {
      return;
    }
    inputController.insertMention(name: file.name, path: file.path);
    syncCanSend();
    focusNode.requestFocus();
  }
}

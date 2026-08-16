import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_highlight/themes/github.dart';
import 'package:flutter_highlight/themes/vs2015.dart';
import 'package:highlight/highlight.dart' show Node, highlight;
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/core/utils/system_file_manager.dart';
import 'package:zeta/src/features/agent_management/application/agent_management_controller.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';
import 'package:zeta/src/ui/core/ide_dialog.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_status_card.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/ide_toast.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// Codex TOML 配置编辑器。
class AgentConfigurationEditor extends StatefulWidget {
  const AgentConfigurationEditor({
    required this.controller,
    this.onDirtyChanged,
    super.key,
  });

  final AgentManagementController controller;
  final ValueChanged<bool>? onDirtyChanged;

  @override
  State<AgentConfigurationEditor> createState() =>
      AgentConfigurationEditorState();
}

/// 暴露未保存状态，供设置页在离开前确认。
class AgentConfigurationEditorState extends State<AgentConfigurationEditor> {
  late final _TomlEditingController _editingController;
  late final TextEditingController _searchController;
  bool _revealed = false;
  bool _dirty = false;
  String? _validationError;

  bool get hasUnsavedChanges => _dirty;

  /// 保存当前编辑内容；按钮和宿主页面可复用同一异步操作。
  Future<void> save() => _save();

  @override
  void initState() {
    super.initState();
    _editingController = _TomlEditingController();
    _searchController = TextEditingController();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      final existing = widget.controller.configuration;
      if (existing != null) {
        _setEditorContent(
          _revealed ? existing.content : existing.maskedContent,
          dirty: false,
        );
        return;
      }
      unawaited(_load());
    });
  }

  @override
  void dispose() {
    _editingController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// 未保存时询问用户是否放弃修改。
  Future<bool> confirmCanLeave() async {
    if (!_dirty) {
      return true;
    }
    final discard = await showIdeDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => IdeDialog(
        title: Text(context.l10n.mgmtUnsavedTitle),
        content: Text(context.l10n.mgmtUnsavedBody),
        actions: <IdeDialogAction>[
          IdeDialogAction.cancel(
            label: context.l10n.mgmtKeepEditing,
            onPressed: () => Navigator.of(context).pop(false),
          ),
          IdeDialogAction.destructive(
            label: context.l10n.mgmtDiscardChanges,
            onPressed: () => Navigator.of(context).pop(true),
          ),
        ],
      ),
    );
    return discard ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final brightness = sf.Theme.of(context).brightness;
    _editingController
      ..syntaxTheme = brightness == Brightness.dark ? vs2015Theme : githubTheme
      ..baseStyle = textStyles.codeSmall.copyWith(color: colors.textPrimary);

    return ListenableBuilder(
      listenable: widget.controller,
      builder: (context, _) {
        final document = widget.controller.configuration;
        if (widget.controller.loadingConfiguration && document == null) {
          return Center(
            child: IdeLoadingIndicator(
              width: 32,
              height: 14,
              semanticsLabel: context.l10n.mgmtLoadingConfig,
            ),
          );
        }
        if (document == null) {
          return EmptyState(
            text:
                widget.controller.operationError ??
                context.l10n.mgmtConfigNotLoadedYet,
          );
        }

        final lineCount = '\n'.allMatches(_editingController.text).length + 1;
        return SingleChildScrollView(
          padding: IdeSpacing.all16,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildFileHeader(context, document),
              const SizedBox(height: IdeSpacing.space12),
              if (!_revealed)
                IdeStatusCard(
                  tone: IdeStatusCardTone.warning,
                  title: context.l10n.mgmtSensitiveMaskedTitle,
                  body: Text(
                    context.l10n.mgmtSensitiveMaskedBody,
                    style: textStyles.bodySmall.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              _buildSearchBar(context),
              const SizedBox(height: IdeSpacing.space8),
              SizedBox(
                height: 420,
                child: PanelCard(
                  child: SingleChildScrollView(
                    padding: EdgeInsets.zero,
                    child: IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Container(
                            width: 48,
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 10),
                            color: colors.surfaceElevated,
                            child: SelectableText(
                              List<String>.generate(
                                lineCount,
                                (index) => '${index + 1}',
                              ).join('\n'),
                              textAlign: TextAlign.right,
                              style: textStyles.codeSmall.copyWith(
                                color: colors.textTertiary,
                                height: 1.45,
                              ),
                            ),
                          ),
                          Expanded(
                            child: sf.TextField(
                              key: const ValueKey('agent-config-editor'),
                              controller: _editingController,
                              readOnly: !_revealed,
                              minLines: 18,
                              maxLines: null,
                              keyboardType: TextInputType.multiline,
                              style: textStyles.codeSmall.copyWith(
                                color: colors.textPrimary,
                                height: 1.45,
                              ),
                              onChanged: _handleChanged,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: IdeSpacing.space10),
              _buildValidationAndActions(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFileHeader(
    BuildContext context,
    AgentConfigurationDocument document,
  ) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final info = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.l10n.mgmtConfigFile, style: textStyles.sectionTitle),
            const SizedBox(height: IdeSpacing.space4),
            SelectableText(
              document.path,
              style: textStyles.codeSmall.copyWith(color: colors.textSecondary),
            ),
            const SizedBox(height: IdeSpacing.space4),
            Text(
              '${document.format} · ${document.exists ? context.l10n.mgmtConfigExists : context.l10n.mgmtConfigMissing} · '
              '${context.l10n.mgmtLastLoaded(_formatDateTime(document.loadedAt))}',
              style: textStyles.caption.copyWith(color: colors.textTertiary),
            ),
          ],
        );
        final actions = Wrap(
          spacing: IdeSpacing.space8,
          runSpacing: IdeSpacing.space8,
          children: [
            sf.OutlineButton(
              onPressed: _dirty ? null : _load,
              size: sf.ButtonSize.small,
              child: Text(context.l10n.mgmtReloadConfig),
            ),
            sf.OutlineButton(
              onPressed: () => _openContainingDirectory(document.path),
              size: sf.ButtonSize.small,
              child: Text(context.l10n.mgmtOpenContainingFolder),
            ),
            sf.OutlineButton(
              key: const ValueKey('agent-config-reveal-button'),
              onPressed: _dirty && _revealed ? null : _toggleReveal,
              size: sf.ButtonSize.small,
              child: Text(
                _revealed
                    ? context.l10n.mgmtHideSensitive
                    : context.l10n.mgmtShowSensitive,
              ),
            ),
          ],
        );
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              info,
              const SizedBox(height: IdeSpacing.space12),
              actions,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: info),
            const SizedBox(width: IdeSpacing.space16),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildSearchBar(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: sf.TextField(
            key: const ValueKey('agent-config-search'),
            controller: _searchController,
            placeholder: Text(context.l10n.mgmtSearchInConfig),
            features: const <sf.InputFeature>[
              sf.InputFeature.leading(Icon(Icons.search_rounded, size: 18)),
            ],
            onSubmitted: (_) => _findNext(),
          ),
        ),
        const SizedBox(width: IdeSpacing.space8),
        sf.OutlineButton(
          onPressed: _findNext,
          size: sf.ButtonSize.small,
          child: Text(context.l10n.mgmtFindNext),
        ),
      ],
    );
  }

  Widget _buildValidationAndActions(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final valid = _validationError == null;
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: IdeSpacing.space12,
      runSpacing: IdeSpacing.space8,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              valid ? Icons.check_circle_outline : Icons.error_outline,
              size: 16,
              color: valid ? colors.success : colors.error,
            ),
            const SizedBox(width: IdeSpacing.space6),
            Flexible(
              child: Text(
                valid ? context.l10n.mgmtConfigValid : _validationError!,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: textStyles.bodySmall.copyWith(
                  color: valid ? colors.success : colors.error,
                ),
              ),
            ),
          ],
        ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            sf.OutlineButton(
              onPressed: _dirty ? _discardChanges : null,
              size: sf.ButtonSize.small,
              child: Text(context.l10n.mgmtCancelEdits),
            ),
            const SizedBox(width: IdeSpacing.space8),
            sf.PrimaryButton(
              key: const ValueKey('agent-config-save-button'),
              onPressed:
                  _dirty && valid && !widget.controller.savingConfiguration
                  ? _save
                  : null,
              size: sf.ButtonSize.small,
              child: Text(
                widget.controller.savingConfiguration
                    ? context.l10n.mgmtSaving
                    : context.l10n.mgmtSaveConfig,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _load() async {
    final document = await widget.controller.loadConfiguration();
    if (document == null || !mounted) {
      return;
    }
    _setEditorContent(
      _revealed ? document.content : document.maskedContent,
      dirty: false,
    );
  }

  void _toggleReveal() {
    final document = widget.controller.configuration;
    if (document == null || _dirty) {
      return;
    }
    setState(() {
      _revealed = !_revealed;
      _editingController.text = _revealed
          ? document.content
          : document.maskedContent;
      _editingController.selection = const TextSelection.collapsed(offset: 0);
      _validationError = _revealed
          ? widget.controller.validateConfiguration(document.content)
          : null;
    });
  }

  void _handleChanged(String content) {
    if (!_revealed) {
      return;
    }
    final document = widget.controller.configuration;
    final dirty = document != null && content != document.content;
    final error = widget.controller.validateConfiguration(content);
    if (dirty == _dirty && error == _validationError) {
      return;
    }
    setState(() {
      _validationError = error;
      _setDirty(dirty);
    });
  }

  void _discardChanges() {
    final document = widget.controller.configuration;
    if (document == null) {
      return;
    }
    _setEditorContent(document.content, dirty: false);
  }

  Future<void> _save({bool overwriteExternalChanges = false}) async {
    try {
      final result = await widget.controller.saveConfiguration(
        _editingController.text,
        overwriteExternalChanges: overwriteExternalChanges,
      );
      if (!mounted) {
        return;
      }
      _setEditorContent(result.document.content, dirty: false);
      showIdeToast(
        context,
        message: result.backupPath == null
            ? context.l10n.mgmtConfigSavedRestart
            : context.l10n.mgmtConfigSavedBackup,
        tone: IdeToastTone.success,
      );
    } on AgentConfigurationConflictException {
      if (!mounted) {
        return;
      }
      final action = await showIdeDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (context) => IdeDialog(
          title: Text(context.l10n.mgmtConfigExternalTitle),
          content: Text(context.l10n.mgmtConfigExternalBody),
          actions: <IdeDialogAction>[
            IdeDialogAction.cancel(
              label: context.l10n.mgmtReloadConfig,
              onPressed: () => Navigator.of(context).pop('reload'),
            ),
            IdeDialogAction.destructive(
              label: context.l10n.mgmtSaveAnyway,
              onPressed: () => Navigator.of(context).pop('overwrite'),
            ),
          ],
        ),
      );
      if (!mounted) {
        return;
      }
      if (action == 'reload') {
        await _load();
      } else if (action == 'overwrite') {
        await _save(overwriteExternalChanges: true);
      }
    } on AgentConfigurationValidationException catch (error) {
      if (mounted) {
        setState(() {
          _validationError = error.message;
        });
      }
    } catch (error) {
      if (mounted) {
        showIdeToast(
          context,
          message: context.l10n.mgmtConfigSaveFailed('$error'),
          tone: IdeToastTone.error,
        );
      }
    }
  }

  void _findNext() {
    final query = _searchController.text;
    if (query.isEmpty) {
      return;
    }
    final text = _editingController.text;
    final start = _editingController.selection.end.clamp(0, text.length);
    var index = text.toLowerCase().indexOf(query.toLowerCase(), start);
    if (index < 0 && start > 0) {
      index = text.toLowerCase().indexOf(query.toLowerCase());
    }
    if (index < 0) {
      showIdeToast(context, message: context.l10n.mgmtQueryNotFound(query));
      return;
    }
    _editingController.selection = TextSelection(
      baseOffset: index,
      extentOffset: index + query.length,
    );
  }

  void _setEditorContent(String content, {required bool dirty}) {
    setState(() {
      _editingController.text = content;
      _editingController.selection = const TextSelection.collapsed(offset: 0);
      _validationError = _revealed
          ? widget.controller.validateConfiguration(content)
          : null;
      _setDirty(dirty);
    });
  }

  void _setDirty(bool value) {
    if (_dirty == value) {
      return;
    }
    _dirty = value;
    widget.onDirtyChanged?.call(value);
  }

  Future<void> _openContainingDirectory(String path) async {
    try {
      await openPathInSystemFileManager(File(path).parent.path);
    } catch (error) {
      if (mounted) {
        showIdeToast(
          context,
          message: context.l10n.mgmtCannotOpenConfigDir('$error'),
          tone: IdeToastTone.error,
        );
      }
    }
  }
}

class _TomlEditingController extends TextEditingController {
  Map<String, TextStyle> syntaxTheme = const <String, TextStyle>{};
  TextStyle baseStyle = const TextStyle();

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    try {
      final nodes = highlight.parse(text, language: 'toml').nodes;
      return TextSpan(
        style: baseStyle.merge(style),
        children: nodes == null ? <TextSpan>[] : _convert(nodes),
      );
    } catch (_) {
      return TextSpan(text: text, style: baseStyle.merge(style));
    }
  }

  List<TextSpan> _convert(List<Node> nodes) {
    final spans = <TextSpan>[];
    for (final node in nodes) {
      spans.add(_convertNode(node));
    }
    return spans;
  }

  TextSpan _convertNode(Node node) {
    final nodeStyle = node.className == null
        ? null
        : syntaxTheme[node.className!];
    if (node.value != null) {
      return TextSpan(text: node.value, style: nodeStyle);
    }
    return TextSpan(
      style: nodeStyle,
      children: <TextSpan>[
        for (final child in node.children ?? const <Node>[])
          _convertNode(child),
      ],
    );
  }
}

String _formatDateTime(DateTime value) {
  String two(int number) => number.toString().padLeft(2, '0');
  return '${value.year}-${two(value.month)}-${two(value.day)} '
      '${two(value.hour)}:${two(value.minute)}';
}

import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

void main() {
  runApp(const PrototypeApp());
}

@immutable
class GraphitePalette {
  const GraphitePalette({
    required this.brightness,
    required this.panel,
    required this.surface,
    required this.border,
    required this.accent,
    required this.textPrimary,
    required this.textSecondary,
  });

  final Brightness brightness;
  final Color panel;
  final Color surface;
  final Color border;
  final Color accent;
  final Color textPrimary;
  final Color textSecondary;

  static const dark = GraphitePalette(
    brightness: Brightness.dark,
    panel: Color(0xFF18191B),
    surface: Color(0xFF141517),
    border: Color(0xFF2C2D31),
    accent: Color(0xFF1B84FF),
    textPrimary: Color(0xFFF4F5F7),
    textSecondary: Color(0xFF9EA1A7),
  );

  static const light = GraphitePalette(
    brightness: Brightness.light,
    panel: Color(0xFFF7F7F8),
    surface: Color(0xFFFFFFFF),
    border: Color(0xFFD8DAE0),
    accent: Color(0xFF0B76D8),
    textPrimary: Color(0xFF17181A),
    textSecondary: Color(0xFF5B5E66),
  );
}

/// 最小 Graphite token scope：验证主题真源可以留在项目自身，而不是反向依赖库主题。
class GraphiteThemeScope extends InheritedWidget {
  const GraphiteThemeScope({
    required this.palette,
    required super.child,
    super.key,
  });

  final GraphitePalette palette;

  static GraphitePalette of(BuildContext context) {
    final scope =
        context.dependOnInheritedWidgetOfExactType<GraphiteThemeScope>();
    assert(scope != null, 'GraphiteThemeScope is missing');
    return scope!.palette;
  }

  @override
  bool updateShouldNotify(covariant GraphiteThemeScope oldWidget) {
    return oldWidget.palette != palette;
  }
}

sf.ThemeData buildGraphiteTheme(GraphitePalette palette) {
  return palette.brightness == Brightness.dark
      ? const sf.ThemeData.dark(
          colorScheme: sf.ColorSchemes.darkSlate,
          radius: 0.7,
          scaling: 1,
          typography: sf.Typography.geist(),
          platform: TargetPlatform.windows,
        )
      : const sf.ThemeData(
          colorScheme: sf.ColorSchemes.lightSlate,
          radius: 0.7,
          scaling: 1,
          typography: sf.Typography.geist(),
          platform: TargetPlatform.windows,
        );
}

class PrototypeApp extends StatelessWidget {
  const PrototypeApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const GraphiteThemeScope(
      palette: GraphitePalette.dark,
      child: _PrototypeRoot(),
    );
  }
}

class _PrototypeRoot extends StatelessWidget {
  const _PrototypeRoot();

  @override
  Widget build(BuildContext context) {
    return sf.ShadcnApp(
      debugShowCheckedModeBanner: false,
      title: 'shadcn_flutter preflight',
      theme: buildGraphiteTheme(GraphitePalette.light),
      darkTheme: buildGraphiteTheme(GraphitePalette.dark),
      themeMode: sf.ThemeMode.dark,
      home: const _PrototypeScreen(),
    );
  }
}

class _PrototypeScreen extends StatefulWidget {
  const _PrototypeScreen();

  @override
  State<_PrototypeScreen> createState() => _PrototypeScreenState();
}

class _PrototypeScreenState extends State<_PrototypeScreen> {
  final TextEditingController _textareaController = TextEditingController();
  String? _selectedModel;

  @override
  void dispose() {
    _textareaController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GraphiteThemeScope.of(context);
    return Material(
      color: palette.surface,
      child: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Graphite projection active',
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '验证 ShadcnApp、AlertDialog、Popover、Select 与 TextArea 的最小可行性。',
                    style: TextStyle(color: palette.textSecondary),
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      sf.PrimaryButton(
                        key: const ValueKey('open-dialog-button'),
                        onPressed: _showPrototypeDialog,
                        child: const Text('Open dialog'),
                      ),
                      sf.OutlineButton(
                        key: const ValueKey('open-popover-button'),
                        onPressed: _showPrototypePopover,
                        child: const Text('Open popover'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 220,
                        child: sf.Select<String>(
                          key: const ValueKey('model-select'),
                          value: _selectedModel,
                          onChanged: (value) {
                            setState(() {
                              _selectedModel = value;
                            });
                          },
                          placeholder: const Text(
                            'Model',
                            key: ValueKey('model-select-trigger'),
                          ),
                          itemBuilder: (context, item) {
                            return Text(item);
                          },
                          constraints: const BoxConstraints(minWidth: 220),
                          popupConstraints:
                              const BoxConstraints(maxHeight: 220),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          popup: sf.SelectPopup<String>(
                            items: sf.SelectItemList(
                              children: const [
                                sf.SelectItemButton<String>(
                                  value: 'GPT-5',
                                  child: Text('GPT-5'),
                                ),
                                sf.SelectItemButton<String>(
                                  value: 'o4-mini',
                                  child: Text('o4-mini'),
                                ),
                                sf.SelectItemButton<String>(
                                  value: 'Reasoning High',
                                  child: Text('Reasoning High'),
                                ),
                              ],
                            ),
                          ).call,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Container(
                    decoration: BoxDecoration(
                      color: palette.panel,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: palette.border),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: sf.TextArea(
                      key: const ValueKey('prototype-textarea'),
                      controller: _textareaController,
                      placeholder: const Text('Describe the migration risk...'),
                      minLines: 3,
                      maxLines: 10,
                      minHeight: 96,
                      maxHeight: 240,
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _showPrototypeDialog() {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return sf.AlertDialog(
          title: const Text('Prototype alert'),
          content: const Text('showDialog + sf.AlertDialog works as expected.'),
          actions: [
            sf.OutlineButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            sf.PrimaryButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Confirm'),
            ),
          ],
        );
      },
    );
  }

  void _showPrototypePopover() {
    sf.showPopover<void>(
      context: context,
      alignment: Alignment.bottomLeft,
      anchorAlignment: Alignment.topLeft,
      offset: const Offset(0, 8),
      builder: (popoverContext) {
        return ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 196),
          child: sf.MenuGroup(
            direction: Axis.vertical,
            onDismissed: () => sf.closeOverlay(popoverContext),
            builder: (context, children) {
              return sf.MenuPopup(children: children);
            },
            children: [
              sf.MenuButton(
                child: const Text('Rename thread'),
                onPressed: (_) => sf.closeOverlay(popoverContext),
              ),
              const sf.MenuDivider(),
              sf.MenuButton(
                child: const Text('Archive thread'),
                onPressed: (_) => sf.closeOverlay(popoverContext),
              ),
            ],
          ),
        );
      },
    );
  }
}

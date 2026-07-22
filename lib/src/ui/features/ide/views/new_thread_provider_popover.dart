import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';

/// 新建 Thread 时使用的 Agent Provider 选择内容。
///
/// 调用方负责通过 [showIdePopover] 提供锚点，并消费关闭时返回的 provider。
class NewThreadProviderPopover extends StatefulWidget {
  const NewThreadProviderPopover({
    required this.loadAvailableProviders,
    super.key,
  });

  final Future<List<AgentProviderConfig>> Function() loadAvailableProviders;

  @override
  State<NewThreadProviderPopover> createState() =>
      _NewThreadProviderPopoverState();
}

class _NewThreadProviderPopoverState extends State<NewThreadProviderPopover> {
  late final Future<List<AgentProviderConfig>> _providersFuture = widget
      .loadAvailableProviders();
  String? _selectedProviderId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<AgentProviderConfig>>(
      future: _providersFuture,
      builder: (context, snapshot) {
        final providers = CursorRetirementPolicy.supportedProviders(
          snapshot.data ?? const <AgentProviderConfig>[],
        );
        final selectedProvider = _selectedProvider(providers);
        final colors = IdeColors.of(context);
        final textStyles = IdeTextStyles.of(context);
        final brightness = sf.Theme.of(context).brightness;
        return RepaintBoundary(
          child: PanelCard(
            key: const ValueKey<String>('new-thread-provider-popover'),
            color: colors.surfaceOverlay,
            borderRadius: IdeRadius.allLarge,
            boxShadow: IdeEffects.overlayShadow(brightness),
            child: SizedBox(
              width: 300,
              child: Padding(
                padding: IdeSpacing.all12,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '选择 Agent Provider',
                      style: textStyles.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: IdeSpacing.space10),
                    _buildContent(context, snapshot, providers),
                    const SizedBox(height: IdeSpacing.space12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        sf.OutlineButton(
                          onPressed: () => sf.closeOverlay(context),
                          size: sf.ButtonSize.small,
                          child: const Text('取消'),
                        ),
                        const SizedBox(width: IdeSpacing.space8),
                        sf.PrimaryButton(
                          onPressed: selectedProvider == null
                              ? null
                              : () =>
                                    sf.closeOverlay(context, selectedProvider),
                          size: sf.ButtonSize.small,
                          child: const Text('创建 Thread'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildContent(
    BuildContext context,
    AsyncSnapshot<List<AgentProviderConfig>> snapshot,
    List<AgentProviderConfig> providers,
  ) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    if (snapshot.connectionState != ConnectionState.done) {
      return Padding(
        padding: IdeSpacing.all16,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colors.accent,
              ),
            ),
            const SizedBox(width: IdeSpacing.space10),
            Flexible(
              child: Text(
                '正在加载 Agent…',
                style: textStyles.bodySmall.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      );
    }
    if (snapshot.hasError) {
      return Padding(
        padding: IdeSpacing.all16,
        child: Text(
          '无法加载 Agent：${snapshot.error}',
          style: textStyles.bodySmall.copyWith(color: colors.error),
        ),
      );
    }
    if (providers.isEmpty) {
      return Padding(
        padding: IdeSpacing.all16,
        child: Text(
          '没有已启用且受支持的 Agent provider。请先在 Settings > Agents 中启用。',
          style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: IdeSpacing.space10),
          child: Text(
            '请选择用于创建新 thread 的 Agent。',
            style: textStyles.bodySmall.copyWith(color: colors.textSecondary),
          ),
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: providers.length,
            separatorBuilder: (_, _) =>
                const SizedBox(height: IdeSpacing.space6),
            itemBuilder: (context, index) {
              final provider = providers[index];
              final selected = provider.id == _selectedProviderId;
              return Semantics(
                button: true,
                selected: selected,
                label: '使用 ${provider.displayName} 创建 thread',
                child: PaneInteractiveSurface(
                  key: ValueKey<String>(
                    'new-thread-provider-option-${provider.id}',
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedProviderId = provider.id;
                    });
                  },
                  selected: selected,
                  padding: const EdgeInsets.symmetric(
                    horizontal: IdeSpacing.space12,
                    vertical: IdeSpacing.space10,
                  ),
                  child: Row(
                    children: [
                      AgentProviderIcon(
                        providerId: provider.id,
                        kind: provider.kind,
                        size: 18,
                        color: selected ? colors.accent : colors.textSecondary,
                      ),
                      const SizedBox(width: IdeSpacing.space10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              provider.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyles.bodyMedium.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              _providerKindLabel(provider.kind),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: textStyles.caption.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (selected)
                        Icon(
                          Icons.check_rounded,
                          size: 17,
                          color: colors.accent,
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  AgentProviderConfig? _selectedProvider(List<AgentProviderConfig> providers) {
    for (final provider in providers) {
      if (provider.id == _selectedProviderId) {
        return provider;
      }
    }
    return null;
  }

  String _providerKindLabel(AgentProviderKind kind) {
    return switch (kind) {
      AgentProviderKind.codexAppServer => 'Codex app-server',
      AgentProviderKind.acp => 'Agent Client Protocol',
      AgentProviderKind.cursorAcp => 'Unavailable provider',
      AgentProviderKind.claudeCode => 'Claude Code CLI',
    };
  }
}

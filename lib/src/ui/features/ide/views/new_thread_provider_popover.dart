import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta_ui/zeta_ui.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

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
        final providers = snapshot.data ?? const <AgentProviderConfig>[];
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
                      context.l10n.newThreadSelectProvider,
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
                          child: Text(context.l10n.commonCancel),
                        ),
                        const SizedBox(width: IdeSpacing.space8),
                        sf.PrimaryButton(
                          key: const ValueKey<String>(
                            'new-thread-provider-confirm',
                          ),
                          onPressed: selectedProvider == null
                              ? null
                              : () =>
                                    sf.closeOverlay(context, selectedProvider),
                          size: sf.ButtonSize.small,
                          child: Text(context.l10n.projectNewSession),
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
            IdeBusySpinner(size: 18, color: colors.accent),
            const SizedBox(width: IdeSpacing.space10),
            Flexible(
              child: Text(
                context.l10n.newThreadLoadingAgents,
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
          context.l10n.newThreadCannotLoadAgents('${snapshot.error}'),
          style: textStyles.bodySmall.copyWith(color: colors.error),
        ),
      );
    }
    if (providers.isEmpty) {
      return Padding(
        padding: IdeSpacing.all16,
        child: Text(
          context.l10n.newThreadNoEnabledProviders,
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
            context.l10n.newThreadChooseAgent,
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
                label: context.l10n.newThreadUseProvider(provider.displayName),
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
                        child: Text(
                          provider.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: textStyles.identifier.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
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
}

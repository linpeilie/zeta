import 'package:flutter/material.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/features/agent/domain/agent_models.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/ide_session/domain/recent_project_summary.dart';
import 'package:zeta/src/ui/core/ide_chip.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_effects.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/rows/ide_row_divider.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

const int globalHomeRecentItemLimit = 5;

/// 首页 Provider 的归一化状态。
enum HomeProviderStatus {
  available,
  running,
  disabled,
  needsLogin,
  error,
  updateAvailable,
  detecting,
}

/// 首页消费的 Provider 轻量摘要。
final class HomeProviderSummary {
  const HomeProviderSummary({
    required this.id,
    required this.displayName,
    required this.vendor,
    required this.status,
    this.version,
  });

  factory HomeProviderSummary.fromManagedAgent(ManagedAgent agent) {
    return HomeProviderSummary(
      id: agent.definition.id,
      displayName: agent.definition.displayName,
      vendor: agent.definition.vendor,
      version: agent.currentVersion,
      status: _resolveProviderStatus(agent),
    );
  }

  final String id;
  final String displayName;
  final String vendor;
  final String? version;
  final HomeProviderStatus status;
}

/// 没有活动项目时显示的全局软件首页。
///
/// 本组件只消费不可变快照与回调，不负责文件系统、Provider 检测或会话刷新，
/// 因此可以安全运行在 Flutter Widget Previewer 中。
class GlobalHomePage extends StatelessWidget {
  const GlobalHomePage({
    required this.recentProjects,
    required this.recentThreads,
    required this.installedProviders,
    required this.onOpenProject,
    required this.onSelectProject,
    required this.onSelectThread,
    super.key,
    this.isLoadingRecentProjects = false,
    this.isLoadingRecentThreads = false,
    this.recentThreadsError,
    this.isLoadingProviders = false,
    this.providerError,
    this.now,
  });

  final List<RecentProjectSummary> recentProjects;
  final List<AgentThreadSummary> recentThreads;
  final List<HomeProviderSummary> installedProviders;
  final VoidCallback onOpenProject;
  final ValueChanged<String> onSelectProject;
  final ValueChanged<AgentThreadSummary> onSelectThread;
  final bool isLoadingRecentProjects;
  final bool isLoadingRecentThreads;
  final String? recentThreadsError;
  final bool isLoadingProviders;
  final String? providerError;
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return ColoredBox(
      key: const ValueKey<String>('global-home-page'),
      color: colors.canvasSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < IdeMetrics.mediumBreakpoint;
          final padding = compact
              ? IdeSpacing.pagePaddingCompact
              : IdeSpacing.pagePadding;
          return SingleChildScrollView(
            key: const ValueKey<String>('global-home-scroll-view'),
            padding: padding,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: IdeMetrics.settingsContentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _WelcomeHeader(
                      compact: compact,
                      onOpenProject: onOpenProject,
                    ),
                    const SizedBox(height: IdeSpacing.space20),
                    if (compact)
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildProjectsSection(context),
                          const SizedBox(height: IdeSpacing.space16),
                          _buildThreadsSection(context),
                        ],
                      )
                    else
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(child: _buildProjectsSection(context)),
                          const SizedBox(width: IdeSpacing.space16),
                          Expanded(child: _buildThreadsSection(context)),
                        ],
                      ),
                    const SizedBox(height: IdeSpacing.space16),
                    _buildProvidersSection(context),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildProjectsSection(BuildContext context) {
    final projects = recentProjects
        .take(globalHomeRecentItemLimit)
        .toList(growable: false);
    return _HomeSection(
      key: const ValueKey<String>('global-home-projects-section'),
      title: context.l10n.homeRecentProjects,
      loading: isLoadingRecentProjects,
      child: projects.isEmpty
          ? _HomeSectionState(
              key: const ValueKey<String>('global-home-projects-empty'),
              icon: Icons.folder_open_rounded,
              title: isLoadingRecentProjects
                  ? context.l10n.homeReadingRecentProjects
                  : context.l10n.homeNoRecentProjects,
              body: isLoadingRecentProjects
                  ? context.l10n.homeRecentProjectsAfterRestore
                  : context.l10n.homeRecentProjectsAfterOpen,
              loading: isLoadingRecentProjects,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < projects.length; index += 1)
                  _RecentProjectRow(
                    key: ValueKey<String>(
                      'global-home-project-${projects[index].path}',
                    ),
                    project: projects[index],
                    now: now ?? DateTime.now(),
                    showDivider: index < projects.length - 1,
                    onPressed: () => onSelectProject(projects[index].path),
                  ),
              ],
            ),
    );
  }

  Widget _buildThreadsSection(BuildContext context) {
    final threads = recentThreads
        .take(globalHomeRecentItemLimit)
        .toList(growable: false);
    return _HomeSection(
      key: const ValueKey<String>('global-home-threads-section'),
      title: context.l10n.homeRecentSessions,
      loading: isLoadingRecentThreads,
      warning: recentThreadsError == null
          ? null
          : context.l10n.homeRefreshFailed,
      warningTooltip: recentThreadsError,
      child: threads.isEmpty
          ? _HomeSectionState(
              key: const ValueKey<String>('global-home-threads-empty'),
              icon: recentThreadsError == null
                  ? Icons.forum_outlined
                  : Icons.error_outline_rounded,
              title: recentThreadsError != null
                  ? context.l10n.homeCannotRefreshSessions
                  : isLoadingRecentThreads
                  ? context.l10n.homeLoadingRecentSessions
                  : context.l10n.homeNoRecentSessions,
              body:
                  recentThreadsError ??
                  (isLoadingRecentThreads
                      ? context.l10n.homeSessionsCacheHint
                      : context.l10n.homeSessionsEmptyHint),
              loading: isLoadingRecentThreads,
              error: recentThreadsError != null,
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var index = 0; index < threads.length; index += 1)
                  _RecentThreadRow(
                    key: ValueKey<String>(
                      'global-home-thread-${threads[index].providerId}-${threads[index].id}',
                    ),
                    thread: threads[index],
                    now: now ?? DateTime.now(),
                    showDivider: index < threads.length - 1,
                    onPressed: () => onSelectThread(threads[index]),
                  ),
              ],
            ),
    );
  }

  Widget _buildProvidersSection(BuildContext context) {
    return _HomeSection(
      key: const ValueKey<String>('global-home-providers-section'),
      title: context.l10n.homeInstalledProviders,
      loading: isLoadingProviders,
      warning: providerError == null ? null : context.l10n.homeDetectionFailed,
      warningTooltip: providerError,
      child: installedProviders.isEmpty
          ? _HomeSectionState(
              key: const ValueKey<String>('global-home-providers-empty'),
              icon: providerError == null
                  ? Icons.extension_off_outlined
                  : Icons.error_outline_rounded,
              title: providerError != null
                  ? context.l10n.homeProviderDetectionFailedTitle
                  : isLoadingProviders
                  ? context.l10n.homeDetectingProviders
                  : context.l10n.homeNoInstalledProviders,
              body:
                  providerError ??
                  (isLoadingProviders
                      ? context.l10n.homeProvidersAfterDetect
                      : context.l10n.homeProvidersAfterInstall),
              loading: isLoadingProviders,
              error: providerError != null,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final split =
                    constraints.maxWidth >= IdeMetrics.stackedRowBreakpoint;
                final itemWidth = split
                    ? (constraints.maxWidth - IdeSpacing.space12) / 2
                    : constraints.maxWidth;
                return Padding(
                  padding: IdeSpacing.all12,
                  child: Wrap(
                    spacing: IdeSpacing.space12,
                    runSpacing: IdeSpacing.space8,
                    children: [
                      for (final provider in installedProviders)
                        SizedBox(
                          width: itemWidth,
                          child: _ProviderStatusItem(
                            key: ValueKey<String>(
                              'global-home-provider-${provider.id}',
                            ),
                            provider: provider,
                          ),
                        ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.compact, required this.onOpenProject});

  final bool compact;
  final VoidCallback onOpenProject;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final copy = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.homeWelcomeTitle,
          key: const ValueKey<String>('global-home-title'),
          style: textStyles.displayLarge,
        ),
        const SizedBox(height: IdeSpacing.space6),
        Text(
          context.l10n.homeWelcomeSubtitle,
          key: const ValueKey<String>('global-home-subtitle'),
          style: textStyles.bodyMedium.copyWith(color: colors.textSecondary),
        ),
      ],
    );
    final button = Semantics(
      button: true,
      label: context.l10n.homeOpenProjectFolder,
      child: sf.PrimaryButton(
        key: const ValueKey<String>('global-home-open-project'),
        onPressed: onOpenProject,
        size: sf.ButtonSize.small,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.folder_open_rounded, size: 16),
            const SizedBox(width: IdeSpacing.space6),
            Text(context.l10n.homeOpenProject),
          ],
        ),
      ),
    );

    return PanelCard(
      key: const ValueKey<String>('global-home-welcome'),
      color: colors.surfaceElevated,
      child: Padding(
        padding: IdeSpacing.all20,
        child: compact
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  copy,
                  const SizedBox(height: IdeSpacing.space16),
                  button,
                ],
              )
            : Row(
                children: [
                  Expanded(child: copy),
                  const SizedBox(width: IdeSpacing.space20),
                  button,
                ],
              ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  const _HomeSection({
    required this.title,
    required this.child,
    super.key,
    this.loading = false,
    this.warning,
    this.warningTooltip,
  });

  final String title;
  final Widget child;
  final bool loading;
  final String? warning;
  final String? warningTooltip;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return PanelCard(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: IdeSpacing.space12,
              vertical: IdeSpacing.space10,
            ),
            child: Row(
              children: [
                Expanded(child: Text(title, style: textStyles.sectionTitle)),
                if (warning != null)
                  IdeTooltip(
                    message: warningTooltip ?? warning!,
                    child: IdeChip(
                      label: warning!,
                      leadingIcon: Icons.warning_amber_rounded,
                      variant: IdeChipVariant.outline,
                    ),
                  ),
                if (loading) ...[
                  if (warning != null) const SizedBox(width: IdeSpacing.space8),
                  IdeBusySpinner(
                    key: ValueKey<String>('global-home-loading-$title'),
                    size: 14,
                    color: colors.accent,
                  ),
                ],
              ],
            ),
          ),
          const IdeRowDivider(),
          child,
        ],
      ),
    );
  }
}

class _RecentProjectRow extends StatelessWidget {
  const _RecentProjectRow({
    required this.project,
    required this.now,
    required this.showDivider,
    required this.onPressed,
    super.key,
  });

  final RecentProjectSummary project;
  final DateTime now;
  final bool showDivider;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final time = _relativeTime(project.lastOpenedAt, now);
    return IdeTooltip(
      message: project.path,
      child: IdeListRow(
        title: _fileName(project.path),
        subtitle: time == null ? project.path : '${project.path} · $time',
        leading: const Icon(Icons.folder_outlined),
        trailing: const Icon(Icons.chevron_right_rounded, size: 16),
        showDivider: showDivider,
        semanticLabel: context.l10n.homeOpenRecentProject(
          _fileName(project.path),
        ),
        onPressed: onPressed,
      ),
    );
  }
}

class _RecentThreadRow extends StatelessWidget {
  const _RecentThreadRow({
    required this.thread,
    required this.now,
    required this.showDivider,
    required this.onPressed,
    super.key,
  });

  final AgentThreadSummary thread;
  final DateTime now;
  final bool showDivider;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final metadata = <String>[
      _fileName(thread.projectPath),
      if (_relativeTime(thread.lastActiveAt, now) case final String value)
        value,
    ];
    return IdeListRow(
      title: thread.displayName,
      subtitle: metadata.join(' · '),
      leading: AgentProviderIcon(providerId: thread.providerId, size: 18),
      trailing: const Icon(Icons.chevron_right_rounded, size: 16),
      showDivider: showDivider,
      semanticLabel: context.l10n.homeOpenRecentSession(thread.displayName),
      onPressed: onPressed,
    );
  }
}

class _ProviderStatusItem extends StatelessWidget {
  const _ProviderStatusItem({required this.provider, super.key});

  final HomeProviderSummary provider;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final version = provider.version?.trim();
    return Semantics(
      label: context.l10n.homeCommaJoin(
        provider.displayName,
        _providerStatusLabel(context, provider.status),
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.controlSurface,
          border: Border.all(color: colors.borderSubtle),
          borderRadius: IdeRadius.allMedium,
        ),
        child: Padding(
          padding: IdeSpacing.all12,
          child: Row(
            children: [
              AgentProviderIcon(
                providerId: provider.id,
                size: 18,
                color: colors.textSecondary,
              ),
              const SizedBox(width: IdeSpacing.space10),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      provider.displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.identifier,
                    ),
                    Text(
                      version == null || version.isEmpty
                          ? provider.vendor
                          : '${provider.vendor} · $version',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: textStyles.meta.copyWith(
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: IdeSpacing.space8),
              IdeChip(
                label: _providerStatusLabel(context, provider.status),
                leadingIcon: _providerStatusIcon(provider.status),
                variant: _providerChipVariant(provider.status),
                selected:
                    provider.status == HomeProviderStatus.available ||
                    provider.status == HomeProviderStatus.running,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HomeSectionState extends StatelessWidget {
  const _HomeSectionState({
    required this.icon,
    required this.title,
    required this.body,
    super.key,
    this.loading = false,
    this.error = false,
  });

  final IconData icon;
  final String title;
  final String body;
  final bool loading;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = error ? colors.error : colors.textSecondary;
    return Padding(
      padding: IdeSpacing.all20,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (loading)
            IdeBusySpinner(size: 18, color: colors.accent)
          else
            Icon(icon, size: 18, color: foreground),
          const SizedBox(width: IdeSpacing.space10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: textStyles.rowTitle.copyWith(color: foreground),
                ),
                const SizedBox(height: IdeSpacing.space4),
                Text(
                  body,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: textStyles.bodySmall.copyWith(
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

HomeProviderStatus _resolveProviderStatus(ManagedAgent agent) {
  if (agent.installationState == AgentInstallationState.detecting) {
    return HomeProviderStatus.detecting;
  }
  if (!agent.enabled || agent.runtimeState == AgentRuntimeState.disabled) {
    return HomeProviderStatus.disabled;
  }
  if (agent.accountState == AgentAccountState.loggedOut ||
      agent.accountState == AgentAccountState.expired ||
      agent.accountState == AgentAccountState.unavailable) {
    return HomeProviderStatus.needsLogin;
  }
  if (agent.runtimeState == AgentRuntimeState.error ||
      agent.runtimeState == AgentRuntimeState.unavailable) {
    return HomeProviderStatus.error;
  }
  if (agent.runtimeState == AgentRuntimeState.running ||
      agent.runtimeState == AgentRuntimeState.starting ||
      agent.runtimeState == AgentRuntimeState.stopping) {
    return HomeProviderStatus.running;
  }
  if (agent.versionState == AgentVersionState.updateAvailable) {
    return HomeProviderStatus.updateAvailable;
  }
  return HomeProviderStatus.available;
}

String _providerStatusLabel(BuildContext context, HomeProviderStatus status) {
  final l10n = context.l10n;
  return switch (status) {
    HomeProviderStatus.available => l10n.homeProviderAvailable,
    HomeProviderStatus.running => l10n.homeProviderRunning,
    HomeProviderStatus.disabled => l10n.homeProviderDisabled,
    HomeProviderStatus.needsLogin => l10n.homeProviderNeedsLogin,
    HomeProviderStatus.error => l10n.homeProviderError,
    HomeProviderStatus.updateAvailable => l10n.homeProviderUpdateAvailable,
    HomeProviderStatus.detecting => l10n.homeProviderDetecting,
  };
}

IconData _providerStatusIcon(HomeProviderStatus status) => switch (status) {
  HomeProviderStatus.available => Icons.check_circle_outline_rounded,
  HomeProviderStatus.running => Icons.sync_rounded,
  HomeProviderStatus.disabled => Icons.pause_circle_outline_rounded,
  HomeProviderStatus.needsLogin => Icons.person_off_outlined,
  HomeProviderStatus.error => Icons.error_outline_rounded,
  HomeProviderStatus.updateAvailable => Icons.system_update_alt_rounded,
  HomeProviderStatus.detecting => Icons.search_rounded,
};

IdeChipVariant _providerChipVariant(HomeProviderStatus status) =>
    switch (status) {
      HomeProviderStatus.error => IdeChipVariant.destructive,
      HomeProviderStatus.needsLogin ||
      HomeProviderStatus.updateAvailable => IdeChipVariant.outline,
      HomeProviderStatus.disabled ||
      HomeProviderStatus.detecting => IdeChipVariant.ghost,
      HomeProviderStatus.available ||
      HomeProviderStatus.running => IdeChipVariant.primary,
    };

String _fileName(String path) {
  final parts = path
      .replaceAll('\\', '/')
      .split('/')
      .where((part) => part.isNotEmpty)
      .toList(growable: false);
  return parts.isEmpty ? path : parts.last;
}

String? _relativeTime(DateTime? value, DateTime now) {
  if (value == null) {
    return null;
  }
  final difference = now.difference(value);
  if (difference.isNegative || difference.inMinutes < 1) {
    return '刚刚';
  }
  if (difference.inHours < 1) {
    return '${difference.inMinutes} 分钟前';
  }
  if (difference.inDays < 1) {
    return '${difference.inHours} 小时前';
  }
  return '${difference.inDays} 天前';
}

import 'package:flutter/material.dart';

import 'package:zeta/src/features/agent/presentation/widgets/agent_provider_icon.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/ui/core/ide_button.dart';
import 'package:zeta/src/ui/core/ide_colors.dart';
import 'package:zeta/src/ui/core/ide_metrics.dart';
import 'package:zeta/src/ui/core/ide_spacing.dart';
import 'package:zeta/src/ui/core/ide_text_styles.dart';
import 'package:zeta/src/ui/core/pane_widgets.dart';
import 'package:zeta/src/ui/core/rows/ide_list_row.dart';
import 'package:zeta/src/ui/localization/app_localizations_x.dart';

/// 首页 Provider 行左侧图标的边长。
const double _providerLogoSize = 18;

/// 状态圆点的直径。
///
/// 小到只在余光里提供一点颜色：状态是「扫一眼确认没出事」的信息，不该像药丸
/// 徽章那样在右侧拉出一排色块，把注意力从 Provider 名字上夺走。
const double _statusDotSize = 6;

/// 标题区上方的留白（宽屏）。
///
/// 直接取两档 [IdeSpacing.space32]：这一页只有一个焦点，标题得先被空白托起来
/// 才立得住，页面级 padding 的 12px 远远不够。窄屏回落到一档。
const double _heroTopSpace = IdeSpacing.space32 * 2;

/// 首页 Provider 的归一化状态。
enum HomeProviderStatus {
  available,
  running,
  disabled,
  needsLogin,
  error,
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
/// 整页只有三样东西：一个被留白托起来的标题、一个打开项目的入口，以及一列
/// 已安装的 Provider。刻意**不做卡片**——首页没有需要互相区隔的并列区块，
/// 再画一圈描边只会凭空造出「这里有两个容器」的层级。近期项目与近期会话也
/// 不在这里重复：左侧 Projects 栏已经是它们的常驻入口。
///
/// 本组件只消费不可变快照与回调，不负责文件系统、Provider 检测或会话刷新，
/// 因此可以安全运行在 Flutter Widget Previewer 中。
class GlobalHomePage extends StatelessWidget {
  const GlobalHomePage({
    required this.installedProviders,
    required this.onOpenProject,
    super.key,
    this.isLoadingProviders = false,
    this.providerError,
  });

  final List<HomeProviderSummary> installedProviders;
  final VoidCallback onOpenProject;
  final bool isLoadingProviders;
  final String? providerError;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    return ColoredBox(
      key: const ValueKey<String>('global-home-page'),
      color: colors.canvasSurface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < IdeMetrics.mediumBreakpoint;
          return SingleChildScrollView(
            key: const ValueKey<String>('global-home-scroll-view'),
            padding: compact
                ? IdeSpacing.pagePaddingCompact
                : IdeSpacing.pagePadding,
            child: Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  maxWidth: IdeMetrics.homeContentMaxWidth,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      height: compact ? IdeSpacing.space32 : _heroTopSpace,
                    ),
                    _WelcomeHeader(onOpenProject: onOpenProject),
                    const SizedBox(height: IdeSpacing.space32),
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

  Widget _buildProvidersSection(BuildContext context) {
    final providers = installedProviders;
    return Column(
      key: const ValueKey<String>('global-home-providers-section'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ProvidersGroupHeader(
          loading: isLoadingProviders,
          error: providerError,
        ),
        if (providers.isEmpty)
          _ProvidersPlaceholder(
            key: const ValueKey<String>('global-home-providers-empty'),
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
            error: providerError != null,
          )
        else
          for (var index = 0; index < providers.length; index += 1)
            _ProviderRow(
              key: ValueKey<String>(
                'global-home-provider-${providers[index].id}',
              ),
              provider: providers[index],
              showDivider: index < providers.length - 1,
            ),
      ],
    );
  }
}

class _WelcomeHeader extends StatelessWidget {
  const _WelcomeHeader({required this.onOpenProject});

  final VoidCallback onOpenProject;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    // 标题 → 副标题 → 动作，三件事排成一条从上往下的读取路径。按钮压在副标题
    // 正下方而不是甩到右端：它是这句话的下一步，不是与标题并列的第二个焦点。
    return Column(
      key: const ValueKey<String>('global-home-welcome'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          context.l10n.homeWelcomeTitle,
          key: const ValueKey<String>('global-home-title'),
          style: textStyles.displayHero,
        ),
        const SizedBox(height: IdeSpacing.space8),
        Text(
          context.l10n.homeWelcomeSubtitle,
          key: const ValueKey<String>('global-home-subtitle'),
          style: textStyles.proseBody.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: IdeSpacing.space16),
        // 主色描边而不是实心大按钮：整页已经有一个绝对视觉中心（标题），实心
        // 蓝块会立刻变成第二个，还会把「欢迎」那句话压成它的说明文字。
        IdeButton.toolbar(
          key: const ValueKey<String>('global-home-open-project'),
          label: context.l10n.homeOpenProject,
          leadingIcon: Icons.folder_open_rounded,
          variant: IdeButtonVariant.accentOutline,
          semanticLabel: context.l10n.homeOpenProjectFolder,
          onPressed: onOpenProject,
        ),
      ],
    );
  }
}

/// Provider 列表的眉标题，右端挂检测中 / 检测失败两个非阻断提示。
class _ProvidersGroupHeader extends StatelessWidget {
  const _ProvidersGroupHeader({required this.loading, required this.error});

  final bool loading;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    return Padding(
      padding: IdeSpacing.settingsGroupTitlePadding,
      child: Row(
        children: [
          Expanded(
            child: Text(
              context.l10n.homeInstalledProviders,
              style: textStyles.groupTitle,
            ),
          ),
          if (error case final String message)
            IdeTooltip(
              message: message,
              child: Text(
                context.l10n.homeDetectionFailed,
                style: textStyles.meta.copyWith(color: colors.warning),
              ),
            ),
          if (loading) ...[
            if (error != null) const SizedBox(width: IdeSpacing.space8),
            IdeBusySpinner(
              key: const ValueKey<String>('global-home-providers-loading'),
              size: 12,
              color: colors.accent,
            ),
          ],
        ],
      ),
    );
  }
}

class _ProviderRow extends StatelessWidget {
  const _ProviderRow({
    required this.provider,
    required this.showDivider,
    super.key,
  });

  final HomeProviderSummary provider;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final version = provider.version?.trim();
    final statusLabel = _providerStatusLabel(context, provider.status);
    return IdeListRow(
      title: provider.displayName,
      subtitle: version == null || version.isEmpty
          ? provider.vendor
          : '${provider.vendor} · $version',
      // 图标锁进一个正方形槽：品牌 SVG 按高度缩放后，宽度会随各家 logo 的比例
      // 浮动（Codex 在 18 高时是 19.1 宽）。槽一旦不定宽，下面那条分隔线的缩进
      // 就对不上标题左边缘——那正是这条线唯一要做对的事。
      leading: SizedBox.square(
        dimension: _providerLogoSize,
        child: FittedBox(
          child: AgentProviderIcon(
            providerId: provider.id,
            size: _providerLogoSize,
            color: colors.textSecondary,
          ),
        ),
      ),
      trailing: _ProviderStatusIndicator(
        status: provider.status,
        label: statusLabel,
      ),
      showDivider: showDivider,
      // 线的起点推到标题左边缘：行内边距 + 图标宽 + 图标与文字的间隙。用 token
      // 相加而不是写死，改图标尺寸时对齐会自己跟上。
      dividerIndent: IdeSpacing.space10 + _providerLogoSize + IdeSpacing.space8,
      semanticLabel: context.l10n.homeCommaJoin(
        provider.displayName,
        statusLabel,
      ),
    );
  }
}

/// 状态圆点 + 灰色文字。
///
/// 取代原来的药丸徽章：一列全是「可用」的时候，色块面积等于噪音面积。圆点只
/// 在真出问题（需登录 / 错误）时才把颜色带到文字上，其余状态一律留在
/// [IdeTextStyles.meta] 的三级灰里。
class _ProviderStatusIndicator extends StatelessWidget {
  const _ProviderStatusIndicator({required this.status, required this.label});

  final HomeProviderStatus status;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final tone = _providerStatusTone(colors, status);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: _statusDotSize,
          height: _statusDotSize,
          decoration: BoxDecoration(color: tone.dot, shape: BoxShape.circle),
        ),
        const SizedBox(width: IdeSpacing.space6),
        Text(label, style: textStyles.meta.copyWith(color: tone.label)),
      ],
    );
  }
}

/// Provider 列表为空 / 检测失败时的平铺占位，不套卡片。
class _ProvidersPlaceholder extends StatelessWidget {
  const _ProvidersPlaceholder({
    required this.title,
    required this.body,
    super.key,
    this.error = false,
  });

  final String title;
  final String body;
  final bool error;

  @override
  Widget build(BuildContext context) {
    final colors = IdeColors.of(context);
    final textStyles = IdeTextStyles.of(context);
    final foreground = error ? colors.error : colors.textSecondary;
    return Padding(
      padding: IdeSpacing.vertical8,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: textStyles.rowTitle.copyWith(color: foreground)),
          const SizedBox(height: IdeSpacing.space4),
          Text(
            body,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: textStyles.bodySmall.copyWith(color: colors.textTertiary),
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
  // 「有新版本」不在首页出现：升级是 Agent 管理页的事，首页只回答「现在能不能
  // 用」。可更新的 Provider 依然是可用的，就按可用显示。
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
    HomeProviderStatus.detecting => l10n.homeProviderDetecting,
  };
}

({Color dot, Color label}) _providerStatusTone(
  IdeColors colors,
  HomeProviderStatus status,
) => switch (status) {
  HomeProviderStatus.available => (
    dot: colors.success,
    label: colors.textTertiary,
  ),
  HomeProviderStatus.running => (
    dot: colors.accent,
    label: colors.textTertiary,
  ),
  HomeProviderStatus.disabled || HomeProviderStatus.detecting => (
    dot: colors.textTertiary,
    label: colors.textTertiary,
  ),
  HomeProviderStatus.needsLogin => (dot: colors.warning, label: colors.warning),
  HomeProviderStatus.error => (dot: colors.error, label: colors.error),
};

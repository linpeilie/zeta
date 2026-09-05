import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/agent/application/conversation_slice/agent_conversation_region_state.dart';
import 'package:zeta/src/features/agent/presentation/widgets/agent_pane_text.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

void main() {
  final en = lookupAppLocalizations(const Locale('en'));
  final zh = lookupAppLocalizations(const Locale('zh'));

  group('planPreviewText', () {
    test('剥掉标题标记后取首个非空行', () {
      expect(planPreviewText('## 标题'), '标题');
    });

    test('空输入回落到 Plan', () {
      expect(planPreviewText(''), 'Plan');
      expect(planPreviewText('   \n  \n'), 'Plan');
    });
  });

  group('threadOpenStatusText', () {
    test('英文头栏文案走 l10n', () {
      expect(
        threadOpenStatusText(_header(AgentThreadOpenPhase.loadingHistory), en),
        'Loading thread history...',
      );
      expect(
        threadOpenStatusText(_header(AgentThreadOpenPhase.openFailed), en),
        'Thread open failed. Click this thread again to retry.',
      );
    });

    test('中文头栏文案走 l10n', () {
      expect(
        threadOpenStatusText(_header(AgentThreadOpenPhase.loadingHistory), zh),
        zh.agentThreadLoadingHistory,
      );
      expect(
        threadOpenStatusText(_header(AgentThreadOpenPhase.openFailed), zh),
        zh.agentThreadOpenFailedRetry,
      );
    });
  });

  group('token usage labels', () {
    const usage = AgentTokenUsage(
      totalTokens: 1300,
      inputTokens: 800,
      cachedInputTokens: 200,
      outputTokens: 280,
      modelContextWindow: 2000,
    );

    test('短标签与 tooltip 在英文下保持原口径', () {
      expect(turnTokenUsageLabel(usage, en), '1.3k tokens');
      expect(threadTotalTokenUsageLabel(usage, en), '1.3k tokens');
      expect(
        contextWindowTokenUsageTooltip(usage, en),
        'Usage: 65%\nUsed: 1.3k\nTotal: 2k',
      );
      expect(
        tokenUsageTooltip(usage, en),
        'Total: 1.3k\n'
        'Context window: 2k\n'
        'Input: 800\n'
        'Cached: 200\n'
        'Output: 280',
      );
    });

    test('短标签与 tooltip 在中文下走 l10n', () {
      expect(turnTokenUsageLabel(usage, zh), zh.agentTurnTokenUsage('1.3k'));
      expect(
        contextWindowTokenUsageTooltip(usage, zh),
        zh.agentTokenUsageContextTooltip('65', '1.3k', '2k'),
      );
      expect(
        tokenUsageTooltip(usage, zh),
        contains(zh.agentTokenUsageTotalLine('1.3k')),
      );
      expect(tokenUsageTooltip(null, zh), isEmpty);
      expect(turnTokenUsageLabel(null, zh), isNull);
    });
  });
}

AgentHeaderState _header(AgentThreadOpenPhase phase) {
  return AgentHeaderState(
    title: 't',
    threadOpenPhase: phase,
    systemNoticeLabel: null,
    statusCapsuleLabel: null,
    waitingOnApproval: false,
    waitingOnUserInput: false,
    showRunningIndicator: false,
    runningActivityLabel: null,
    segmentStartedAt: null,
    turnStartedAt: null,
    tokenUsage: null,
    isTurnRunning: false,
    isReadOnly: false,
    canFork: false,
    canRename: false,
    canArchive: false,
    isPlanMode: false,
  );
}

import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta_agent_core/zeta_agent_core.dart';
import 'package:zeta/src/features/desktop_notifications/domain/fallback_desktop_attention_text_catalog.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

void main() {
  test('AppDesktopAttentionTextCatalog matches ARB in both locales', () {
    final zh = AppDesktopAttentionTextCatalog(
      lookupAppLocalizations(ZetaLocalization.simplifiedChinese),
    );
    final en = AppDesktopAttentionTextCatalog(
      lookupAppLocalizations(ZetaLocalization.english),
    );
    const fallback = FallbackDesktopAttentionTextCatalog();

    expect(zh.titleFor(AgentAttentionKind.turnCompleted), '任务已完成');
    expect(en.titleFor(AgentAttentionKind.turnCompleted), 'Task completed');
    expect(
      fallback.titleFor(AgentAttentionKind.turnCompleted),
      zh.titleFor(AgentAttentionKind.turnCompleted),
    );
    expect(zh.sessionBody('zeta'), 'zeta · Agent 会话');
    expect(en.sessionBody('zeta'), 'zeta · Agent session');
    expect(fallback.linuxAction, zh.linuxAction);
    expect(en.linuxAction, 'Open Zeta');
  });
}

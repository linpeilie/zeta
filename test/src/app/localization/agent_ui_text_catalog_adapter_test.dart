import 'package:flutter_test/flutter_test.dart';
import 'package:zeta/src/app/localization/zeta_localization.dart';
import 'package:zeta/src/app/localization/zeta_text_catalogs.dart';
import 'package:zeta/src/features/agent/domain/fallback_agent_ui_text_catalog.dart';
import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

void main() {
  test('AppAgentUiTextCatalog thinking canary matches ARB', () {
    final zh = AppAgentUiTextCatalog(
      lookupAppLocalizations(ZetaLocalization.simplifiedChinese),
    );
    final en = AppAgentUiTextCatalog(
      lookupAppLocalizations(ZetaLocalization.english),
    );

    expect(zh.thinkingToolTitle, '思考');
    expect(en.thinkingToolTitle, 'Think');
    expect(
      const FallbackAgentUiTextCatalog().thinkingToolTitle,
      zh.thinkingToolTitle,
    );
  });
}

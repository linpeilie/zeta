import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/composition/zeta_environment_providers.dart';
import 'package:zeta/src/app/desktop_attention_slice/desktop_attention_providers.dart';
import 'package:zeta/src/app/localization/zeta_display_language_source.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/usage_statistics_slice/usage_statistics_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/agent_management/domain/agent_management_models.dart';
import 'package:zeta/src/features/desktop_notifications/domain/desktop_attention_models.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';

/// 测试用的 [MainApp]。
///
/// 和生产入口是同一个口径：**组合根只认 `overrides`**。测试安全边界全部由
/// [zetaTestComposition] 自动装上（内存存储、无头窗口、空 CLI 探测……），
/// 用例要换掉什么就覆盖对应的 provider。
///
/// 组合根会自动 `addTearDown(dispose)`，容器与三个切片组合随用例结束一起关。
MainApp zetaTestApp({Key? key, List<Override> overrides = const <Override>[]}) {
  return MainApp(
    key: key,
    composition: zetaTestComposition(overrides: overrides),
  );
}

/// 建一份测试组合根并登记 tear-down。
///
/// 需要 `takeStateSnapshot()` 或直接读容器的用例，自己拿这个返回值；只要 Widget 的
/// 用例用 [zetaTestApp] 即可。
///
/// 自动补 widget test 不能碰本机的那一组依赖，用例传了同一个 provider 时以用例为准：
///
/// 1. 内存文档存储——一个字节都不写 `~/.zeta`；
/// 2. 无头窗口、空桌面通知与任务栏指示——不打平台通道；
/// 3. 固定显示语言——第一帧就能挂有文字的 UI；
/// 4. 空的本机 CLI 探测、关闭用量自动刷新——不扫本机 Agent、不读用量历史；
/// 5. 外观仓库与系统字体目录——它们声明在 feature 的 application 层，那里够不到
///    `data` 实现，兜底值只能由调用方装（生产在 `lib/main.dart` 装同样两个）。
ZetaAppComposition zetaTestComposition({
  List<Override> overrides = const <Override>[],
}) {
  final composition = ZetaAppComposition.create(
    overrides: <Override>[
      ...ZetaStorageBindings.memory().providerOverrides,
      ..._testDefaultsNotCoveredBy(overrides),
      ...overrides,
    ],
  );
  addTearDown(composition.dispose);
  return composition;
}

/// 不接管原生窗口的窗口宿主。
///
/// 测试组合根默认就是 [HeadlessWindowHost]；只有要关掉窗口控制按钮时才需要显式装。
Override headlessWindowHost({bool showsWindowControls = true}) =>
    zetaWindowHostProvider.overrideWithValue(
      HeadlessWindowHost(showsWindowControls: showsWindowControls),
    );

/// widget test 不能碰本机的默认装配；用例已经覆盖的 provider 不再重复装。
List<Override> _testDefaultsNotCoveredBy(List<Override> overrides) {
  return <Override>[
    if (!_covers(overrides, zetaWindowHostProvider))
      zetaWindowHostProvider.overrideWithValue(HeadlessWindowHost()),
    if (!_covers(overrides, desktopNotificationServiceProvider))
      desktopNotificationServiceProvider.overrideWithValue(
        const NoopDesktopNotificationService(),
      ),
    if (!_covers(overrides, desktopAttentionIndicatorProvider))
      desktopAttentionIndicatorProvider.overrideWithValue(
        const NoopDesktopAttentionIndicator(),
      ),
    if (!_covers(overrides, zetaDisplayLanguageSourceProvider))
      zetaDisplayLanguageSourceProvider.overrideWith(
        (ref) => FixedDisplayLanguageSource(
          ref.watch(settingsFallbackLanguageProvider),
        ),
      ),
    if (!_covers(overrides, homeProviderDetectionLoaderProvider))
      homeProviderDetectionLoaderProvider.overrideWithValue(
        _loadNoInstalledHomeProviders,
      ),
    if (!_covers(overrides, agentUsageAutoRefreshEnabledProvider))
      agentUsageAutoRefreshEnabledProvider.overrideWithValue(false),
    if (!_covers(overrides, appearanceSettingsRepositoryProvider))
      appearanceSettingsRepositoryOverride(),
    if (!_covers(overrides, appearanceFontCatalogProvider))
      appearanceFontCatalogProvider.overrideWith(
        (ref) => DesktopSystemFontCatalogService(),
      ),
  ];
}

/// 用例的 `overrides` 是否已经覆盖了 [provider]。
///
/// Riverpod 对同一容器内的重复 override 直接断言失败，所以测试默认值必须让路。
/// `Override.origin` 由 Riverpod 标成 `@visibleForTesting`，专门给测试读被覆盖
/// 的那个 provider。
bool _covers<T>(List<Override> overrides, Provider<T> provider) {
  for (final override in overrides) {
    // ignore: invalid_use_of_visible_for_testing_member
    if (identical(override.origin, provider)) {
      return true;
    }
  }
  return false;
}

Future<List<ManagedAgent>> _loadNoInstalledHomeProviders() async =>
    const <ManagedAgent>[];

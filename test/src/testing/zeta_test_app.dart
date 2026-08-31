import 'package:flutter/widgets.dart' show Key;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:zeta/src/app/app.dart';
import 'package:zeta/src/app/composition/zeta_app_composition.dart';
import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/storage/zeta_storage_bindings.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/app/window/zeta_window_host.dart';
import 'package:zeta/src/features/settings/application/appearance_settings_notifier.dart';
import 'package:zeta/src/features/settings/data/system_font_catalog_service.dart';

/// 测试用的 [MainApp]。
///
/// 和生产入口是同一个口径：**组合根只认宿主模式，实现全部经 `overrides` 进
/// 容器**。这里不再有一排便利参数——那排参数本质上是把组合根的注入口重复实现了
/// 一遍，两边还会各自漂移。要换掉什么就覆盖对应的 provider。
///
/// 组合根会自动 `addTearDown(dispose)`，容器与三个切片组合随用例结束一起关。
MainApp zetaTestApp({
  Key? key,
  ZetaHostMode hostMode = ZetaHostMode.ephemeral,
  List<Override> overrides = const <Override>[],
}) {
  return MainApp(
    key: key,
    composition: zetaTestComposition(hostMode: hostMode, overrides: overrides),
  );
}

/// 建一份测试组合根并登记 tear-down。
///
/// 需要 `takeStateSnapshot()` 或直接读容器的用例，自己拿这个返回值；只要 Widget 的
/// 用例用 [zetaTestApp] 即可。
///
/// 自动补两类 ephemeral 宿主装配，用例传了同一个 provider 时以用例为准：
///
/// 1. 内存文档存储——`ephemeral` 一个字节都不写 `~/.zeta`；
/// 2. 外观仓库与系统字体目录——它们声明在 feature 的 application 层，那里够不到
///    `data` 实现，兜底值只能由调用方装（生产在 `lib/main.dart` 装同样两个）。
ZetaAppComposition zetaTestComposition({
  ZetaHostMode hostMode = ZetaHostMode.ephemeral,
  List<Override> overrides = const <Override>[],
}) {
  final composition = ZetaAppComposition.create(
    hostMode: hostMode,
    overrides: <Override>[
      ...ZetaStorageBindings.memory().providerOverrides,
      ..._appearanceDefaultsNotCoveredBy(overrides),
      ...overrides,
    ],
  );
  addTearDown(composition.dispose);
  return composition;
}

/// 不接管原生窗口的窗口宿主。
///
/// `ephemeral` 本来就是这个默认值；只有要关掉窗口控制按钮时才需要显式装。
Override headlessWindowHost({bool showsWindowControls = true}) =>
    zetaWindowHostProvider.overrideWithValue(
      HeadlessWindowHost(showsWindowControls: showsWindowControls),
    );

/// 补上用例没有自己装的外观依赖。
///
/// Riverpod 对同一容器内的重复 override 直接断言失败，因此不能无条件装——先拿
/// 用例自己的 override 开一个临时容器探一下：读得出来就说明用例装过了。两个
/// provider 的兜底都是 fail-closed 抛错，"读得出来"和"被覆盖过"是同一件事。
List<Override> _appearanceDefaultsNotCoveredBy(List<Override> overrides) {
  final probe = ProviderContainer(
    overrides: <Override>[
      ...ZetaStorageBindings.memory().providerOverrides,
      ...overrides,
    ],
  );
  try {
    return <Override>[
      if (!_resolves(probe, appearanceSettingsRepositoryProvider))
        appearanceSettingsRepositoryOverride(),
      if (!_resolves(probe, appearanceFontCatalogProvider))
        appearanceFontCatalogProvider.overrideWith(
          (ref) => DesktopSystemFontCatalogService(),
        ),
    ];
  } finally {
    probe.dispose();
  }
}

bool _resolves<T>(ProviderContainer probe, Provider<T> provider) {
  try {
    probe.read(provider);
    return true;
  } on Object {
    return false;
  }
}

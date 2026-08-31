import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/app/composition/zeta_host_mode.dart';
import 'package:zeta/src/app/storage/zeta_store_providers.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';
import 'package:zeta/src/features/settings/presentation/settings_slice/settings_slice_providers.dart';

/// 显示语言从哪里来。
///
/// 取代了组合根上的三个参数（`fallbackLanguage` / `displayLanguageOverride` /
/// `waitForGeneralSettings`）。那三个开关组合出来只有两种真实行为，与其让调用方
/// 拼开关、由组合根再解一遍，不如让它们各自成为一个实现：
///
/// - [GeneralSettingsDisplayLanguageSource]：等持久化的常规设置读完再冻结语言。
///   生产路径唯一正确的做法——先挂 UI 再跳变，用户会看到文案闪一下。
/// - [FixedDisplayLanguageSource]：语言已经定了，第一帧就能挂有文字的 UI。
///
/// 语言一旦冻结就不再变（见 `ZetaAppComposition.frozenDisplayLocale`），因此这
/// 里只需回答一次。
abstract interface class ZetaDisplayLanguageSource {
  /// 无需等待即可确定的语言；返回 null 表示必须 await [resolve]。
  ///
  /// 非 null 时组合根同步装配本地化运行时，`isReady` 在第一帧就是 true。
  AppLanguage? get eagerLanguage;

  /// 解析最终的显示语言。
  Future<AppLanguage> resolve();
}

/// 等常规设置读完再定显示语言。
final class GeneralSettingsDisplayLanguageSource
    implements ZetaDisplayLanguageSource {
  const GeneralSettingsDisplayLanguageSource(this._loadAppLanguage);

  final Future<AppLanguage> Function() _loadAppLanguage;

  @override
  AppLanguage? get eagerLanguage => null;

  @override
  Future<AppLanguage> resolve() => _loadAppLanguage();
}

/// 语言已经定了，不等任何 IO。
final class FixedDisplayLanguageSource implements ZetaDisplayLanguageSource {
  const FixedDisplayLanguageSource(this.language);

  final AppLanguage language;

  @override
  AppLanguage? get eagerLanguage => language;

  @override
  Future<AppLanguage> resolve() async => language;
}

/// 当前的显示语言来源。
///
/// 默认按宿主模式选：`local` 等常规设置，`ephemeral` 直接用
/// [settingsFallbackLanguageProvider]（也就是常规设置损坏时的兜底语言）。要在
/// 测试里验证"等待常规设置"这段过程，就覆盖成
/// [GeneralSettingsDisplayLanguageSource]。
final zetaDisplayLanguageSourceProvider = Provider<ZetaDisplayLanguageSource>((
  ref,
) {
  if (!ref.watch(zetaHostModeProvider).waitsForPersistedDisplayLanguage) {
    return FixedDisplayLanguageSource(
      ref.watch(settingsFallbackLanguageProvider),
    );
  }
  return _generalSettingsSource(ref);
}, name: 'zetaDisplayLanguageSource');

/// 等常规设置读完再冻结显示语言。
///
/// `local` 宿主本来就是这个默认值；这个 override 是给"要验证等待过程"的
/// ephemeral 用例用的。
Override waitForGeneralSettingsDisplayLanguage() =>
    zetaDisplayLanguageSourceProvider.overrideWith(_generalSettingsSource);

GeneralSettingsDisplayLanguageSource _generalSettingsSource(Ref ref) {
  return GeneralSettingsDisplayLanguageSource(
    () async => (await ref.read(generalSettingsSliceStoreProvider).initialLoad)
        .appLanguage,
  );
}

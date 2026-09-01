import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
import 'package:zeta/src/features/settings/domain/app_language.dart';

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
/// 生产默认等常规设置读完再冻结，避免先按兜底语言挂一次 UI 再跳变。
/// widget test 由 `zetaTestComposition` 换成 [FixedDisplayLanguageSource]，
/// 第一帧就能挂有文字的 UI；要验证等待过程，覆盖成
/// [waitForGeneralSettingsDisplayLanguage]。
final zetaDisplayLanguageSourceProvider = Provider<ZetaDisplayLanguageSource>(
  _generalSettingsSource,
  name: 'zetaDisplayLanguageSource',
);

/// 等常规设置读完再冻结显示语言。
///
/// 生产本来就是这个默认值；这个 override 是给"要验证等待过程"的测试用例用的。
Override waitForGeneralSettingsDisplayLanguage() =>
    zetaDisplayLanguageSourceProvider.overrideWith(_generalSettingsSource);

GeneralSettingsDisplayLanguageSource _generalSettingsSource(Ref ref) {
  return GeneralSettingsDisplayLanguageSource(
    () async =>
        (await ref.read(generalSettingsSliceProvider.notifier).initialLoad)
            .appLanguage,
  );
}

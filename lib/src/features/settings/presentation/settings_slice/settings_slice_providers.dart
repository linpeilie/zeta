import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:zeta/src/features/settings/application/settings_slice/general_settings_slice_notifier.dart';
import 'package:zeta/src/features/settings/domain/general_settings.dart';

/// general 切片已应用设置 selector。
final generalSettingsSliceValueProvider = Provider<GeneralSettings>(
  (ref) =>
      ref.watch(generalSettingsSliceProvider.select((state) => state.settings)),
  name: 'generalSettingsSliceValue',
);

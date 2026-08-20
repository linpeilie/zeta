import 'package:app_ui/app_ui.dart';

/// Extension on [BuildContext] for easy access to custom theme tokens.
extension AppThemeBuildContext on BuildContext {
  /// Returns the [AppColors] from the current theme.
  AppColors get appColors => Theme.of(this).extension<AppColors>()!;

  /// Returns the [AppSpacing] from the current theme.
  AppSpacing get appSpacing => Theme.of(this).extension<AppSpacing>()!;

  /// Returns the [AppMetrics] from the current theme.
  AppMetrics get appMetrics => Theme.of(this).extension<AppMetrics>()!;

  /// Returns the [AppRadii] from the current theme.
  AppRadii get appRadii => Theme.of(this).extension<AppRadii>()!;

  /// Returns the [AppEffects] from the current theme.
  AppEffects get appEffects => Theme.of(this).extension<AppEffects>()!;

  /// Returns the [AppMotion] from the current theme.
  AppMotion get appMotion => Theme.of(this).extension<AppMotion>()!;

  /// Returns semantic desktop typography from the current theme.
  AppTypography get appTypography => Theme.of(this).extension<AppTypography>()!;

  /// Returns the [AppTextStyles] from the current theme.
  AppTextStyles get appTextStyles => Theme.of(this).extension<AppTextStyles>()!;
}

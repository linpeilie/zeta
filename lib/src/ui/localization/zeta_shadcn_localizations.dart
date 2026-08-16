import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:shadcn_flutter/shadcn_flutter.dart' as sf;

import 'package:zeta/src/ui/localization/generated/app_localizations.dart';

/// Zeta 自有的 [sf.ShadcnLocalizations] 适配器。
///
/// 静态文案走 [AppLocalizations]；数值与日期格式保持语言无关，避免违反 D6。
final class ZetaShadcnLocalizations extends sf.ShadcnLocalizations {
  ZetaShadcnLocalizations(this._l10n, [super.locale = 'en']);

  final AppLocalizations _l10n;

  static const LocalizationsDelegate<sf.ShadcnLocalizations> delegate =
      ZetaShadcnLocalizationsDelegate();

  static String formatInvariantNumber(double value) {
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toString();
  }

  @override
  String get formNotEmpty => _l10n.shadcnFormNotEmpty;

  @override
  String get invalidValue => _l10n.shadcnInvalidValue;

  @override
  String get invalidEmail => _l10n.shadcnInvalidEmail;

  @override
  String get invalidURL => _l10n.shadcnInvalidURL;

  @override
  String formLessThan(double value) =>
      _l10n.shadcnFormLessThan(formatInvariantNumber(value));

  @override
  String formGreaterThan(double value) =>
      _l10n.shadcnFormGreaterThan(formatInvariantNumber(value));

  @override
  String formLessThanOrEqualTo(double value) =>
      _l10n.shadcnFormLessThanOrEqualTo(formatInvariantNumber(value));

  @override
  String formGreaterThanOrEqualTo(double value) =>
      _l10n.shadcnFormGreaterThanOrEqualTo(formatInvariantNumber(value));

  @override
  String get formPhoneNumberInvalid => _l10n.shadcnFormPhoneNumberInvalid;

  @override
  String get formPhoneNumberEmpty => _l10n.shadcnFormPhoneNumberEmpty;

  @override
  String formBetweenInclusively(double min, double max) =>
      _l10n.shadcnFormBetweenInclusively(
        formatInvariantNumber(min),
        formatInvariantNumber(max),
      );

  @override
  String formBetweenExclusively(double min, double max) =>
      _l10n.shadcnFormBetweenExclusively(
        formatInvariantNumber(min),
        formatInvariantNumber(max),
      );

  @override
  String formLengthLessThan(int value) =>
      _l10n.shadcnFormLengthLessThan('$value');

  @override
  String formLengthGreaterThan(int value) =>
      _l10n.shadcnFormLengthGreaterThan('$value');

  @override
  String get formPasswordDigits => _l10n.shadcnFormPasswordDigits;

  @override
  String get formPasswordLowercase => _l10n.shadcnFormPasswordLowercase;

  @override
  String get formPasswordUppercase => _l10n.shadcnFormPasswordUppercase;

  @override
  String get formPasswordSpecial => _l10n.shadcnFormPasswordSpecial;

  @override
  String get commandSearch => _l10n.shadcnCommandSearch;

  @override
  String get commandEmpty => _l10n.shadcnCommandEmpty;

  @override
  String get datePickerSelectYear => _l10n.shadcnDatePickerSelectYear;

  @override
  String get abbreviatedMonday => _l10n.shadcnAbbreviatedMonday;

  @override
  String get abbreviatedTuesday => _l10n.shadcnAbbreviatedTuesday;

  @override
  String get abbreviatedWednesday => _l10n.shadcnAbbreviatedWednesday;

  @override
  String get abbreviatedThursday => _l10n.shadcnAbbreviatedThursday;

  @override
  String get abbreviatedFriday => _l10n.shadcnAbbreviatedFriday;

  @override
  String get abbreviatedSaturday => _l10n.shadcnAbbreviatedSaturday;

  @override
  String get abbreviatedSunday => _l10n.shadcnAbbreviatedSunday;

  @override
  String get monthJanuary => _l10n.shadcnMonthJanuary;

  @override
  String get monthFebruary => _l10n.shadcnMonthFebruary;

  @override
  String get monthMarch => _l10n.shadcnMonthMarch;

  @override
  String get monthApril => _l10n.shadcnMonthApril;

  @override
  String get monthMay => _l10n.shadcnMonthMay;

  @override
  String get monthJune => _l10n.shadcnMonthJune;

  @override
  String get monthJuly => _l10n.shadcnMonthJuly;

  @override
  String get monthAugust => _l10n.shadcnMonthAugust;

  @override
  String get monthSeptember => _l10n.shadcnMonthSeptember;

  @override
  String get monthOctober => _l10n.shadcnMonthOctober;

  @override
  String get monthNovember => _l10n.shadcnMonthNovember;

  @override
  String get monthDecember => _l10n.shadcnMonthDecember;

  @override
  String get abbreviatedJanuary => _l10n.shadcnAbbreviatedJanuary;

  @override
  String get abbreviatedFebruary => _l10n.shadcnAbbreviatedFebruary;

  @override
  String get abbreviatedMarch => _l10n.shadcnAbbreviatedMarch;

  @override
  String get abbreviatedApril => _l10n.shadcnAbbreviatedApril;

  @override
  String get abbreviatedMay => _l10n.shadcnAbbreviatedMay;

  @override
  String get abbreviatedJune => _l10n.shadcnAbbreviatedJune;

  @override
  String get abbreviatedJuly => _l10n.shadcnAbbreviatedJuly;

  @override
  String get abbreviatedAugust => _l10n.shadcnAbbreviatedAugust;

  @override
  String get abbreviatedSeptember => _l10n.shadcnAbbreviatedSeptember;

  @override
  String get abbreviatedOctober => _l10n.shadcnAbbreviatedOctober;

  @override
  String get abbreviatedNovember => _l10n.shadcnAbbreviatedNovember;

  @override
  String get abbreviatedDecember => _l10n.shadcnAbbreviatedDecember;

  @override
  String get buttonCancel => _l10n.shadcnButtonCancel;

  @override
  String get buttonSave => _l10n.shadcnButtonSave;

  @override
  String get timeHour => _l10n.shadcnTimeHour;

  @override
  String get timeMinute => _l10n.shadcnTimeMinute;

  @override
  String get timeSecond => _l10n.shadcnTimeSecond;

  @override
  String get timeAM => _l10n.shadcnTimeAM;

  @override
  String get timePM => _l10n.shadcnTimePM;

  @override
  String get colorRed => _l10n.shadcnColorRed;

  @override
  String get colorGreen => _l10n.shadcnColorGreen;

  @override
  String get colorBlue => _l10n.shadcnColorBlue;

  @override
  String get colorAlpha => _l10n.shadcnColorAlpha;

  @override
  String get colorHue => _l10n.shadcnColorHue;

  @override
  String get colorSaturation => _l10n.shadcnColorSaturation;

  @override
  String get colorValue => _l10n.shadcnColorValue;

  @override
  String get colorLightness => _l10n.shadcnColorLightness;

  @override
  String get menuCut => _l10n.shadcnMenuCut;

  @override
  String get menuCopy => _l10n.shadcnMenuCopy;

  @override
  String get menuPaste => _l10n.shadcnMenuPaste;

  @override
  String get menuSelectAll => _l10n.shadcnMenuSelectAll;

  @override
  String get menuUndo => _l10n.shadcnMenuUndo;

  @override
  String get menuRedo => _l10n.shadcnMenuRedo;

  @override
  String get menuDelete => _l10n.shadcnMenuDelete;

  @override
  String get menuShare => _l10n.shadcnMenuShare;

  @override
  String get menuSearchWeb => _l10n.shadcnMenuSearchWeb;

  @override
  String get menuLiveTextInput => _l10n.shadcnMenuLiveTextInput;

  @override
  String get placeholderDatePicker => _l10n.shadcnPlaceholderDatePicker;

  @override
  String get placeholderTimePicker => _l10n.shadcnPlaceholderTimePicker;

  @override
  String get placeholderColorPicker => _l10n.shadcnPlaceholderColorPicker;

  @override
  String get buttonPrevious => _l10n.shadcnButtonPrevious;

  @override
  String get buttonNext => _l10n.shadcnButtonNext;

  @override
  String get refreshTriggerPull => _l10n.shadcnRefreshTriggerPull;

  @override
  String get refreshTriggerRelease => _l10n.shadcnRefreshTriggerRelease;

  @override
  String get refreshTriggerRefreshing => _l10n.shadcnRefreshTriggerRefreshing;

  @override
  String get refreshTriggerComplete => _l10n.shadcnRefreshTriggerComplete;

  @override
  String get colorPickerTabRecent => _l10n.shadcnColorPickerTabRecent;

  @override
  String get colorPickerTabRGB => _l10n.shadcnColorPickerTabRGB;

  @override
  String get colorPickerTabHSV => _l10n.shadcnColorPickerTabHSV;

  @override
  String get colorPickerTabHSL => _l10n.shadcnColorPickerTabHSL;

  @override
  String get colorPickerTabHEX => _l10n.shadcnColorPickerTabHEX;

  @override
  String get commandMoveUp => _l10n.shadcnCommandMoveUp;

  @override
  String get commandMoveDown => _l10n.shadcnCommandMoveDown;

  @override
  String get commandActivate => _l10n.shadcnCommandActivate;

  @override
  String dataTableSelectedRows(int count, int total) =>
      _l10n.shadcnDataTableSelectedRows('$count', '$total');

  @override
  String get dataTableNext => _l10n.shadcnDataTableNext;

  @override
  String get dataTablePrevious => _l10n.shadcnDataTablePrevious;

  @override
  String get dataTableColumns => _l10n.shadcnDataTableColumns;

  @override
  String get timeDaysAbbreviation => _l10n.shadcnTimeDaysAbbreviation;

  @override
  String get timeHoursAbbreviation => _l10n.shadcnTimeHoursAbbreviation;

  @override
  String get timeMinutesAbbreviation => _l10n.shadcnTimeMinutesAbbreviation;

  @override
  String get timeSecondsAbbreviation => _l10n.shadcnTimeSecondsAbbreviation;

  @override
  String get placeholderDurationPicker => _l10n.shadcnPlaceholderDurationPicker;

  @override
  String get durationDay => _l10n.shadcnDurationDay;

  @override
  String get durationHour => _l10n.shadcnDurationHour;

  @override
  String get durationMinute => _l10n.shadcnDurationMinute;

  @override
  String get durationSecond => _l10n.shadcnDurationSecond;
}

/// 覆盖 en / zh 的 shadcn 本地化 delegate，须排在包内英语 delegate 之前。
final class ZetaShadcnLocalizationsDelegate
    extends LocalizationsDelegate<sf.ShadcnLocalizations> {
  const ZetaShadcnLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) {
    return locale.languageCode == 'en' || locale.languageCode == 'zh';
  }

  @override
  Future<sf.ShadcnLocalizations> load(Locale locale) {
    return SynchronousFuture<sf.ShadcnLocalizations>(
      ZetaShadcnLocalizations(
        lookupAppLocalizations(locale),
        locale.toLanguageTag(),
      ),
    );
  }

  @override
  bool shouldReload(covariant ZetaShadcnLocalizationsDelegate old) => false;
}

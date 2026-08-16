// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Zeta';

  @override
  String localizationContractGreeting(String name) {
    return 'Hello $name';
  }

  @override
  String get shadcnFormNotEmpty => 'This field cannot be empty';

  @override
  String get shadcnInvalidValue => 'Invalid value';

  @override
  String get shadcnInvalidEmail => 'Invalid email';

  @override
  String get shadcnInvalidURL => 'Invalid URL';

  @override
  String shadcnFormLessThan(String value) {
    return 'Must be less than $value';
  }

  @override
  String shadcnFormGreaterThan(String value) {
    return 'Must be greater than $value';
  }

  @override
  String shadcnFormLessThanOrEqualTo(String value) {
    return 'Must be less than or equal to $value';
  }

  @override
  String shadcnFormGreaterThanOrEqualTo(String value) {
    return 'Must be greater than or equal to $value';
  }

  @override
  String get shadcnFormPhoneNumberInvalid => 'Phone number is invalid';

  @override
  String get shadcnFormPhoneNumberEmpty => 'Phone number is required';

  @override
  String shadcnFormBetweenInclusively(String min, String max) {
    return 'Must be between $min and $max (inclusive)';
  }

  @override
  String shadcnFormBetweenExclusively(String min, String max) {
    return 'Must be between $min and $max (exclusive)';
  }

  @override
  String shadcnFormLengthLessThan(String value) {
    return 'Must be at least $value characters';
  }

  @override
  String shadcnFormLengthGreaterThan(String value) {
    return 'Must be at most $value characters';
  }

  @override
  String get shadcnFormPasswordDigits => 'Must contain at least one digit';

  @override
  String get shadcnFormPasswordLowercase =>
      'Must contain at least one lowercase letter';

  @override
  String get shadcnFormPasswordUppercase =>
      'Must contain at least one uppercase letter';

  @override
  String get shadcnFormPasswordSpecial =>
      'Must contain at least one special character';

  @override
  String get shadcnCommandSearch => 'Type a command or search...';

  @override
  String get shadcnCommandEmpty => 'No results found.';

  @override
  String get shadcnCommandMoveUp => 'Move Up';

  @override
  String get shadcnCommandMoveDown => 'Move Down';

  @override
  String get shadcnCommandActivate => 'Select';

  @override
  String get shadcnDatePickerSelectYear => 'Select a year';

  @override
  String get shadcnPlaceholderDatePicker => 'Select a date';

  @override
  String get shadcnPlaceholderTimePicker => 'Select a time';

  @override
  String get shadcnPlaceholderColorPicker => 'Select a color';

  @override
  String get shadcnPlaceholderDurationPicker => 'Select a duration';

  @override
  String get shadcnButtonCancel => 'Cancel';

  @override
  String get shadcnButtonSave => 'Save';

  @override
  String get shadcnButtonPrevious => 'Previous';

  @override
  String get shadcnButtonNext => 'Next';

  @override
  String get shadcnTimeHour => 'Hour';

  @override
  String get shadcnTimeMinute => 'Minute';

  @override
  String get shadcnTimeSecond => 'Second';

  @override
  String get shadcnTimeAM => 'AM';

  @override
  String get shadcnTimePM => 'PM';

  @override
  String get shadcnColorRed => 'Red';

  @override
  String get shadcnColorGreen => 'Green';

  @override
  String get shadcnColorBlue => 'Blue';

  @override
  String get shadcnColorAlpha => 'Alpha';

  @override
  String get shadcnColorHue => 'Hue';

  @override
  String get shadcnColorSaturation => 'Sat';

  @override
  String get shadcnColorValue => 'Val';

  @override
  String get shadcnColorLightness => 'Lum';

  @override
  String get shadcnMenuCut => 'Cut';

  @override
  String get shadcnMenuCopy => 'Copy';

  @override
  String get shadcnMenuPaste => 'Paste';

  @override
  String get shadcnMenuSelectAll => 'Select All';

  @override
  String get shadcnMenuUndo => 'Undo';

  @override
  String get shadcnMenuRedo => 'Redo';

  @override
  String get shadcnMenuDelete => 'Delete';

  @override
  String get shadcnMenuShare => 'Share';

  @override
  String get shadcnMenuSearchWeb => 'Search Web';

  @override
  String get shadcnMenuLiveTextInput => 'Live Text Input';

  @override
  String get shadcnRefreshTriggerPull => 'Pull to refresh';

  @override
  String get shadcnRefreshTriggerRelease => 'Release to refresh';

  @override
  String get shadcnRefreshTriggerRefreshing => 'Refreshing...';

  @override
  String get shadcnRefreshTriggerComplete => 'Refresh complete';

  @override
  String get shadcnColorPickerTabRecent => 'Recent';

  @override
  String get shadcnColorPickerTabRGB => 'RGB';

  @override
  String get shadcnColorPickerTabHSV => 'HSV';

  @override
  String get shadcnColorPickerTabHSL => 'HSL';

  @override
  String get shadcnColorPickerTabHEX => 'HEX';

  @override
  String shadcnDataTableSelectedRows(String count, String total) {
    return '$count of $total row(s) selected.';
  }

  @override
  String get shadcnDataTableNext => 'Next';

  @override
  String get shadcnDataTablePrevious => 'Previous';

  @override
  String get shadcnDataTableColumns => 'Columns';

  @override
  String get shadcnTimeDaysAbbreviation => 'DD';

  @override
  String get shadcnTimeHoursAbbreviation => 'HH';

  @override
  String get shadcnTimeMinutesAbbreviation => 'MM';

  @override
  String get shadcnTimeSecondsAbbreviation => 'SS';

  @override
  String get shadcnDurationDay => 'Day';

  @override
  String get shadcnDurationHour => 'Hour';

  @override
  String get shadcnDurationMinute => 'Minute';

  @override
  String get shadcnDurationSecond => 'Second';

  @override
  String get shadcnAbbreviatedMonday => 'Mo';

  @override
  String get shadcnAbbreviatedTuesday => 'Tu';

  @override
  String get shadcnAbbreviatedWednesday => 'We';

  @override
  String get shadcnAbbreviatedThursday => 'Th';

  @override
  String get shadcnAbbreviatedFriday => 'Fr';

  @override
  String get shadcnAbbreviatedSaturday => 'Sa';

  @override
  String get shadcnAbbreviatedSunday => 'Su';

  @override
  String get shadcnMonthJanuary => 'January';

  @override
  String get shadcnMonthFebruary => 'February';

  @override
  String get shadcnMonthMarch => 'March';

  @override
  String get shadcnMonthApril => 'April';

  @override
  String get shadcnMonthMay => 'May';

  @override
  String get shadcnMonthJune => 'June';

  @override
  String get shadcnMonthJuly => 'July';

  @override
  String get shadcnMonthAugust => 'August';

  @override
  String get shadcnMonthSeptember => 'September';

  @override
  String get shadcnMonthOctober => 'October';

  @override
  String get shadcnMonthNovember => 'November';

  @override
  String get shadcnMonthDecember => 'December';

  @override
  String get shadcnAbbreviatedJanuary => 'Jan';

  @override
  String get shadcnAbbreviatedFebruary => 'Feb';

  @override
  String get shadcnAbbreviatedMarch => 'Mar';

  @override
  String get shadcnAbbreviatedApril => 'Apr';

  @override
  String get shadcnAbbreviatedMay => 'May';

  @override
  String get shadcnAbbreviatedJune => 'Jun';

  @override
  String get shadcnAbbreviatedJuly => 'Jul';

  @override
  String get shadcnAbbreviatedAugust => 'Aug';

  @override
  String get shadcnAbbreviatedSeptember => 'Sep';

  @override
  String get shadcnAbbreviatedOctober => 'Oct';

  @override
  String get shadcnAbbreviatedNovember => 'Nov';

  @override
  String get shadcnAbbreviatedDecember => 'Dec';
}

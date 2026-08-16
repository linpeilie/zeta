import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh'),
  ];

  /// Application window title and brand name. Keep as Zeta.
  ///
  /// In en, this message translates to:
  /// **'Zeta'**
  String get appTitle;

  /// Contract-only greeting used to lock placeholder generation.
  ///
  /// In en, this message translates to:
  /// **'Hello {name}'**
  String localizationContractGreeting(String name);

  /// shadcn form empty validation
  ///
  /// In en, this message translates to:
  /// **'This field cannot be empty'**
  String get shadcnFormNotEmpty;

  /// shadcn generic invalid value
  ///
  /// In en, this message translates to:
  /// **'Invalid value'**
  String get shadcnInvalidValue;

  /// shadcn email validation
  ///
  /// In en, this message translates to:
  /// **'Invalid email'**
  String get shadcnInvalidEmail;

  /// shadcn URL validation
  ///
  /// In en, this message translates to:
  /// **'Invalid URL'**
  String get shadcnInvalidURL;

  /// shadcn less-than validation; value is preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be less than {value}'**
  String shadcnFormLessThan(String value);

  /// shadcn greater-than validation; value is preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be greater than {value}'**
  String shadcnFormGreaterThan(String value);

  /// shadcn LTE validation; value is preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be less than or equal to {value}'**
  String shadcnFormLessThanOrEqualTo(String value);

  /// shadcn GTE validation; value is preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be greater than or equal to {value}'**
  String shadcnFormGreaterThanOrEqualTo(String value);

  /// shadcn phone validation
  ///
  /// In en, this message translates to:
  /// **'Phone number is invalid'**
  String get shadcnFormPhoneNumberInvalid;

  /// shadcn phone required
  ///
  /// In en, this message translates to:
  /// **'Phone number is required'**
  String get shadcnFormPhoneNumberEmpty;

  /// shadcn inclusive range; numbers preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be between {min} and {max} (inclusive)'**
  String shadcnFormBetweenInclusively(String min, String max);

  /// shadcn exclusive range; numbers preformatted
  ///
  /// In en, this message translates to:
  /// **'Must be between {min} and {max} (exclusive)'**
  String shadcnFormBetweenExclusively(String min, String max);

  /// shadcn min length; value is digits
  ///
  /// In en, this message translates to:
  /// **'Must be at least {value} characters'**
  String shadcnFormLengthLessThan(String value);

  /// shadcn max length; value is digits
  ///
  /// In en, this message translates to:
  /// **'Must be at most {value} characters'**
  String shadcnFormLengthGreaterThan(String value);

  /// shadcn password digit rule
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one digit'**
  String get shadcnFormPasswordDigits;

  /// shadcn password lowercase rule
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one lowercase letter'**
  String get shadcnFormPasswordLowercase;

  /// shadcn password uppercase rule
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one uppercase letter'**
  String get shadcnFormPasswordUppercase;

  /// shadcn password special rule
  ///
  /// In en, this message translates to:
  /// **'Must contain at least one special character'**
  String get shadcnFormPasswordSpecial;

  /// shadcn command palette search
  ///
  /// In en, this message translates to:
  /// **'Type a command or search...'**
  String get shadcnCommandSearch;

  /// shadcn command empty
  ///
  /// In en, this message translates to:
  /// **'No results found.'**
  String get shadcnCommandEmpty;

  /// shadcn command move up
  ///
  /// In en, this message translates to:
  /// **'Move Up'**
  String get shadcnCommandMoveUp;

  /// shadcn command move down
  ///
  /// In en, this message translates to:
  /// **'Move Down'**
  String get shadcnCommandMoveDown;

  /// shadcn command activate
  ///
  /// In en, this message translates to:
  /// **'Select'**
  String get shadcnCommandActivate;

  /// shadcn date picker year
  ///
  /// In en, this message translates to:
  /// **'Select a year'**
  String get shadcnDatePickerSelectYear;

  /// shadcn date picker placeholder
  ///
  /// In en, this message translates to:
  /// **'Select a date'**
  String get shadcnPlaceholderDatePicker;

  /// shadcn time picker placeholder
  ///
  /// In en, this message translates to:
  /// **'Select a time'**
  String get shadcnPlaceholderTimePicker;

  /// shadcn color picker placeholder
  ///
  /// In en, this message translates to:
  /// **'Select a color'**
  String get shadcnPlaceholderColorPicker;

  /// shadcn duration picker placeholder
  ///
  /// In en, this message translates to:
  /// **'Select a duration'**
  String get shadcnPlaceholderDurationPicker;

  /// shadcn cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get shadcnButtonCancel;

  /// shadcn save
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get shadcnButtonSave;

  /// shadcn previous
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get shadcnButtonPrevious;

  /// shadcn next
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get shadcnButtonNext;

  /// shadcn hour label
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get shadcnTimeHour;

  /// shadcn minute label
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get shadcnTimeMinute;

  /// shadcn second label
  ///
  /// In en, this message translates to:
  /// **'Second'**
  String get shadcnTimeSecond;

  /// Keep AM token for D6 time format
  ///
  /// In en, this message translates to:
  /// **'AM'**
  String get shadcnTimeAM;

  /// Keep PM token for D6 time format
  ///
  /// In en, this message translates to:
  /// **'PM'**
  String get shadcnTimePM;

  /// shadcn color red
  ///
  /// In en, this message translates to:
  /// **'Red'**
  String get shadcnColorRed;

  /// shadcn color green
  ///
  /// In en, this message translates to:
  /// **'Green'**
  String get shadcnColorGreen;

  /// shadcn color blue
  ///
  /// In en, this message translates to:
  /// **'Blue'**
  String get shadcnColorBlue;

  /// shadcn color alpha
  ///
  /// In en, this message translates to:
  /// **'Alpha'**
  String get shadcnColorAlpha;

  /// shadcn color hue
  ///
  /// In en, this message translates to:
  /// **'Hue'**
  String get shadcnColorHue;

  /// shadcn color saturation
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get shadcnColorSaturation;

  /// shadcn color value
  ///
  /// In en, this message translates to:
  /// **'Val'**
  String get shadcnColorValue;

  /// shadcn color lightness
  ///
  /// In en, this message translates to:
  /// **'Lum'**
  String get shadcnColorLightness;

  /// context menu cut
  ///
  /// In en, this message translates to:
  /// **'Cut'**
  String get shadcnMenuCut;

  /// context menu copy
  ///
  /// In en, this message translates to:
  /// **'Copy'**
  String get shadcnMenuCopy;

  /// context menu paste
  ///
  /// In en, this message translates to:
  /// **'Paste'**
  String get shadcnMenuPaste;

  /// context menu select all
  ///
  /// In en, this message translates to:
  /// **'Select All'**
  String get shadcnMenuSelectAll;

  /// context menu undo
  ///
  /// In en, this message translates to:
  /// **'Undo'**
  String get shadcnMenuUndo;

  /// context menu redo
  ///
  /// In en, this message translates to:
  /// **'Redo'**
  String get shadcnMenuRedo;

  /// context menu delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get shadcnMenuDelete;

  /// context menu share
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get shadcnMenuShare;

  /// context menu search web
  ///
  /// In en, this message translates to:
  /// **'Search Web'**
  String get shadcnMenuSearchWeb;

  /// context menu live text
  ///
  /// In en, this message translates to:
  /// **'Live Text Input'**
  String get shadcnMenuLiveTextInput;

  /// refresh pull
  ///
  /// In en, this message translates to:
  /// **'Pull to refresh'**
  String get shadcnRefreshTriggerPull;

  /// refresh release
  ///
  /// In en, this message translates to:
  /// **'Release to refresh'**
  String get shadcnRefreshTriggerRelease;

  /// refresh in progress
  ///
  /// In en, this message translates to:
  /// **'Refreshing...'**
  String get shadcnRefreshTriggerRefreshing;

  /// refresh complete
  ///
  /// In en, this message translates to:
  /// **'Refresh complete'**
  String get shadcnRefreshTriggerComplete;

  /// color picker recent
  ///
  /// In en, this message translates to:
  /// **'Recent'**
  String get shadcnColorPickerTabRecent;

  /// color picker RGB tab token
  ///
  /// In en, this message translates to:
  /// **'RGB'**
  String get shadcnColorPickerTabRGB;

  /// color picker HSV tab token
  ///
  /// In en, this message translates to:
  /// **'HSV'**
  String get shadcnColorPickerTabHSV;

  /// color picker HSL tab token
  ///
  /// In en, this message translates to:
  /// **'HSL'**
  String get shadcnColorPickerTabHSL;

  /// color picker HEX tab token
  ///
  /// In en, this message translates to:
  /// **'HEX'**
  String get shadcnColorPickerTabHEX;

  /// data table selection; counts preformatted
  ///
  /// In en, this message translates to:
  /// **'{count} of {total} row(s) selected.'**
  String shadcnDataTableSelectedRows(String count, String total);

  /// data table next
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get shadcnDataTableNext;

  /// data table previous
  ///
  /// In en, this message translates to:
  /// **'Previous'**
  String get shadcnDataTablePrevious;

  /// data table columns
  ///
  /// In en, this message translates to:
  /// **'Columns'**
  String get shadcnDataTableColumns;

  /// duration day abbreviation, keep token
  ///
  /// In en, this message translates to:
  /// **'DD'**
  String get shadcnTimeDaysAbbreviation;

  /// duration hour abbreviation, keep token
  ///
  /// In en, this message translates to:
  /// **'HH'**
  String get shadcnTimeHoursAbbreviation;

  /// duration minute abbreviation, keep token
  ///
  /// In en, this message translates to:
  /// **'MM'**
  String get shadcnTimeMinutesAbbreviation;

  /// duration second abbreviation, keep token
  ///
  /// In en, this message translates to:
  /// **'SS'**
  String get shadcnTimeSecondsAbbreviation;

  /// duration day label
  ///
  /// In en, this message translates to:
  /// **'Day'**
  String get shadcnDurationDay;

  /// duration hour label
  ///
  /// In en, this message translates to:
  /// **'Hour'**
  String get shadcnDurationHour;

  /// duration minute label
  ///
  /// In en, this message translates to:
  /// **'Minute'**
  String get shadcnDurationMinute;

  /// duration second label
  ///
  /// In en, this message translates to:
  /// **'Second'**
  String get shadcnDurationSecond;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Mo'**
  String get shadcnAbbreviatedMonday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Tu'**
  String get shadcnAbbreviatedTuesday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'We'**
  String get shadcnAbbreviatedWednesday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Th'**
  String get shadcnAbbreviatedThursday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Fr'**
  String get shadcnAbbreviatedFriday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Sa'**
  String get shadcnAbbreviatedSaturday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Su'**
  String get shadcnAbbreviatedSunday;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'January'**
  String get shadcnMonthJanuary;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'February'**
  String get shadcnMonthFebruary;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'March'**
  String get shadcnMonthMarch;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'April'**
  String get shadcnMonthApril;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get shadcnMonthMay;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'June'**
  String get shadcnMonthJune;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'July'**
  String get shadcnMonthJuly;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'August'**
  String get shadcnMonthAugust;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'September'**
  String get shadcnMonthSeptember;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'October'**
  String get shadcnMonthOctober;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'November'**
  String get shadcnMonthNovember;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'December'**
  String get shadcnMonthDecember;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Jan'**
  String get shadcnAbbreviatedJanuary;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Feb'**
  String get shadcnAbbreviatedFebruary;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Mar'**
  String get shadcnAbbreviatedMarch;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Apr'**
  String get shadcnAbbreviatedApril;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'May'**
  String get shadcnAbbreviatedMay;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Jun'**
  String get shadcnAbbreviatedJune;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Jul'**
  String get shadcnAbbreviatedJuly;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Aug'**
  String get shadcnAbbreviatedAugust;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Sep'**
  String get shadcnAbbreviatedSeptember;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Oct'**
  String get shadcnAbbreviatedOctober;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Nov'**
  String get shadcnAbbreviatedNovember;

  /// Calendar token kept language-stable for D6 date format.
  ///
  /// In en, this message translates to:
  /// **'Dec'**
  String get shadcnAbbreviatedDecember;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

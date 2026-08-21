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

  /// Settings nav general
  ///
  /// In en, this message translates to:
  /// **'General'**
  String get settingsNavGeneral;

  /// Settings nav appearance
  ///
  /// In en, this message translates to:
  /// **'Appearance'**
  String get settingsNavAppearance;

  /// Settings nav agents
  ///
  /// In en, this message translates to:
  /// **'Agent management'**
  String get settingsNavAgents;

  /// Settings agents missing
  ///
  /// In en, this message translates to:
  /// **'Agent management is unavailable.'**
  String get settingsAgentsUnavailable;

  /// macOS send shortcut tab
  ///
  /// In en, this message translates to:
  /// **'Cmd + Enter to send'**
  String get settingsSendShortcutCmdEnter;

  /// non-mac send shortcut tab
  ///
  /// In en, this message translates to:
  /// **'Ctrl + Enter to send'**
  String get settingsSendShortcutCtrlEnter;

  /// Enter send hint
  ///
  /// In en, this message translates to:
  /// **'Press Enter to send, Shift + Enter for a new line.'**
  String get settingsSendShortcutEnterHint;

  /// Cmd send hint
  ///
  /// In en, this message translates to:
  /// **'Press Cmd + Enter to send, Enter for a new line.'**
  String get settingsSendShortcutCmdHint;

  /// Ctrl send hint
  ///
  /// In en, this message translates to:
  /// **'Press Ctrl + Enter to send, Enter for a new line.'**
  String get settingsSendShortcutCtrlHint;

  /// Display language label
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get settingsLanguage;

  /// Display language hint
  ///
  /// In en, this message translates to:
  /// **'The interface language changes after you restart the app.'**
  String get settingsLanguageHint;

  /// English option self-name
  ///
  /// In en, this message translates to:
  /// **'English'**
  String get settingsLanguageEnglish;

  /// Simplified Chinese option self-name
  ///
  /// In en, this message translates to:
  /// **'简体中文'**
  String get settingsLanguageSimplifiedChinese;

  /// Language change pending restart
  ///
  /// In en, this message translates to:
  /// **'Takes effect after restart'**
  String get settingsLanguageRestartToApply;

  /// Language save failure toast
  ///
  /// In en, this message translates to:
  /// **'Could not save the language setting. The current selection was kept.'**
  String get settingsLanguageSaveFailed;

  /// General settings group
  ///
  /// In en, this message translates to:
  /// **'Sending messages'**
  String get settingsMessageSending;

  /// Send shortcut label
  ///
  /// In en, this message translates to:
  /// **'Send shortcut'**
  String get settingsSendShortcut;

  /// Enter tab
  ///
  /// In en, this message translates to:
  /// **'Enter to send'**
  String get settingsSendShortcutEnter;

  /// Notifications group
  ///
  /// In en, this message translates to:
  /// **'Notifications'**
  String get settingsNotifications;

  /// Master notification switch
  ///
  /// In en, this message translates to:
  /// **'System notifications'**
  String get settingsSystemNotifications;

  /// Master notification hint
  ///
  /// In en, this message translates to:
  /// **'Send system alerts when a task moves to the background or another session.'**
  String get settingsSystemNotificationsHint;

  /// Turn terminal switch
  ///
  /// In en, this message translates to:
  /// **'Task finished'**
  String get settingsTurnTerminalNotifications;

  /// Turn terminal hint
  ///
  /// In en, this message translates to:
  /// **'Notify when a task completes, fails, or is interrupted.'**
  String get settingsTurnTerminalNotificationsHint;

  /// Action required switch
  ///
  /// In en, this message translates to:
  /// **'Needs confirmation'**
  String get settingsActionRequiredNotifications;

  /// Action required hint
  ///
  /// In en, this message translates to:
  /// **'Notify when permission, a question, plan approval, or execution confirmation is waiting.'**
  String get settingsActionRequiredNotificationsHint;

  /// Theme system tab
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeFollowSystem;

  /// Theme system hint
  ///
  /// In en, this message translates to:
  /// **'Use the current system light or dark preference.'**
  String get settingsThemeFollowSystemHint;

  /// Theme light tab
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// Theme light hint
  ///
  /// In en, this message translates to:
  /// **'Light background, low-contrast borders, and a blue accent.'**
  String get settingsThemeLightHint;

  /// Theme dark tab
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// Theme dark hint
  ///
  /// In en, this message translates to:
  /// **'Dark background, high-contrast panes, and a bright accent.'**
  String get settingsThemeDarkHint;

  /// Theme group
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get settingsTheme;

  /// Fonts group
  ///
  /// In en, this message translates to:
  /// **'Fonts'**
  String get settingsFonts;

  /// UI font label
  ///
  /// In en, this message translates to:
  /// **'UI font'**
  String get settingsUiFont;

  /// UI font hint
  ///
  /// In en, this message translates to:
  /// **'Used for regular UI text and non-code Markdown body.'**
  String get settingsUiFontHint;

  /// UI font error
  ///
  /// In en, this message translates to:
  /// **'Could not load the selected UI font.'**
  String get settingsUiFontLoadError;

  /// UI size label
  ///
  /// In en, this message translates to:
  /// **'UI font size'**
  String get settingsUiFontSize;

  /// UI size hint
  ///
  /// In en, this message translates to:
  /// **'Scale regular UI text ({min}–{max} px).'**
  String settingsUiFontSizeHint(String min, String max);

  /// Code font label
  ///
  /// In en, this message translates to:
  /// **'Code font'**
  String get settingsCodeFont;

  /// Code font hint
  ///
  /// In en, this message translates to:
  /// **'Used for code blocks, commands, diffs, and tool output.'**
  String get settingsCodeFontHint;

  /// Code font error
  ///
  /// In en, this message translates to:
  /// **'Could not load the selected code font.'**
  String get settingsCodeFontLoadError;

  /// Code size label
  ///
  /// In en, this message translates to:
  /// **'Code font size'**
  String get settingsCodeFontSize;

  /// Code size hint
  ///
  /// In en, this message translates to:
  /// **'Scale code content ({min}–{max} px).'**
  String settingsCodeFontSizeHint(String min, String max);

  /// Theme mode label
  ///
  /// In en, this message translates to:
  /// **'Theme mode'**
  String get settingsThemeMode;

  /// Semantics label value
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String settingsLabeledValue(String label, String value);

  /// Font search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search {label}'**
  String settingsSearchSomething(String label);

  /// Font empty
  ///
  /// In en, this message translates to:
  /// **'No matching fonts.'**
  String get settingsNoMatchingFonts;

  /// Font list error
  ///
  /// In en, this message translates to:
  /// **'Could not load the font list.'**
  String get settingsFontListLoadFailed;

  /// Font size semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, currently {size} pixels'**
  String settingsFontSizeSemantics(String label, String size);

  /// Decrease control
  ///
  /// In en, this message translates to:
  /// **'Decrease {label}'**
  String settingsDecreaseSomething(String label);

  /// Pixel value
  ///
  /// In en, this message translates to:
  /// **'{size} px'**
  String settingsPixelValue(String size);

  /// Increase control
  ///
  /// In en, this message translates to:
  /// **'Increase {label}'**
  String settingsIncreaseSomething(String label);

  /// Geist default label
  ///
  /// In en, this message translates to:
  /// **'Geist (built-in default)'**
  String get settingsFontGeistDefault;

  /// JetBrains default label
  ///
  /// In en, this message translates to:
  /// **'JetBrainsMono (built-in default)'**
  String get settingsFontJetBrainsDefault;

  /// Common cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// Common confirm
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get commonConfirm;

  /// Common retry
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// Common more
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get commonMore;

  /// Common remove
  ///
  /// In en, this message translates to:
  /// **'Remove'**
  String get commonRemove;

  /// Window menu semantics
  ///
  /// In en, this message translates to:
  /// **'Menu'**
  String get commonMenu;

  /// Left sidebar hide
  ///
  /// In en, this message translates to:
  /// **'Hide left sidebar'**
  String get workbenchHideLeftSidebar;

  /// Left sidebar show
  ///
  /// In en, this message translates to:
  /// **'Show left sidebar'**
  String get workbenchShowLeftSidebar;

  /// Back home
  ///
  /// In en, this message translates to:
  /// **'Back to home'**
  String get workbenchBackToHome;

  /// Usage tooltip (keep current)
  ///
  /// In en, this message translates to:
  /// **'Usage statistics'**
  String get workbenchUsageStatistics;

  /// Usage semantic (keep current)
  ///
  /// In en, this message translates to:
  /// **'Open usage statistics page'**
  String get workbenchOpenUsageStatistics;

  /// Settings semantic (keep current)
  ///
  /// In en, this message translates to:
  /// **'Open settings page'**
  String get workbenchOpenSettings;

  /// Right sidebar hide
  ///
  /// In en, this message translates to:
  /// **'Hide right sidebar'**
  String get workbenchHideRightSidebar;

  /// Right sidebar show
  ///
  /// In en, this message translates to:
  /// **'Show right sidebar'**
  String get workbenchShowRightSidebar;

  /// Right sidebar disabled
  ///
  /// In en, this message translates to:
  /// **'The right sidebar is only available on the home screen'**
  String get workbenchRightSidebarHomeOnly;

  /// Window File menu
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get workbenchMenuFile;

  /// Window open project
  ///
  /// In en, this message translates to:
  /// **'Open Project'**
  String get workbenchMenuOpenProject;

  /// Window quit
  ///
  /// In en, this message translates to:
  /// **'Quit'**
  String get workbenchMenuQuit;

  /// Left resize (keep current)
  ///
  /// In en, this message translates to:
  /// **'Resize left panel width'**
  String get workbenchResizeLeftPanel;

  /// Right resize (keep current)
  ///
  /// In en, this message translates to:
  /// **'Resize right panel width'**
  String get workbenchResizeRightPanel;

  /// Notification thread missing
  ///
  /// In en, this message translates to:
  /// **'Could not open the session from the notification. It may have been deleted or is not in the current project list.'**
  String get workbenchCannotOpenNotificationThread;

  /// Provider detect error
  ///
  /// In en, this message translates to:
  /// **'Could not detect Provider: {error}'**
  String workbenchProviderDetectionFailed(String error);

  /// Overlay close (keep current)
  ///
  /// In en, this message translates to:
  /// **'Close workbench overlay'**
  String get workbenchCloseOverlay;

  /// Logo semantics
  ///
  /// In en, this message translates to:
  /// **'Zeta Logo'**
  String get workbenchLogoSemantics;

  /// Virtual timeline scrollbar semantics
  ///
  /// In en, this message translates to:
  /// **'Conversation scrollbar'**
  String get timelineScrollbar;

  /// Scroll to bottom
  ///
  /// In en, this message translates to:
  /// **'Scroll to end of conversation'**
  String get timelineScrollToBottom;

  /// New content chip
  ///
  /// In en, this message translates to:
  /// **'New content'**
  String get timelineNewContent;

  /// Back to bottom
  ///
  /// In en, this message translates to:
  /// **'Back to bottom'**
  String get timelineBackToBottom;

  /// Image missing
  ///
  /// In en, this message translates to:
  /// **'Image file unavailable'**
  String get imagePreviewUnavailable;

  /// View large
  ///
  /// In en, this message translates to:
  /// **'View larger image'**
  String get imagePreviewViewLarge;

  /// View image
  ///
  /// In en, this message translates to:
  /// **'View image'**
  String get imagePreviewView;

  /// Tabs loading
  ///
  /// In en, this message translates to:
  /// **'{label}, loading'**
  String tabsLoadingSuffix(String label);

  /// Global home welcome
  ///
  /// In en, this message translates to:
  /// **'Welcome to Zeta'**
  String get homeWelcomeTitle;

  /// Global home subtitle
  ///
  /// In en, this message translates to:
  /// **'Open a local project to start working with an Agent.'**
  String get homeWelcomeSubtitle;

  /// Open folder CTA
  ///
  /// In en, this message translates to:
  /// **'Open project folder'**
  String get homeOpenProjectFolder;

  /// Open project
  ///
  /// In en, this message translates to:
  /// **'Open project'**
  String get homeOpenProject;

  /// Recent projects
  ///
  /// In en, this message translates to:
  /// **'Recent projects'**
  String get homeRecentProjects;

  /// Reading projects
  ///
  /// In en, this message translates to:
  /// **'Reading recent projects…'**
  String get homeReadingRecentProjects;

  /// Empty projects
  ///
  /// In en, this message translates to:
  /// **'No recent projects'**
  String get homeNoRecentProjects;

  /// Projects restoring
  ///
  /// In en, this message translates to:
  /// **'Recent projects will appear here after restore finishes.'**
  String get homeRecentProjectsAfterRestore;

  /// Projects empty
  ///
  /// In en, this message translates to:
  /// **'After you open a project, it will appear here.'**
  String get homeRecentProjectsAfterOpen;

  /// Recent sessions
  ///
  /// In en, this message translates to:
  /// **'Recent sessions'**
  String get homeRecentSessions;

  /// Refresh failed
  ///
  /// In en, this message translates to:
  /// **'Refresh failed'**
  String get homeRefreshFailed;

  /// Cannot refresh
  ///
  /// In en, this message translates to:
  /// **'Could not refresh recent sessions'**
  String get homeCannotRefreshSessions;

  /// Loading sessions
  ///
  /// In en, this message translates to:
  /// **'Loading recent sessions…'**
  String get homeLoadingRecentSessions;

  /// Empty sessions
  ///
  /// In en, this message translates to:
  /// **'No recent sessions'**
  String get homeNoRecentSessions;

  /// Sessions cache
  ///
  /// In en, this message translates to:
  /// **'Cached sessions show first; newer ones fill in in the background.'**
  String get homeSessionsCacheHint;

  /// Sessions empty
  ///
  /// In en, this message translates to:
  /// **'After you create a session, it appears by last activity.'**
  String get homeSessionsEmptyHint;

  /// Installed providers
  ///
  /// In en, this message translates to:
  /// **'Installed providers'**
  String get homeInstalledProviders;

  /// Detection failed
  ///
  /// In en, this message translates to:
  /// **'Detection failed'**
  String get homeDetectionFailed;

  /// Provider detect title
  ///
  /// In en, this message translates to:
  /// **'Provider detection failed'**
  String get homeProviderDetectionFailedTitle;

  /// Detecting
  ///
  /// In en, this message translates to:
  /// **'Detecting providers…'**
  String get homeDetectingProviders;

  /// No providers
  ///
  /// In en, this message translates to:
  /// **'No installed providers detected'**
  String get homeNoInstalledProviders;

  /// Providers after detect
  ///
  /// In en, this message translates to:
  /// **'Available Agent environments appear here after detection.'**
  String get homeProvidersAfterDetect;

  /// Providers after install
  ///
  /// In en, this message translates to:
  /// **'After you install and configure a supported Agent, it appears here.'**
  String get homeProvidersAfterInstall;

  /// Open recent project
  ///
  /// In en, this message translates to:
  /// **'Open recent project {name}'**
  String homeOpenRecentProject(String name);

  /// Open recent session
  ///
  /// In en, this message translates to:
  /// **'Open recent session {title}'**
  String homeOpenRecentSession(String title);

  /// Join two labels
  ///
  /// In en, this message translates to:
  /// **'{left}, {right}'**
  String homeCommaJoin(String left, String right);

  /// Provider available
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get homeProviderAvailable;

  /// Provider running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get homeProviderRunning;

  /// Provider disabled
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get homeProviderDisabled;

  /// Provider login
  ///
  /// In en, this message translates to:
  /// **'Sign-in required'**
  String get homeProviderNeedsLogin;

  /// Provider error
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get homeProviderError;

  /// Provider update
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get homeProviderUpdateAvailable;

  /// Provider detecting
  ///
  /// In en, this message translates to:
  /// **'Detecting'**
  String get homeProviderDetecting;

  /// New session
  ///
  /// In en, this message translates to:
  /// **'New session'**
  String get projectNewSession;

  /// New session for project
  ///
  /// In en, this message translates to:
  /// **'New session for {name}'**
  String projectNewSessionFor(String name);

  /// Project empty sessions
  ///
  /// In en, this message translates to:
  /// **'No recent sessions'**
  String get projectNoRecentSessions;

  /// Create thread hint
  ///
  /// In en, this message translates to:
  /// **'After you create a Thread, it appears here.'**
  String get projectCreateThreadHint;

  /// Cannot load sessions
  ///
  /// In en, this message translates to:
  /// **'Could not load recent sessions'**
  String get projectCannotLoadSessions;

  /// Retry later
  ///
  /// In en, this message translates to:
  /// **'Please try again later.'**
  String get projectPleaseRetryLater;

  /// Retry sessions
  ///
  /// In en, this message translates to:
  /// **'Retry loading recent sessions'**
  String get projectRetryLoadSessions;

  /// Open session
  ///
  /// In en, this message translates to:
  /// **'Open session {title}'**
  String projectOpenSession(String title);

  /// Waiting approval
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get threadWaitingApproval;

  /// Waiting input
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get threadWaitingInput;

  /// Thread running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get threadRunning;

  /// System error
  ///
  /// In en, this message translates to:
  /// **'System error'**
  String get threadSystemError;

  /// Open folder (keep current)
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get projectOpenFolder;

  /// Refresh sessions
  ///
  /// In en, this message translates to:
  /// **'Refresh sessions'**
  String get projectRefreshSessions;

  /// Running threads (keep current)
  ///
  /// In en, this message translates to:
  /// **'Project has running threads'**
  String get projectHasRunningThreads;

  /// Rename
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get threadRename;

  /// Unarchive
  ///
  /// In en, this message translates to:
  /// **'Unarchive'**
  String get threadUnarchive;

  /// Archive
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get threadArchive;

  /// Fork
  ///
  /// In en, this message translates to:
  /// **'Fork'**
  String get threadFork;

  /// Delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get threadDelete;

  /// Remove index only
  ///
  /// In en, this message translates to:
  /// **'Remove from Zeta list only'**
  String get threadRemoveFromZetaOnly;

  /// Remove from list
  ///
  /// In en, this message translates to:
  /// **'Remove session from list'**
  String get threadRemoveFromList;

  /// Delete session
  ///
  /// In en, this message translates to:
  /// **'Delete session'**
  String get threadDeleteSession;

  /// Delete warning
  ///
  /// In en, this message translates to:
  /// **'This cannot be undone and permanently deletes the session.'**
  String get threadDeleteIrreversible;

  /// Remove index hint
  ///
  /// In en, this message translates to:
  /// **'This only removes Zeta\'\'s local index. Provider history files remain.'**
  String get threadRemoveIndexOnlyHint;

  /// Delete in agent
  ///
  /// In en, this message translates to:
  /// **'To delete it completely, use the corresponding Agent tool.'**
  String get threadDeleteInAgentHint;

  /// Thread running tooltip (keep current)
  ///
  /// In en, this message translates to:
  /// **'Thread running'**
  String get threadRunningStatus;

  /// Completed dismiss
  ///
  /// In en, this message translates to:
  /// **'Finished, click to dismiss'**
  String get threadCompletedClickToDismiss;

  /// Load threads error (keep current)
  ///
  /// In en, this message translates to:
  /// **'Could not load threads'**
  String get threadCouldNotLoadThreads;

  /// Open Finder
  ///
  /// In en, this message translates to:
  /// **'Open in Finder'**
  String get projectOpenInFinder;

  /// Open Explorer
  ///
  /// In en, this message translates to:
  /// **'Open in Explorer'**
  String get projectOpenInExplorer;

  /// Open file manager
  ///
  /// In en, this message translates to:
  /// **'Open in file manager'**
  String get projectOpenInFileManager;

  /// Select provider
  ///
  /// In en, this message translates to:
  /// **'Select Agent Provider'**
  String get newThreadSelectProvider;

  /// Loading agents
  ///
  /// In en, this message translates to:
  /// **'Loading Agent…'**
  String get newThreadLoadingAgents;

  /// Load agents error
  ///
  /// In en, this message translates to:
  /// **'Could not load Agent: {error}'**
  String newThreadCannotLoadAgents(String error);

  /// No enabled providers
  ///
  /// In en, this message translates to:
  /// **'No enabled supported Agent provider. Enable one in Settings > Agents first.'**
  String get newThreadNoEnabledProviders;

  /// Choose agent
  ///
  /// In en, this message translates to:
  /// **'Choose the Agent used to create the new session.'**
  String get newThreadChooseAgent;

  /// Use provider
  ///
  /// In en, this message translates to:
  /// **'Create thread with {name}'**
  String newThreadUseProvider(String name);

  /// Usage time range today
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get usageTimeRangeToday;

  /// Usage time range last 7 days
  ///
  /// In en, this message translates to:
  /// **'Last 7 days'**
  String get usageTimeRangeLast7Days;

  /// Usage time range last 30 days
  ///
  /// In en, this message translates to:
  /// **'Last 30 days'**
  String get usageTimeRangeLast30Days;

  /// Usage time range last 90 days
  ///
  /// In en, this message translates to:
  /// **'Last 90 days'**
  String get usageTimeRangeLast90Days;

  /// Usage time range this month
  ///
  /// In en, this message translates to:
  /// **'This month'**
  String get usageTimeRangeThisMonth;

  /// Usage time range previous month
  ///
  /// In en, this message translates to:
  /// **'Last month'**
  String get usageTimeRangePreviousMonth;

  /// Usage time range custom
  ///
  /// In en, this message translates to:
  /// **'Custom range'**
  String get usageTimeRangeCustom;

  /// Usage task running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get usageTaskStatusRunning;

  /// Usage task completed
  ///
  /// In en, this message translates to:
  /// **'Succeeded'**
  String get usageTaskStatusCompleted;

  /// Usage task interrupted
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get usageTaskStatusInterrupted;

  /// Usage task failed
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get usageTaskStatusFailed;

  /// Usage task unknown
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get usageTaskStatusUnknown;

  /// Usage error account
  ///
  /// In en, this message translates to:
  /// **'Account issue'**
  String get usageErrorCategoryAccount;

  /// Usage error CLI
  ///
  /// In en, this message translates to:
  /// **'Runtime issue'**
  String get usageErrorCategoryCli;

  /// Usage error network
  ///
  /// In en, this message translates to:
  /// **'Network error'**
  String get usageErrorCategoryNetwork;

  /// Usage error timeout
  ///
  /// In en, this message translates to:
  /// **'Timed out'**
  String get usageErrorCategoryTimeout;

  /// Usage error cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled by user'**
  String get usageErrorCategoryCancelled;

  /// Usage error other
  ///
  /// In en, this message translates to:
  /// **'Other error'**
  String get usageErrorCategoryOther;

  /// Usage next action account
  ///
  /// In en, this message translates to:
  /// **'Check the Codex sign-in status and current plan quota.'**
  String get usageErrorNextActionAccount;

  /// Usage next action CLI
  ///
  /// In en, this message translates to:
  /// **'Check the Codex version, configuration, and runtime logs.'**
  String get usageErrorNextActionCli;

  /// Usage next action network
  ///
  /// In en, this message translates to:
  /// **'Check the network and proxy settings, then retry.'**
  String get usageErrorNextActionNetwork;

  /// Usage next action timeout
  ///
  /// In en, this message translates to:
  /// **'Narrow the task scope and retry.'**
  String get usageErrorNextActionTimeout;

  /// Usage next action cancelled
  ///
  /// In en, this message translates to:
  /// **'Start the task again if you still need it.'**
  String get usageErrorNextActionCancelled;

  /// Usage next action other
  ///
  /// In en, this message translates to:
  /// **'Open the task details or Agent logs for the original reason.'**
  String get usageErrorNextActionOther;

  /// Usage trend calls
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get usageTrendMetricCalls;

  /// Usage trend success rate
  ///
  /// In en, this message translates to:
  /// **'Success rate'**
  String get usageTrendMetricSuccessRate;

  /// Usage trend tokens
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get usageTrendMetricTotalTokens;

  /// Usage trend response
  ///
  /// In en, this message translates to:
  /// **'Average response time'**
  String get usageTrendMetricAverageResponse;

  /// Usage trend duration
  ///
  /// In en, this message translates to:
  /// **'Task duration'**
  String get usageTrendMetricAverageDuration;

  /// Usage rank sort calls
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get usageRankSortCalls;

  /// Usage rank sort tokens
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get usageRankSortTotalTokens;

  /// Usage rank sort failures
  ///
  /// In en, this message translates to:
  /// **'Failures'**
  String get usageRankSortFailures;

  /// Usage rank sort duration
  ///
  /// In en, this message translates to:
  /// **'Task duration'**
  String get usageRankSortAverageDuration;

  /// Usage unknown project
  ///
  /// In en, this message translates to:
  /// **'Unknown project'**
  String get usageUnknownProject;

  /// Usage load failed
  ///
  /// In en, this message translates to:
  /// **'Unable to load usage statistics: {error}'**
  String usageLoadFailed(String error);

  /// Usage quota unreadable
  ///
  /// In en, this message translates to:
  /// **'Plan quota is temporarily unavailable'**
  String get usageQuotaUnreadable;

  /// Usage agent unavailable
  ///
  /// In en, this message translates to:
  /// **'This Agent is temporarily unavailable'**
  String get usageAgentTemporarilyUnavailable;

  /// Usage token history unavailable
  ///
  /// In en, this message translates to:
  /// **'Token history is temporarily unavailable'**
  String get usageTokenHistoryUnavailable;

  /// Usage token source mismatch
  ///
  /// In en, this message translates to:
  /// **'Token history source configuration does not match'**
  String get usageTokenSourceMismatch;

  /// Usage no token history
  ///
  /// In en, this message translates to:
  /// **'No Token history'**
  String get usageNoTokenHistory;

  /// Usage today tokens unreadable
  ///
  /// In en, this message translates to:
  /// **'Today\'\'s Token usage is temporarily unavailable'**
  String get usageTodayTokensUnreadable;

  /// Usage index write failed
  ///
  /// In en, this message translates to:
  /// **'The statistics index could not be saved. This result is still available.'**
  String get usageIndexWriteFailed;

  /// Usage index read failed then rescanned
  ///
  /// In en, this message translates to:
  /// **'{providerName} statistics index is temporarily unreadable. Local history was rescanned.'**
  String usageIndexReadRescanned(String providerName);

  /// Usage agent disabled
  ///
  /// In en, this message translates to:
  /// **'This Agent is disabled or unavailable'**
  String get usageAgentDisabledOrUnavailable;

  /// Usage panel load error
  ///
  /// In en, this message translates to:
  /// **'Agent usage is temporarily unavailable'**
  String get usageAgentUsageTemporarilyUnavailable;

  /// Usage page title
  ///
  /// In en, this message translates to:
  /// **'Usage statistics'**
  String get usagePageTitle;

  /// Usage page subtitle
  ///
  /// In en, this message translates to:
  /// **'Analyze calls, performance, tokens, projects, and plan quota'**
  String get usagePageSubtitle;

  /// Usage load failed title
  ///
  /// In en, this message translates to:
  /// **'Failed to load statistics'**
  String get usageLoadFailedTitle;

  /// Usage partial unavailable
  ///
  /// In en, this message translates to:
  /// **'Some data is unavailable'**
  String get usagePartialUnavailable;

  /// Usage reload
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get usageReload;

  /// Usage time range field
  ///
  /// In en, this message translates to:
  /// **'Time range'**
  String get usageTimeRangeLabel;

  /// Usage all agents
  ///
  /// In en, this message translates to:
  /// **'All Agents'**
  String get usageAllAgents;

  /// Usage model field
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get usageModelLabel;

  /// Usage all models
  ///
  /// In en, this message translates to:
  /// **'All models'**
  String get usageAllModels;

  /// Usage last updated
  ///
  /// In en, this message translates to:
  /// **'Last updated: {time}'**
  String usageLastUpdated(String time);

  /// Usage refresh
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get usageRefresh;

  /// Usage token breakdown line
  ///
  /// In en, this message translates to:
  /// **'Input {input} · Output {output} · Reasoning {reasoning}'**
  String usageTokenBreakdownLine(String input, String output, String reasoning);

  /// Usage no token stats
  ///
  /// In en, this message translates to:
  /// **'No Token statistics for the current filters'**
  String get usageNoTokenStats;

  /// Usage token usage card label
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get usageTokenUsageLabel;

  /// Usage token amount heading
  ///
  /// In en, this message translates to:
  /// **'Token usage {amount}'**
  String usageTokenUsageAmount(String amount);

  /// Usage call count
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get usageCallCount;

  /// Usage call count semantics
  ///
  /// In en, this message translates to:
  /// **'Calls {count}'**
  String usageCallCountSemantic(String count);

  /// Usage trend title
  ///
  /// In en, this message translates to:
  /// **'Usage trend'**
  String get usageTrendTitle;

  /// Usage trend subtitle
  ///
  /// In en, this message translates to:
  /// **'Token usage · granularity follows the selected range'**
  String get usageTrendSubtitle;

  /// Usage trend semantics
  ///
  /// In en, this message translates to:
  /// **'{metric} trend, {count} time points'**
  String usageTrendSemantic(String metric, String count);

  /// Usage detail tabs
  ///
  /// In en, this message translates to:
  /// **'Usage statistics detail categories'**
  String get usageDetailTabsSemantic;

  /// Usage agent stats tab - keep current chrome if mixed
  ///
  /// In en, this message translates to:
  /// **'Agent statistics'**
  String get usageAgentStats;

  /// Usage model stats tab
  ///
  /// In en, this message translates to:
  /// **'Model statistics'**
  String get usageModelStats;

  /// Usage project list tab
  ///
  /// In en, this message translates to:
  /// **'Project list'**
  String get usageProjectList;

  /// Usage task list tab
  ///
  /// In en, this message translates to:
  /// **'Task list'**
  String get usageTaskList;

  /// Usage rank summary
  ///
  /// In en, this message translates to:
  /// **'Summarized for the current filters'**
  String get usageRankSummary;

  /// Usage unsupported metric
  ///
  /// In en, this message translates to:
  /// **'Unsupported'**
  String get usageUnsupported;

  /// Usage table header calls
  ///
  /// In en, this message translates to:
  /// **'Calls'**
  String get usageHeaderCalls;

  /// Usage table header success
  ///
  /// In en, this message translates to:
  /// **'Success rate'**
  String get usageHeaderSuccessRate;

  /// Usage table header token
  ///
  /// In en, this message translates to:
  /// **'Token'**
  String get usageHeaderToken;

  /// Usage table header failures
  ///
  /// In en, this message translates to:
  /// **'Failures'**
  String get usageHeaderFailures;

  /// Usage table header duration
  ///
  /// In en, this message translates to:
  /// **'Avg. duration'**
  String get usageHeaderAverageDuration;

  /// Usage model share heading
  ///
  /// In en, this message translates to:
  /// **'Model Token usage and share'**
  String get usageModelTokenShare;

  /// Usage no model stats
  ///
  /// In en, this message translates to:
  /// **'No model statistics for the current filters'**
  String get usageNoModelStats;

  /// Usage token total
  ///
  /// In en, this message translates to:
  /// **'Total'**
  String get usageTokenTotal;

  /// Usage token input
  ///
  /// In en, this message translates to:
  /// **'Input'**
  String get usageTokenInput;

  /// Usage token cached input
  ///
  /// In en, this message translates to:
  /// **'Cached input'**
  String get usageTokenCachedInput;

  /// Usage token output
  ///
  /// In en, this message translates to:
  /// **'Output'**
  String get usageTokenOutput;

  /// Usage token reasoning
  ///
  /// In en, this message translates to:
  /// **'Reasoning'**
  String get usageTokenReasoning;

  /// Usage table header model
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get usageHeaderModel;

  /// Usage table header share
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get usageHeaderShare;

  /// Usage project summary
  ///
  /// In en, this message translates to:
  /// **'Summarized for the current filters · click a project to focus it'**
  String get usageProjectSummary;

  /// Usage table header project
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get usageHeaderProject;

  /// Usage table header last used
  ///
  /// In en, this message translates to:
  /// **'Last used'**
  String get usageHeaderLastUsed;

  /// Usage task list summary
  ///
  /// In en, this message translates to:
  /// **'{count} items · {pageSize} per page · metadata only'**
  String usageTaskListSummary(String count, String pageSize);

  /// Usage table header time
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get usageHeaderTime;

  /// Usage table header duration short
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get usageHeaderDuration;

  /// Usage table header status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get usageHeaderStatus;

  /// Usage unknown model
  ///
  /// In en, this message translates to:
  /// **'Unknown model'**
  String get usageUnknownModel;

  /// Usage open detail
  ///
  /// In en, this message translates to:
  /// **'Open {name} details'**
  String usageOpenDetail(String name);

  /// Usage task detail title
  ///
  /// In en, this message translates to:
  /// **'Task details'**
  String get usageTaskDetail;

  /// Usage field project
  ///
  /// In en, this message translates to:
  /// **'Project'**
  String get usageFieldProject;

  /// Usage field project path
  ///
  /// In en, this message translates to:
  /// **'Project path'**
  String get usageFieldProjectPath;

  /// Usage field source
  ///
  /// In en, this message translates to:
  /// **'Source'**
  String get usageFieldSource;

  /// Usage field start time
  ///
  /// In en, this message translates to:
  /// **'Start time'**
  String get usageFieldStartTime;

  /// Usage field duration
  ///
  /// In en, this message translates to:
  /// **'Duration'**
  String get usageFieldDuration;

  /// Usage field first response
  ///
  /// In en, this message translates to:
  /// **'First response'**
  String get usageFieldFirstResponse;

  /// Usage token not supported
  ///
  /// In en, this message translates to:
  /// **'This record does not support Token statistics'**
  String get usageTokenNotSupported;

  /// Usage token full detail
  ///
  /// In en, this message translates to:
  /// **'{total} (Input {input} / Cached {cached} / Output {output} / Reasoning {reasoning})'**
  String usageTokenFullDetail(
    String total,
    String input,
    String cached,
    String output,
    String reasoning,
  );

  /// Usage token detail suffix; leading parenthesis is in the value prefix
  ///
  /// In en, this message translates to:
  /// **'Cached {cached} / Output {output} / Reasoning {reasoning})'**
  String usageTokenDetail(String cached, String output, String reasoning);

  /// Usage field status
  ///
  /// In en, this message translates to:
  /// **'Status'**
  String get usageFieldStatus;

  /// Usage field error category
  ///
  /// In en, this message translates to:
  /// **'Error category'**
  String get usageFieldErrorCategory;

  /// Usage field reason
  ///
  /// In en, this message translates to:
  /// **'Reason'**
  String get usageFieldReason;

  /// Usage no reason
  ///
  /// In en, this message translates to:
  /// **'No detailed reason provided'**
  String get usageNoReason;

  /// Usage field next step
  ///
  /// In en, this message translates to:
  /// **'Next step'**
  String get usageFieldNextStep;

  /// Usage source kind cli
  ///
  /// In en, this message translates to:
  /// **'Local record'**
  String get usageSourceKindCli;

  /// Usage empty title
  ///
  /// In en, this message translates to:
  /// **'No usage records yet'**
  String get usageEmptyTitle;

  /// Usage empty body
  ///
  /// In en, this message translates to:
  /// **'After you start using an Agent, call counts, performance, and resource usage appear here.'**
  String get usageEmptyBody;

  /// Usage open agent management
  ///
  /// In en, this message translates to:
  /// **'Open Agent management'**
  String get usageOpenAgentManagement;

  /// Usage loading
  ///
  /// In en, this message translates to:
  /// **'Loading usage statistics'**
  String get usageLoading;

  /// Usage time shortcuts heading
  ///
  /// In en, this message translates to:
  /// **'Shortcuts'**
  String get usageQuickShortcuts;

  /// Usage panel refresh
  ///
  /// In en, this message translates to:
  /// **'Refresh usage'**
  String get usageRefreshUsage;

  /// Usage no enabled agent
  ///
  /// In en, this message translates to:
  /// **'No enabled Agent'**
  String get usageNoEnabledAgent;

  /// Usage no stats
  ///
  /// In en, this message translates to:
  /// **'No statistics'**
  String get usageNoStats;

  /// Usage collapse panel
  ///
  /// In en, this message translates to:
  /// **'Collapse Agent statistics'**
  String get usageCollapseAgentStats;

  /// Usage expand panel
  ///
  /// In en, this message translates to:
  /// **'Expand Agent statistics'**
  String get usageExpandAgentStats;

  /// Usage today token
  ///
  /// In en, this message translates to:
  /// **'Today\'\'s Token'**
  String get usageTodayToken;

  /// Usage reading
  ///
  /// In en, this message translates to:
  /// **'Reading Agent usage'**
  String get usageReadingAgentUsage;

  /// Usage retry read
  ///
  /// In en, this message translates to:
  /// **'Retry reading Agent usage'**
  String get usageRetryReadAgentUsage;

  /// Usage select agent
  ///
  /// In en, this message translates to:
  /// **'Select Agent usage'**
  String get usageSelectAgentUsage;

  /// Usage reset cards
  ///
  /// In en, this message translates to:
  /// **'Available reset cards'**
  String get usageAvailableResetCards;

  /// Reset card count
  ///
  /// In en, this message translates to:
  /// **'{count} cards'**
  String usageResetCardCount(String count);

  /// Compact usage panel semantics
  ///
  /// In en, this message translates to:
  /// **'Agent statistics summary'**
  String get usageAgentStatsSummary;

  /// Business usage-based plan label
  ///
  /// In en, this message translates to:
  /// **'ChatGPT Business (usage-based)'**
  String get usagePlanBusinessUsageBased;

  /// Enterprise usage-based plan label
  ///
  /// In en, this message translates to:
  /// **'ChatGPT Enterprise (usage-based)'**
  String get usagePlanEnterpriseUsageBased;

  /// Usage retry
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get usageRetry;

  /// Usage previous quota window
  ///
  /// In en, this message translates to:
  /// **'Previous window'**
  String get usagePrevWindow;

  /// Usage next quota window
  ///
  /// In en, this message translates to:
  /// **'Next window'**
  String get usageNextWindow;

  /// Detect locating
  ///
  /// In en, this message translates to:
  /// **'Locating {name}'**
  String mgmtLocating(String name);

  /// Detect locating Claude CLI
  ///
  /// In en, this message translates to:
  /// **'Checking Claude Code CLI'**
  String get mgmtLocatingClaudeCodeCli;

  /// Detect not found
  ///
  /// In en, this message translates to:
  /// **'{name} was not found'**
  String mgmtNotFound(String name);

  /// Claude CLI not found
  ///
  /// In en, this message translates to:
  /// **'Claude Code CLI was not found'**
  String get mgmtNotFoundClaudeCodeCli;

  /// Install suggestion
  ///
  /// In en, this message translates to:
  /// **'Install {name} first and make sure the executable is on PATH.'**
  String mgmtInstallAndAddToPath(String name);

  /// Install Claude suggestion
  ///
  /// In en, this message translates to:
  /// **'Install Claude Code first and make sure claude is on PATH.'**
  String get mgmtInstallClaudeCodeAndAddToPath;

  /// Detect found
  ///
  /// In en, this message translates to:
  /// **'Found {name}'**
  String mgmtFound(String name);

  /// Confirm executable
  ///
  /// In en, this message translates to:
  /// **'Confirm the detected executable can run, then detect again.'**
  String get mgmtConfirmExecutableThenRedetect;

  /// Confirm claude version
  ///
  /// In en, this message translates to:
  /// **'Confirm Claude Code CLI can run `claude --version`.'**
  String get mgmtConfirmClaudeVersionCommand;

  /// Version detected
  ///
  /// In en, this message translates to:
  /// **'Current version detected'**
  String get mgmtVersionDetected;

  /// Claude version detected
  ///
  /// In en, this message translates to:
  /// **'Claude Code version detected'**
  String get mgmtClaudeVersionDetected;

  /// Account detected
  ///
  /// In en, this message translates to:
  /// **'Account status detected'**
  String get mgmtAccountDetected;

  /// Claude auth detected
  ///
  /// In en, this message translates to:
  /// **'Claude Code sign-in status detected'**
  String get mgmtClaudeAuthDetected;

  /// Config status read
  ///
  /// In en, this message translates to:
  /// **'Configuration file status read'**
  String get mgmtConfigStatusRead;

  /// Logs located
  ///
  /// In en, this message translates to:
  /// **'{name} logs located'**
  String mgmtLogsLocated(String name);

  /// Latest version checked
  ///
  /// In en, this message translates to:
  /// **'Latest version checked'**
  String get mgmtLatestVersionChecked;

  /// Handshake complete
  ///
  /// In en, this message translates to:
  /// **'Protocol handshake completed'**
  String get mgmtHandshakeComplete;

  /// Detection complete
  ///
  /// In en, this message translates to:
  /// **'{name} detection finished'**
  String mgmtDetectionComplete(String name);

  /// Retest after config
  ///
  /// In en, this message translates to:
  /// **'Check {name} configuration and account status, then test the connection again.'**
  String mgmtRetestAfterCheckingConfig(String name);

  /// Retest Grok
  ///
  /// In en, this message translates to:
  /// **'Check the Grok sign-in state and configuration, then test the connection again.'**
  String get mgmtRetestAfterCheckingGrokAuth;

  /// Confirm claude auth status
  ///
  /// In en, this message translates to:
  /// **'Confirm `claude auth status --json` can run; you can also run a connection test to verify the current CLI auth path.'**
  String get mgmtConfirmClaudeAuthStatusJson;

  /// No Claude login evidence suggestion
  ///
  /// In en, this message translates to:
  /// **'No Claude.ai sign-in evidence found. Run `claude auth login` if needed, or run a connection test to confirm the current CLI auth path.'**
  String get mgmtNoClaudeLoginEvidenceSuggestion;

  /// Cannot identify version
  ///
  /// In en, this message translates to:
  /// **'Could not identify the {name} version.'**
  String mgmtCannotIdentifyVersion(String name);

  /// Latest check failed
  ///
  /// In en, this message translates to:
  /// **'Latest version check failed.'**
  String get mgmtLatestVersionCheckFailed;

  /// Cannot parse version check
  ///
  /// In en, this message translates to:
  /// **'Could not parse the version check result.'**
  String get mgmtCannotParseVersionCheck;

  /// Unknown version format
  ///
  /// In en, this message translates to:
  /// **'The version service returned an unknown format.'**
  String get mgmtVersionServiceUnknownFormat;

  /// Missing latest version
  ///
  /// In en, this message translates to:
  /// **'The version service did not return a latest version.'**
  String get mgmtVersionServiceMissingVersion;

  /// Cannot get latest
  ///
  /// In en, this message translates to:
  /// **'Could not get the latest {name} version.'**
  String mgmtCannotGetLatestVersion(String name);

  /// Account logged in
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get mgmtAccountLoggedIn;

  /// Run codex login
  ///
  /// In en, this message translates to:
  /// **'Run codex login in a terminal, then detect again.'**
  String get mgmtRunCodexLogin;

  /// Run grok login
  ///
  /// In en, this message translates to:
  /// **'Run grok login in a terminal, then detect again.'**
  String get mgmtRunGrokLogin;

  /// Rerun grok login
  ///
  /// In en, this message translates to:
  /// **'Run grok login again.'**
  String get mgmtRerunGrokLogin;

  /// Codex login status
  ///
  /// In en, this message translates to:
  /// **'Run codex login status in a terminal for details.'**
  String get mgmtRunCodexLoginStatus;

  /// Fix config.toml
  ///
  /// In en, this message translates to:
  /// **'Fix the fields reported in config.toml, then detect again.'**
  String get mgmtFixConfigTomlThenRedetect;

  /// Codex config unparseable
  ///
  /// In en, this message translates to:
  /// **'The Codex configuration file could not be parsed.'**
  String get mgmtCodexConfigUnparseable;

  /// Cannot detect account
  ///
  /// In en, this message translates to:
  /// **'Could not detect account status.'**
  String get mgmtCannotDetectAccount;

  /// Account check failed
  ///
  /// In en, this message translates to:
  /// **'Account status check failed.'**
  String get mgmtAccountCheckFailed;

  /// Confirm CLI runs
  ///
  /// In en, this message translates to:
  /// **'Confirm {name} can run in a terminal.'**
  String mgmtConfirmCliRuns(String name);

  /// Grok login cache
  ///
  /// In en, this message translates to:
  /// **'Could not parse the Grok login cache.'**
  String get mgmtCannotParseGrokLoginCache;

  /// No Claude login label
  ///
  /// In en, this message translates to:
  /// **'No Claude.ai OAuth or API key sign-in evidence found'**
  String get mgmtNoClaudeLoginEvidenceLabel;

  /// Cannot check Claude auth
  ///
  /// In en, this message translates to:
  /// **'Could not check sign-in status through the Claude CLI.'**
  String get mgmtCannotCheckClaudeAuth;

  /// Cannot start initialize
  ///
  /// In en, this message translates to:
  /// **'Could not start the Claude Code initialize probe.'**
  String get mgmtCannotStartClaudeInitialize;

  /// Auth via API key
  ///
  /// In en, this message translates to:
  /// **'Authenticated with an Anthropic API key'**
  String get mgmtClaudeAuthViaApiKey;

  /// Auth via helper
  ///
  /// In en, this message translates to:
  /// **'Authenticated with an API key helper'**
  String get mgmtClaudeAuthViaApiKeyHelper;

  /// Auth via OAuth
  ///
  /// In en, this message translates to:
  /// **'Authenticated with an OAuth token'**
  String get mgmtClaudeAuthViaOauthToken;

  /// Auth path detected
  ///
  /// In en, this message translates to:
  /// **'A Claude Code authentication path was detected'**
  String get mgmtClaudeAuthPathDetected;

  /// Third party provider
  ///
  /// In en, this message translates to:
  /// **'A third-party API Provider is configured'**
  String get mgmtThirdPartyApiProviderConfigured;

  /// Configured provider
  ///
  /// In en, this message translates to:
  /// **'{provider} is configured'**
  String mgmtConfiguredProvider(String provider);

  /// Path not regular file
  ///
  /// In en, this message translates to:
  /// **'That path does not exist or is not a regular file'**
  String get mgmtPathNotRegularFile;

  /// Refuse symlink
  ///
  /// In en, this message translates to:
  /// **'Refusing to write a symlink configuration file'**
  String get mgmtRefuseSymlinkConfig;

  /// Config externally modified
  ///
  /// In en, this message translates to:
  /// **'The configuration file was modified externally.'**
  String get mgmtConfigExternallyModified;

  /// Compat supported
  ///
  /// In en, this message translates to:
  /// **'Verified as supported'**
  String get mgmtCompatSupported;

  /// Compat limited
  ///
  /// In en, this message translates to:
  /// **'Runs with limited capabilities'**
  String get mgmtCompatLimited;

  /// Compat newer
  ///
  /// In en, this message translates to:
  /// **'Newer version, not fully verified'**
  String get mgmtCompatNewerUntested;

  /// Compat older
  ///
  /// In en, this message translates to:
  /// **'Too old to be supported'**
  String get mgmtCompatOlderUnsupported;

  /// Compat protocol
  ///
  /// In en, this message translates to:
  /// **'Protocol incompatible'**
  String get mgmtCompatProtocolMismatch;

  /// Cannot enable
  ///
  /// In en, this message translates to:
  /// **'Could not enable {name}: {error}'**
  String mgmtCannotEnable(String name, String error);

  /// Cannot disable
  ///
  /// In en, this message translates to:
  /// **'Could not disable {name}: {error}'**
  String mgmtCannotDisable(String name, String error);

  /// Enrichment save failed
  ///
  /// In en, this message translates to:
  /// **'Could not save usage-detail enrichment: {error}'**
  String mgmtAccountDataEnrichmentSaveFailed(String error);

  /// Connection test failed
  ///
  /// In en, this message translates to:
  /// **'Connection test failed: {error}'**
  String mgmtConnectionTestFailed(String error);

  /// Config read failed
  ///
  /// In en, this message translates to:
  /// **'Could not read the configuration file: {error}'**
  String mgmtConfigurationReadFailed(String error);

  /// Config not loaded
  ///
  /// In en, this message translates to:
  /// **'The configuration file has not been loaded'**
  String get mgmtConfigurationNotLoaded;

  /// Logs read failed
  ///
  /// In en, this message translates to:
  /// **'Could not read runtime logs: {error}'**
  String mgmtLogsReadFailed(String error);

  /// Operation incomplete
  ///
  /// In en, this message translates to:
  /// **'The operation did not finish'**
  String get mgmtOperationIncomplete;

  /// Filter installed
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get mgmtFilterInstalled;

  /// Filter all supported
  ///
  /// In en, this message translates to:
  /// **'All supported'**
  String get mgmtFilterAllSupported;

  /// Search placeholder
  ///
  /// In en, this message translates to:
  /// **'Search Agents or vendors'**
  String get mgmtSearchPlaceholder;

  /// Detecting
  ///
  /// In en, this message translates to:
  /// **'Detecting…'**
  String get mgmtDetecting;

  /// Auto detect
  ///
  /// In en, this message translates to:
  /// **'Auto-detect Agents'**
  String get mgmtAutoDetect;

  /// Empty installed title
  ///
  /// In en, this message translates to:
  /// **'No installed Agent detected'**
  String get mgmtEmptyInstalledTitle;

  /// Empty installed body
  ///
  /// In en, this message translates to:
  /// **'You can auto-detect this machine, or open All supported to see Agents this app supports.'**
  String get mgmtEmptyInstalledBody;

  /// View all supported
  ///
  /// In en, this message translates to:
  /// **'View all supported'**
  String get mgmtViewAllSupported;

  /// No match title
  ///
  /// In en, this message translates to:
  /// **'No matching Agent'**
  String get mgmtNoMatchTitle;

  /// No match body
  ///
  /// In en, this message translates to:
  /// **'Try changing the search.'**
  String get mgmtNoMatchBody;

  /// Clear search
  ///
  /// In en, this message translates to:
  /// **'Clear search'**
  String get mgmtClearSearch;

  /// Version with value
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String mgmtVersionWithValue(String version);

  /// Unknown
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get mgmtUnknown;

  /// Testing
  ///
  /// In en, this message translates to:
  /// **'Testing…'**
  String get mgmtTesting;

  /// Test connection
  ///
  /// In en, this message translates to:
  /// **'Test connection'**
  String get mgmtTestConnection;

  /// View logs
  ///
  /// In en, this message translates to:
  /// **'View runtime logs'**
  String get mgmtViewLogs;

  /// Disable agent
  ///
  /// In en, this message translates to:
  /// **'Disable Agent'**
  String get mgmtDisableAgent;

  /// Enable agent
  ///
  /// In en, this message translates to:
  /// **'Enable Agent'**
  String get mgmtEnableAgent;

  /// Tab basics
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get mgmtTabBasics;

  /// Tab models
  ///
  /// In en, this message translates to:
  /// **'Models'**
  String get mgmtTabModels;

  /// Tab config
  ///
  /// In en, this message translates to:
  /// **'Configuration'**
  String get mgmtTabConfig;

  /// Copied command
  ///
  /// In en, this message translates to:
  /// **'Launch command copied.'**
  String get mgmtCopiedCommand;

  /// Cannot load models
  ///
  /// In en, this message translates to:
  /// **'Could not load the model list'**
  String get mgmtCannotLoadModels;

  /// Models need login
  ///
  /// In en, this message translates to:
  /// **'This account is not signed in. Sign in to Codex and reload.'**
  String get mgmtModelsNeedLogin;

  /// Reload
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get mgmtReload;

  /// Model source line
  ///
  /// In en, this message translates to:
  /// **'Source: {source} · Updated: {updated}'**
  String mgmtModelSourceUpdated(String source, String updated);

  /// Disable warning
  ///
  /// In en, this message translates to:
  /// **'Disabling stops the current task. Existing sessions become read-only.'**
  String get mgmtDisableWarning;

  /// Stop and disable
  ///
  /// In en, this message translates to:
  /// **'Stop and disable'**
  String get mgmtStopAndDisable;

  /// Test Claude title
  ///
  /// In en, this message translates to:
  /// **'Test the Claude Code connection'**
  String get mgmtTestClaudeTitle;

  /// Test Claude body
  ///
  /// In en, this message translates to:
  /// **'Sends a prompt-free initialize control request only and does not call the model; the Claude CLI may still maintain its own auth or bootstrap cache.'**
  String get mgmtTestClaudeBody;

  /// Continue test
  ///
  /// In en, this message translates to:
  /// **'Continue test'**
  String get mgmtContinueTest;

  /// Test success
  ///
  /// In en, this message translates to:
  /// **'Connection test succeeded. Response took {ms} ms.'**
  String mgmtConnectionTestSuccess(String ms);

  /// Test failed message
  ///
  /// In en, this message translates to:
  /// **'Connection test failed: {message}'**
  String mgmtConnectionTestFailedMessage(String message);

  /// Unknown error
  ///
  /// In en, this message translates to:
  /// **'Unknown error'**
  String get mgmtUnknownError;

  /// Open dir failed
  ///
  /// In en, this message translates to:
  /// **'Could not open the executable directory: {error}'**
  String mgmtCannotOpenExecutableDir(String error);

  /// View details
  ///
  /// In en, this message translates to:
  /// **'View {name} details'**
  String mgmtViewDetails(String name);

  /// Version unknown
  ///
  /// In en, this message translates to:
  /// **'Version unknown'**
  String get mgmtVersionUnknown;

  /// Not installed
  ///
  /// In en, this message translates to:
  /// **'Not installed'**
  String get mgmtNotInstalled;

  /// Connection available
  ///
  /// In en, this message translates to:
  /// **'Connection available'**
  String get mgmtConnectionAvailable;

  /// Update available
  ///
  /// In en, this message translates to:
  /// **'Update available'**
  String get mgmtUpdateAvailable;

  /// Detecting short
  ///
  /// In en, this message translates to:
  /// **'Detecting'**
  String get mgmtDetectingShort;

  /// Running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get mgmtRunning;

  /// Enabled
  ///
  /// In en, this message translates to:
  /// **'Enabled'**
  String get mgmtEnabled;

  /// Installed
  ///
  /// In en, this message translates to:
  /// **'Installed'**
  String get mgmtInstalled;

  /// Section basics
  ///
  /// In en, this message translates to:
  /// **'Basics'**
  String get mgmtSectionBasics;

  /// Basic attributes
  ///
  /// In en, this message translates to:
  /// **'Basic attributes'**
  String get mgmtBasicAttributes;

  /// Name
  ///
  /// In en, this message translates to:
  /// **'Name'**
  String get mgmtName;

  /// Vendor
  ///
  /// In en, this message translates to:
  /// **'Vendor'**
  String get mgmtVendor;

  /// Protocol
  ///
  /// In en, this message translates to:
  /// **'Protocol'**
  String get mgmtProtocol;

  /// Transport
  ///
  /// In en, this message translates to:
  /// **'Transport'**
  String get mgmtTransport;

  /// Section version
  ///
  /// In en, this message translates to:
  /// **'Version'**
  String get mgmtSectionVersion;

  /// Current version
  ///
  /// In en, this message translates to:
  /// **'Current version'**
  String get mgmtCurrentVersion;

  /// Latest version
  ///
  /// In en, this message translates to:
  /// **'Latest version'**
  String get mgmtLatestVersion;

  /// Paths and commands
  ///
  /// In en, this message translates to:
  /// **'Paths and commands'**
  String get mgmtPathsAndCommands;

  /// Launch command
  ///
  /// In en, this message translates to:
  /// **'Launch command'**
  String get mgmtLaunchCommand;

  /// Executable path
  ///
  /// In en, this message translates to:
  /// **'Executable path'**
  String get mgmtExecutablePath;

  /// Not detected
  ///
  /// In en, this message translates to:
  /// **'Not detected'**
  String get mgmtNotDetected;

  /// Executable hint
  ///
  /// In en, this message translates to:
  /// **'No executable detected yet. Install it and make sure it is on PATH'**
  String get mgmtExecutableNotDetectedHint;

  /// Auto detect short
  ///
  /// In en, this message translates to:
  /// **'Auto-detect'**
  String get mgmtAutoDetectShort;

  /// Open directory
  ///
  /// In en, this message translates to:
  /// **'Open folder'**
  String get mgmtOpenDirectory;

  /// Program
  ///
  /// In en, this message translates to:
  /// **'Program'**
  String get mgmtProgram;

  /// Executable present
  ///
  /// In en, this message translates to:
  /// **'Executable exists and can be invoked'**
  String get mgmtExecutablePresent;

  /// Executable missing
  ///
  /// In en, this message translates to:
  /// **'Executable not found'**
  String get mgmtExecutableMissing;

  /// Auth evidence
  ///
  /// In en, this message translates to:
  /// **'Auth evidence'**
  String get mgmtAuthEvidence;

  /// Communication
  ///
  /// In en, this message translates to:
  /// **'Communication'**
  String get mgmtCommunication;

  /// Connection probe succeeded
  ///
  /// In en, this message translates to:
  /// **'Connection probe succeeded'**
  String get mgmtConnectionProbeOk;

  /// Handshake ok
  ///
  /// In en, this message translates to:
  /// **'Basic handshake succeeded'**
  String get mgmtHandshakeOk;

  /// Not confirmed
  ///
  /// In en, this message translates to:
  /// **'Not confirmed yet'**
  String get mgmtNotConfirmed;

  /// Last detected
  ///
  /// In en, this message translates to:
  /// **'Last detection'**
  String get mgmtLastDetected;

  /// Last test duration
  ///
  /// In en, this message translates to:
  /// **'Last test duration'**
  String get mgmtLastTestDuration;

  /// Handshake identity
  ///
  /// In en, this message translates to:
  /// **'Handshake identity'**
  String get mgmtHandshakeIdentity;

  /// Capabilities
  ///
  /// In en, this message translates to:
  /// **'Negotiated capabilities'**
  String get mgmtNegotiatedCapabilities;

  /// Compatibility
  ///
  /// In en, this message translates to:
  /// **'Compatibility'**
  String get mgmtCompatibility;

  /// Exit reason
  ///
  /// In en, this message translates to:
  /// **'Exit reason'**
  String get mgmtExitReason;

  /// Failure stage
  ///
  /// In en, this message translates to:
  /// **'Failure stage'**
  String get mgmtFailureStage;

  /// Diagnostics
  ///
  /// In en, this message translates to:
  /// **'Diagnostics'**
  String get mgmtDiagnostics;

  /// Connection healthy
  ///
  /// In en, this message translates to:
  /// **'Connection healthy'**
  String get mgmtConnectionHealthy;

  /// Suggested action
  ///
  /// In en, this message translates to:
  /// **'Suggested action: {suggestion}'**
  String mgmtSuggestedAction(String suggestion);

  /// Hidden model chip
  ///
  /// In en, this message translates to:
  /// **'Hidden'**
  String get mgmtHidden;

  /// Available model chip
  ///
  /// In en, this message translates to:
  /// **'Available'**
  String get mgmtAvailable;

  /// Chip text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get mgmtChipText;

  /// Chip image
  ///
  /// In en, this message translates to:
  /// **'Images'**
  String get mgmtChipImage;

  /// Chip code
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get mgmtChipCode;

  /// Chip files
  ///
  /// In en, this message translates to:
  /// **'File operations'**
  String get mgmtChipFiles;

  /// Chip tools
  ///
  /// In en, this message translates to:
  /// **'Tool calls'**
  String get mgmtChipTools;

  /// Chip terminal
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get mgmtChipTerminal;

  /// Chip streaming
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get mgmtChipStreaming;

  /// Unknown reasoning capability
  ///
  /// In en, this message translates to:
  /// **'Reasoning: unknown'**
  String get mgmtReasoningUnknown;

  /// Adjustable reasoning capability
  ///
  /// In en, this message translates to:
  /// **'Reasoning: adjustable ({efforts})'**
  String mgmtReasoningAdjustable(String efforts);

  /// Quota enrichment title
  ///
  /// In en, this message translates to:
  /// **'Usage-detail enrichment'**
  String get mgmtQuotaEnrichmentTitle;

  /// Quota enrichment label
  ///
  /// In en, this message translates to:
  /// **'Read Claude Code usage details'**
  String get mgmtQuotaEnrichmentLabel;

  /// Quota enrichment body
  ///
  /// In en, this message translates to:
  /// **'This switch only controls whether Zeta briefly reads Claude Code OAuth credentials and calls the usage REST API. Model lists and plan names always come from the Claude CLI; Zeta does not refresh, write back, or persist credentials.'**
  String get mgmtQuotaEnrichmentBody;

  /// Onboarding title
  ///
  /// In en, this message translates to:
  /// **'Setup guide'**
  String get mgmtOnboardingTitle;

  /// Onboarding subtitle
  ///
  /// In en, this message translates to:
  /// **'Install · Sign in · Docs'**
  String get mgmtOnboardingSubtitle;

  /// Account unknown
  ///
  /// In en, this message translates to:
  /// **'Could not detect'**
  String get mgmtAccountUnknown;

  /// Account checking
  ///
  /// In en, this message translates to:
  /// **'Checking'**
  String get mgmtAccountChecking;

  /// Account logged in short
  ///
  /// In en, this message translates to:
  /// **'Signed in'**
  String get mgmtAccountLoggedInShort;

  /// Account logged out
  ///
  /// In en, this message translates to:
  /// **'Signed out'**
  String get mgmtAccountLoggedOut;

  /// Account expired
  ///
  /// In en, this message translates to:
  /// **'Sign-in expired'**
  String get mgmtAccountExpired;

  /// Account not required
  ///
  /// In en, this message translates to:
  /// **'Sign-in not required'**
  String get mgmtAccountNotRequired;

  /// Runtime not running
  ///
  /// In en, this message translates to:
  /// **'Not running'**
  String get mgmtRuntimeNotRunning;

  /// Runtime idle
  ///
  /// In en, this message translates to:
  /// **'Idle'**
  String get mgmtRuntimeIdle;

  /// Runtime starting
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get mgmtRuntimeStarting;

  /// Runtime stopping
  ///
  /// In en, this message translates to:
  /// **'Stopping'**
  String get mgmtRuntimeStopping;

  /// Runtime error
  ///
  /// In en, this message translates to:
  /// **'Error'**
  String get mgmtRuntimeError;

  /// Runtime unavailable
  ///
  /// In en, this message translates to:
  /// **'Unavailable'**
  String get mgmtRuntimeUnavailable;

  /// Runtime disabled
  ///
  /// In en, this message translates to:
  /// **'Disabled'**
  String get mgmtRuntimeDisabled;

  /// Stage file
  ///
  /// In en, this message translates to:
  /// **'File detection'**
  String get mgmtStageFileDetection;

  /// Stage startup
  ///
  /// In en, this message translates to:
  /// **'Process startup'**
  String get mgmtStageCliStartup;

  /// Stage version
  ///
  /// In en, this message translates to:
  /// **'Version detection'**
  String get mgmtStageVersionDetection;

  /// Stage account
  ///
  /// In en, this message translates to:
  /// **'Account authentication'**
  String get mgmtStageAccountAuthentication;

  /// Stage handshake
  ///
  /// In en, this message translates to:
  /// **'Protocol handshake'**
  String get mgmtStageProtocolHandshake;

  /// Stage models
  ///
  /// In en, this message translates to:
  /// **'Model loading'**
  String get mgmtStageModelLoading;

  /// Stage config
  ///
  /// In en, this message translates to:
  /// **'Configuration read'**
  String get mgmtStageConfigurationRead;

  /// Stage test
  ///
  /// In en, this message translates to:
  /// **'Test request'**
  String get mgmtStageTestRequest;

  /// Stage exit
  ///
  /// In en, this message translates to:
  /// **'Process exit'**
  String get mgmtStageProcessExit;

  /// Management list tabs semantics
  ///
  /// In en, this message translates to:
  /// **'Agent list scope'**
  String get mgmtListScope;

  /// Management detail tabs semantics
  ///
  /// In en, this message translates to:
  /// **'Agent details'**
  String get mgmtDetailTabs;

  /// Models empty after handshake failure
  ///
  /// In en, this message translates to:
  /// **'The app-server did not return models, or the current configuration could not complete the handshake.'**
  String get mgmtModelsHandshakeFailed;

  /// Disable-while-running dialog title
  ///
  /// In en, this message translates to:
  /// **'{name} is currently running'**
  String mgmtAgentCurrentlyRunning(String name);

  /// Diagnostics unhealthy subtitle
  ///
  /// In en, this message translates to:
  /// **'Status needs attention'**
  String get mgmtStatusNeedsCheck;

  /// Log view title
  ///
  /// In en, this message translates to:
  /// **'{name} runtime logs'**
  String mgmtRuntimeLogsTitle(String name);

  /// Log view subtitle
  ///
  /// In en, this message translates to:
  /// **'{sources} diagnostic sources · {lines} lines loaded'**
  String mgmtLogSourcesLoaded(String sources, String lines);

  /// Not updated
  ///
  /// In en, this message translates to:
  /// **'Not updated yet'**
  String get mgmtNotUpdated;

  /// Unsaved title
  ///
  /// In en, this message translates to:
  /// **'Configuration is not saved'**
  String get mgmtUnsavedTitle;

  /// Unsaved body
  ///
  /// In en, this message translates to:
  /// **'Leaving now discards these changes.'**
  String get mgmtUnsavedBody;

  /// Keep editing
  ///
  /// In en, this message translates to:
  /// **'Keep editing'**
  String get mgmtKeepEditing;

  /// Discard changes
  ///
  /// In en, this message translates to:
  /// **'Discard changes'**
  String get mgmtDiscardChanges;

  /// Loading config
  ///
  /// In en, this message translates to:
  /// **'Loading the configuration file'**
  String get mgmtLoadingConfig;

  /// Config not loaded yet
  ///
  /// In en, this message translates to:
  /// **'The configuration file has not been loaded.'**
  String get mgmtConfigNotLoadedYet;

  /// Sensitive title
  ///
  /// In en, this message translates to:
  /// **'Sensitive values are hidden'**
  String get mgmtSensitiveMaskedTitle;

  /// Sensitive body
  ///
  /// In en, this message translates to:
  /// **'Shown read-only by default so credentials are not exposed. Click Show sensitive values to edit the full configuration.'**
  String get mgmtSensitiveMaskedBody;

  /// Config file
  ///
  /// In en, this message translates to:
  /// **'Configuration file'**
  String get mgmtConfigFile;

  /// Config exists
  ///
  /// In en, this message translates to:
  /// **'exists'**
  String get mgmtConfigExists;

  /// Config missing
  ///
  /// In en, this message translates to:
  /// **'not created yet'**
  String get mgmtConfigMissing;

  /// Last loaded
  ///
  /// In en, this message translates to:
  /// **'Last loaded {time}'**
  String mgmtLastLoaded(String time);

  /// Reload config
  ///
  /// In en, this message translates to:
  /// **'Reload'**
  String get mgmtReloadConfig;

  /// Open containing folder
  ///
  /// In en, this message translates to:
  /// **'Open containing folder'**
  String get mgmtOpenContainingFolder;

  /// Hide sensitive
  ///
  /// In en, this message translates to:
  /// **'Hide sensitive values'**
  String get mgmtHideSensitive;

  /// Show sensitive
  ///
  /// In en, this message translates to:
  /// **'Show sensitive values'**
  String get mgmtShowSensitive;

  /// Search in config
  ///
  /// In en, this message translates to:
  /// **'Search in configuration'**
  String get mgmtSearchInConfig;

  /// Find next
  ///
  /// In en, this message translates to:
  /// **'Find next'**
  String get mgmtFindNext;

  /// Config valid
  ///
  /// In en, this message translates to:
  /// **'Configuration format is valid'**
  String get mgmtConfigValid;

  /// Cancel edits
  ///
  /// In en, this message translates to:
  /// **'Cancel edits'**
  String get mgmtCancelEdits;

  /// Saving
  ///
  /// In en, this message translates to:
  /// **'Saving…'**
  String get mgmtSaving;

  /// Save config
  ///
  /// In en, this message translates to:
  /// **'Save configuration'**
  String get mgmtSaveConfig;

  /// Saved restart
  ///
  /// In en, this message translates to:
  /// **'Configuration saved. Restart Codex to apply it.'**
  String get mgmtConfigSavedRestart;

  /// Saved backup
  ///
  /// In en, this message translates to:
  /// **'Configuration saved, and a backup of the original file was created.'**
  String get mgmtConfigSavedBackup;

  /// External title
  ///
  /// In en, this message translates to:
  /// **'The configuration file was modified externally'**
  String get mgmtConfigExternalTitle;

  /// External body
  ///
  /// In en, this message translates to:
  /// **'Continuing will overwrite the external changes.'**
  String get mgmtConfigExternalBody;

  /// Save anyway
  ///
  /// In en, this message translates to:
  /// **'Save anyway'**
  String get mgmtSaveAnyway;

  /// Save failed
  ///
  /// In en, this message translates to:
  /// **'Could not save the configuration: {error}'**
  String mgmtConfigSaveFailed(String error);

  /// Query not found
  ///
  /// In en, this message translates to:
  /// **'No matches for \"{query}\".'**
  String mgmtQueryNotFound(String query);

  /// Open config dir
  ///
  /// In en, this message translates to:
  /// **'Could not open the configuration directory: {error}'**
  String mgmtCannotOpenConfigDir(String error);

  /// Refreshing
  ///
  /// In en, this message translates to:
  /// **'Refreshing…'**
  String get mgmtRefreshing;

  /// Refresh
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get mgmtRefresh;

  /// Copy logs
  ///
  /// In en, this message translates to:
  /// **'Copy logs'**
  String get mgmtCopyLogs;

  /// Search logs
  ///
  /// In en, this message translates to:
  /// **'Search log keywords'**
  String get mgmtSearchLogKeywords;

  /// Log level
  ///
  /// In en, this message translates to:
  /// **'Log level'**
  String get mgmtLogLevel;

  /// All
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get mgmtAll;

  /// Reading logs
  ///
  /// In en, this message translates to:
  /// **'Reading Agent logs'**
  String get mgmtReadingLogs;

  /// No matching logs
  ///
  /// In en, this message translates to:
  /// **'No logs match the current filters.'**
  String get mgmtNoMatchingLogs;

  /// Copied logs
  ///
  /// In en, this message translates to:
  /// **'Copied {count} redacted log lines.'**
  String mgmtCopiedLogs(String count);

  /// Disabled agent session title
  ///
  /// In en, this message translates to:
  /// **'This session is read-only'**
  String get agentReadonlyTitle;

  /// Disabled agent session body
  ///
  /// In en, this message translates to:
  /// **'The Agent for this session has been disabled. You can still view history, but you cannot send more messages.'**
  String get agentReadonlyBody;

  /// Composer placeholder
  ///
  /// In en, this message translates to:
  /// **'Message Agent'**
  String get agentMessagePlaceholder;

  /// Send
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get agentSend;

  /// Composer cancel
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentCancel;

  /// Generic cancel action
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get agentCancelAction;

  /// Cancel turn semantics
  ///
  /// In en, this message translates to:
  /// **'Cancel turn'**
  String get agentCancelTurn;

  /// More actions
  ///
  /// In en, this message translates to:
  /// **'More actions'**
  String get agentMoreActions;

  /// More actions expanded
  ///
  /// In en, this message translates to:
  /// **'More actions, expanded'**
  String get agentMoreActionsExpanded;

  /// Mention file
  ///
  /// In en, this message translates to:
  /// **'Mention file'**
  String get agentMentionFile;

  /// Insert skill
  ///
  /// In en, this message translates to:
  /// **'Insert skill'**
  String get agentInsertSkill;

  /// Attach image
  ///
  /// In en, this message translates to:
  /// **'Attach image'**
  String get agentAttachImage;

  /// Permission mode
  ///
  /// In en, this message translates to:
  /// **'Permission mode'**
  String get agentPermissionMode;

  /// Plan mode hint
  ///
  /// In en, this message translates to:
  /// **'Read-only planning; cannot change files'**
  String get agentPlanReadOnlyHint;

  /// Token usage semantics
  ///
  /// In en, this message translates to:
  /// **'Token usage'**
  String get agentTokenUsage;

  /// Context window usage
  ///
  /// In en, this message translates to:
  /// **'Context window token usage'**
  String get agentContextWindowUsage;

  /// Rename thread
  ///
  /// In en, this message translates to:
  /// **'Rename'**
  String get agentRename;

  /// Fork session
  ///
  /// In en, this message translates to:
  /// **'Fork this session'**
  String get agentForkSession;

  /// Archive
  ///
  /// In en, this message translates to:
  /// **'Archive'**
  String get agentArchive;

  /// Context
  ///
  /// In en, this message translates to:
  /// **'Context'**
  String get agentContext;

  /// More
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get agentMore;

  /// Project name
  ///
  /// In en, this message translates to:
  /// **'Project {name}'**
  String agentProjectName(String name);

  /// Read-only plan
  ///
  /// In en, this message translates to:
  /// **'Read-only Plan mode'**
  String get agentReadonlyPlanMode;

  /// Loading session
  ///
  /// In en, this message translates to:
  /// **'Loading session…'**
  String get agentLoadingSession;

  /// Accept plan
  ///
  /// In en, this message translates to:
  /// **'Accept plan'**
  String get agentAcceptPlan;

  /// Accept plan hint
  ///
  /// In en, this message translates to:
  /// **'Accepting the plan only confirms the proposal. Commands, files, and network still need separate permission.'**
  String get agentAcceptPlanHint;

  /// Command group
  ///
  /// In en, this message translates to:
  /// **'Command group'**
  String get agentCommandGroup;

  /// File edit group
  ///
  /// In en, this message translates to:
  /// **'File edit group'**
  String get agentFileEditGroup;

  /// Tool call
  ///
  /// In en, this message translates to:
  /// **'Tool call'**
  String get agentToolCall;

  /// Thinking
  ///
  /// In en, this message translates to:
  /// **'Thinking'**
  String get agentThinking;

  /// Running
  ///
  /// In en, this message translates to:
  /// **'Running'**
  String get agentRunning;

  /// Running prefix
  ///
  /// In en, this message translates to:
  /// **'Running · {title}'**
  String agentRunningPrefix(String title);

  /// Execute
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get agentExecute;

  /// Steps
  ///
  /// In en, this message translates to:
  /// **'Steps'**
  String get agentSteps;

  /// Revise plan hint
  ///
  /// In en, this message translates to:
  /// **'Add to or revise the plan…'**
  String get agentRevisePlanHint;

  /// Revise
  ///
  /// In en, this message translates to:
  /// **'Revise'**
  String get agentRevise;

  /// Abandon
  ///
  /// In en, this message translates to:
  /// **'Abandon'**
  String get agentAbandon;

  /// Execution permission
  ///
  /// In en, this message translates to:
  /// **'Execution permission'**
  String get agentExecPermission;

  /// Choose permission
  ///
  /// In en, this message translates to:
  /// **'Choose execution permission'**
  String get agentChooseExecPermission;

  /// Catalog default
  ///
  /// In en, this message translates to:
  /// **'Conservative default'**
  String get agentPermCatalogDefault;

  /// User override
  ///
  /// In en, this message translates to:
  /// **'This time only'**
  String get agentPermUserOverride;

  /// Needs choice
  ///
  /// In en, this message translates to:
  /// **'Selection required'**
  String get agentPermNeedsChoice;

  /// Permission request
  ///
  /// In en, this message translates to:
  /// **'Permission request: {kind} · {title}'**
  String agentPermissionRequest(String kind, String title);

  /// Deny
  ///
  /// In en, this message translates to:
  /// **'Deny'**
  String get agentDeny;

  /// Allow session
  ///
  /// In en, this message translates to:
  /// **'Allow this session'**
  String get agentAllowSession;

  /// Always allow
  ///
  /// In en, this message translates to:
  /// **'Always allow'**
  String get agentAlwaysAllow;

  /// Override guard
  ///
  /// In en, this message translates to:
  /// **'Override guard'**
  String get agentOverrideGuard;

  /// Allow
  ///
  /// In en, this message translates to:
  /// **'Allow'**
  String get agentAllow;

  /// Perm kind command
  ///
  /// In en, this message translates to:
  /// **'Run command'**
  String get agentPermKindCommand;

  /// Perm kind file
  ///
  /// In en, this message translates to:
  /// **'Apply file changes'**
  String get agentPermKindFile;

  /// Perm kind permissions
  ///
  /// In en, this message translates to:
  /// **'Grant permissions'**
  String get agentPermKindPermissions;

  /// Perm kind other
  ///
  /// In en, this message translates to:
  /// **'Request confirmation'**
  String get agentPermKindOther;

  /// Perm short command
  ///
  /// In en, this message translates to:
  /// **'Command'**
  String get agentPermShortCommand;

  /// Perm short file
  ///
  /// In en, this message translates to:
  /// **'File'**
  String get agentPermShortFile;

  /// Perm short permissions
  ///
  /// In en, this message translates to:
  /// **'Permission'**
  String get agentPermShortPermissions;

  /// Perm short other
  ///
  /// In en, this message translates to:
  /// **'Confirm'**
  String get agentPermShortOther;

  /// Close question
  ///
  /// In en, this message translates to:
  /// **'Close question'**
  String get agentCloseQuestion;

  /// No questions
  ///
  /// In en, this message translates to:
  /// **'This request has no questions to answer.'**
  String get agentNoAnswerableQuestions;

  /// Submit answers
  ///
  /// In en, this message translates to:
  /// **'Submit answers'**
  String get agentSubmitAnswers;

  /// Confirm next
  ///
  /// In en, this message translates to:
  /// **'Confirm and go to the next question'**
  String get agentConfirmNextQuestion;

  /// Skip
  ///
  /// In en, this message translates to:
  /// **'Skip'**
  String get agentSkip;

  /// Submit
  ///
  /// In en, this message translates to:
  /// **'Submit'**
  String get agentSubmit;

  /// Next
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get agentNext;

  /// Multi select
  ///
  /// In en, this message translates to:
  /// **'Multiple options can be selected'**
  String get agentMultiSelect;

  /// Previous question
  ///
  /// In en, this message translates to:
  /// **'Previous question'**
  String get agentPreviousQuestion;

  /// Next question
  ///
  /// In en, this message translates to:
  /// **'Next question'**
  String get agentNextQuestion;

  /// Custom solution
  ///
  /// In en, this message translates to:
  /// **'Enter your solution…'**
  String get agentCustomSolutionHint;

  /// Other custom
  ///
  /// In en, this message translates to:
  /// **'Other, enter a custom solution'**
  String get agentOtherCustomSolution;

  /// Waiting approval
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval'**
  String get agentWaitingApproval;

  /// Waiting input
  ///
  /// In en, this message translates to:
  /// **'Waiting for input'**
  String get agentWaitingInput;

  /// System error
  ///
  /// In en, this message translates to:
  /// **'System error'**
  String get agentSystemError;

  /// Tool read
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get agentToolRead;

  /// Tool edit
  ///
  /// In en, this message translates to:
  /// **'Edit'**
  String get agentToolEdit;

  /// Tool delete
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get agentToolDelete;

  /// Tool move
  ///
  /// In en, this message translates to:
  /// **'Move'**
  String get agentToolMove;

  /// Tool search
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get agentToolSearch;

  /// Tool execute
  ///
  /// In en, this message translates to:
  /// **'Execute'**
  String get agentToolExecute;

  /// Tool think
  ///
  /// In en, this message translates to:
  /// **'Think'**
  String get agentToolThink;

  /// Tool fetch
  ///
  /// In en, this message translates to:
  /// **'Fetch'**
  String get agentToolFetch;

  /// Tool other
  ///
  /// In en, this message translates to:
  /// **'Action'**
  String get agentToolOther;

  /// Turn changes
  ///
  /// In en, this message translates to:
  /// **'Changes in this turn'**
  String get agentTurnChanges;

  /// File count
  ///
  /// In en, this message translates to:
  /// **'{count} files'**
  String agentFileCount(String count);

  /// Conversation nav
  ///
  /// In en, this message translates to:
  /// **'Conversation navigation'**
  String get agentNavConversation;

  /// Turn ordinal
  ///
  /// In en, this message translates to:
  /// **'Turn {n}'**
  String agentTurnOrdinal(String n);

  /// Turn with label
  ///
  /// In en, this message translates to:
  /// **'Turn {n}: {label}'**
  String agentTurnOrdinalWithLabel(String n, String label);

  /// Streaming
  ///
  /// In en, this message translates to:
  /// **'Generating'**
  String get agentStatusStreaming;

  /// Completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get agentStatusCompleted;

  /// Failed
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentStatusFailed;

  /// Interrupted
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get agentStatusInterrupted;

  /// Unknown
  ///
  /// In en, this message translates to:
  /// **'Unknown'**
  String get agentStatusUnknown;

  /// Create branch here
  ///
  /// In en, this message translates to:
  /// **'Create a branch from here'**
  String get agentCreateBranchHere;

  /// Create branch retry
  ///
  /// In en, this message translates to:
  /// **'Create a branch and retry'**
  String get agentCreateBranchRetry;

  /// Create branch body
  ///
  /// In en, this message translates to:
  /// **'The original session is kept, and a new branch starts after the previous turn. Workspace files are not rolled back; earlier Agent writes remain.'**
  String get agentCreateBranchBody;

  /// Edit message
  ///
  /// In en, this message translates to:
  /// **'Edit message…'**
  String get agentEditMessage;

  /// Create branch send
  ///
  /// In en, this message translates to:
  /// **'Create branch and send'**
  String get agentCreateBranchSend;

  /// Plan
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get agentPlan;

  /// Collapse plan
  ///
  /// In en, this message translates to:
  /// **'Collapse plan'**
  String get agentCollapsePlan;

  /// Expand plan
  ///
  /// In en, this message translates to:
  /// **'Expand plan'**
  String get agentExpandPlan;

  /// Collapse current plan
  ///
  /// In en, this message translates to:
  /// **'Collapse current plan'**
  String get agentCollapseCurrentPlan;

  /// Expand current plan
  ///
  /// In en, this message translates to:
  /// **'Expand current plan'**
  String get agentExpandCurrentPlan;

  /// Plan progress
  ///
  /// In en, this message translates to:
  /// **'Current plan progress {progress}'**
  String agentCurrentPlanProgress(String progress);

  /// Current step
  ///
  /// In en, this message translates to:
  /// **'Current step: {content}'**
  String agentCurrentStep(String content);

  /// Current
  ///
  /// In en, this message translates to:
  /// **'Current'**
  String get agentCurrent;

  /// Plan completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get agentPlanCompleted;

  /// Plan in progress
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get agentPlanInProgress;

  /// Plan pending
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get agentPlanPending;

  /// Plan unknown
  ///
  /// In en, this message translates to:
  /// **'Unknown status'**
  String get agentPlanUnknown;

  /// No exec permission
  ///
  /// In en, this message translates to:
  /// **'No execution permission is available. Choose one first. Execution does not pre-authorize commands, files, or the network.'**
  String get agentNoExecPermission;

  /// Default exec permission
  ///
  /// In en, this message translates to:
  /// **'Default is “{label}”. Execution starts a new Default turn. Commands, files, and network still follow that mode.'**
  String agentDefaultExecPermission(String label);

  /// Slash commands
  ///
  /// In en, this message translates to:
  /// **'Commands'**
  String get agentSlashCommands;

  /// Model
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get agentModel;

  /// Model load failed
  ///
  /// In en, this message translates to:
  /// **'Failed to load models'**
  String get agentModelLoadFailed;

  /// Model config
  ///
  /// In en, this message translates to:
  /// **'Model configuration'**
  String get agentModelConfig;

  /// Loading models
  ///
  /// In en, this message translates to:
  /// **'Loading models…'**
  String get agentLoadingModels;

  /// No models
  ///
  /// In en, this message translates to:
  /// **'No models available'**
  String get agentNoModels;

  /// Config next turn
  ///
  /// In en, this message translates to:
  /// **'Configuration applies on the next turn'**
  String get agentConfigNextTurn;

  /// Model unavailable
  ///
  /// In en, this message translates to:
  /// **'This model is currently unavailable'**
  String get agentModelUnavailable;

  /// No reasoning
  ///
  /// In en, this message translates to:
  /// **'This model does not provide configurable reasoning effort'**
  String get agentNoReasoningConfig;

  /// Retry
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get agentRetry;

  /// Reasoning effort
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort'**
  String get agentReasoningEffort;

  /// Fast on
  ///
  /// In en, this message translates to:
  /// **'On'**
  String get agentFastOn;

  /// Fast off
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get agentFastOff;

  /// Close
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get agentClose;

  /// Session name
  ///
  /// In en, this message translates to:
  /// **'Session name'**
  String get agentSessionName;

  /// Session id
  ///
  /// In en, this message translates to:
  /// **'Session ID'**
  String get agentSessionId;

  /// Message count
  ///
  /// In en, this message translates to:
  /// **'Messages'**
  String get agentMessageCount;

  /// Provider
  ///
  /// In en, this message translates to:
  /// **'Provider'**
  String get agentProvider;

  /// Context limit
  ///
  /// In en, this message translates to:
  /// **'Context limit'**
  String get agentContextLimit;

  /// Total tokens
  ///
  /// In en, this message translates to:
  /// **'Total tokens'**
  String get agentTotalTokens;

  /// Input tokens
  ///
  /// In en, this message translates to:
  /// **'Input tokens'**
  String get agentInputTokens;

  /// Output tokens
  ///
  /// In en, this message translates to:
  /// **'Output tokens'**
  String get agentOutputTokens;

  /// Cached tokens
  ///
  /// In en, this message translates to:
  /// **'Cached tokens'**
  String get agentCachedTokens;

  /// Created
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get agentCreatedAt;

  /// Last active
  ///
  /// In en, this message translates to:
  /// **'Last active'**
  String get agentLastActive;

  /// Raw messages
  ///
  /// In en, this message translates to:
  /// **'Raw messages'**
  String get agentRawMessages;

  /// Chat only
  ///
  /// In en, this message translates to:
  /// **'Chat only'**
  String get agentChatOnly;

  /// All
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get agentAll;

  /// Show chat only hint
  ///
  /// In en, this message translates to:
  /// **'Showing chat messages only. Tap to show all.'**
  String get agentShowChatOnly;

  /// Show all hint
  ///
  /// In en, this message translates to:
  /// **'Showing all messages. Tap to show chat only.'**
  String get agentShowAllMessages;

  /// No chat
  ///
  /// In en, this message translates to:
  /// **'No chat messages'**
  String get agentNoChatMessages;

  /// No raw
  ///
  /// In en, this message translates to:
  /// **'No raw messages'**
  String get agentNoRawMessages;

  /// Copy original
  ///
  /// In en, this message translates to:
  /// **'Copy original'**
  String get agentCopyOriginal;

  /// Copied original
  ///
  /// In en, this message translates to:
  /// **'Original copied.'**
  String get agentCopiedOriginal;

  /// Kind approval
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get agentKindApproval;

  /// Kind question
  ///
  /// In en, this message translates to:
  /// **'Question'**
  String get agentKindQuestion;

  /// Kind plan approval
  ///
  /// In en, this message translates to:
  /// **'Plan approval'**
  String get agentKindPlanApproval;

  /// Kind file change
  ///
  /// In en, this message translates to:
  /// **'File change'**
  String get agentKindFileChange;

  /// Role user
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get agentRoleUser;

  /// Role agent
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get agentRoleAgent;

  /// Role system
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get agentRoleSystem;

  /// Replace before
  ///
  /// In en, this message translates to:
  /// **'Before replacement'**
  String get agentEvidenceReplaceBefore;

  /// Replace after
  ///
  /// In en, this message translates to:
  /// **'After replacement'**
  String get agentEvidenceReplaceAfter;

  /// Empty snippet
  ///
  /// In en, this message translates to:
  /// **'Empty snippet (explicitly provided by the Provider)'**
  String get agentEvidenceEmptySnippet;

  /// Empty content
  ///
  /// In en, this message translates to:
  /// **'Empty content (explicitly provided by the Provider)'**
  String get agentEvidenceEmptyContent;

  /// Empty diff
  ///
  /// In en, this message translates to:
  /// **'Empty diff (explicitly provided by the Provider)'**
  String get agentEvidenceEmptyDiff;

  /// Added
  ///
  /// In en, this message translates to:
  /// **'Added'**
  String get agentEvidenceAdd;

  /// Removed
  ///
  /// In en, this message translates to:
  /// **'Removed'**
  String get agentEvidenceRemove;

  /// Write
  ///
  /// In en, this message translates to:
  /// **'Write'**
  String get agentEvidenceWrite;

  /// Written content
  ///
  /// In en, this message translates to:
  /// **'Written content'**
  String get agentWrittenContent;

  /// Written content with status
  ///
  /// In en, this message translates to:
  /// **'{title} · {status}'**
  String agentWrittenContentWithStatus(String title, String status);

  /// Unified diff
  ///
  /// In en, this message translates to:
  /// **'Unified diff'**
  String get agentUnifiedDiff;

  /// Diff metadata
  ///
  /// In en, this message translates to:
  /// **'Diff metadata'**
  String get agentDiffMetadata;

  /// Hunk title
  ///
  /// In en, this message translates to:
  /// **'Diff hunk title'**
  String get agentDiffHunkTitle;

  /// Empty line
  ///
  /// In en, this message translates to:
  /// **'Empty line'**
  String get agentEmptyLine;

  /// Live summary
  ///
  /// In en, this message translates to:
  /// **'Live summary for this turn'**
  String get agentLiveSummary;

  /// Live summary hint
  ///
  /// In en, this message translates to:
  /// **'Live summary for this turn; cannot be restored from history'**
  String get agentLiveSummaryHint;

  /// Turn summary
  ///
  /// In en, this message translates to:
  /// **'Summary for this turn'**
  String get agentTurnSummary;

  /// Replace snippet
  ///
  /// In en, this message translates to:
  /// **'Replacement snippet'**
  String get agentReplaceSnippet;

  /// Replace all
  ///
  /// In en, this message translates to:
  /// **'Replacement snippet · all matches'**
  String get agentReplaceSnippetAll;

  /// File created
  ///
  /// In en, this message translates to:
  /// **'Created'**
  String get agentFileCreated;

  /// File modified
  ///
  /// In en, this message translates to:
  /// **'Modified'**
  String get agentFileModified;

  /// File deleted
  ///
  /// In en, this message translates to:
  /// **'Deleted'**
  String get agentFileDeleted;

  /// File moved
  ///
  /// In en, this message translates to:
  /// **'Moved'**
  String get agentFileMoved;

  /// File changed
  ///
  /// In en, this message translates to:
  /// **'File change'**
  String get agentFileChanged;

  /// Tool pending
  ///
  /// In en, this message translates to:
  /// **'Pending'**
  String get agentToolPending;

  /// Tool in progress
  ///
  /// In en, this message translates to:
  /// **'In progress'**
  String get agentToolInProgress;

  /// Tool completed
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get agentToolCompleted;

  /// Tool failed
  ///
  /// In en, this message translates to:
  /// **'Failed'**
  String get agentToolFailed;

  /// Tool cancelled
  ///
  /// In en, this message translates to:
  /// **'Cancelled'**
  String get agentToolCancelled;

  /// Mode icon
  ///
  /// In en, this message translates to:
  /// **'Conversation mode icon'**
  String get agentConversationModeIcon;

  /// Mode options
  ///
  /// In en, this message translates to:
  /// **'Conversation mode options'**
  String get agentConversationModeOptions;

  /// Selected
  ///
  /// In en, this message translates to:
  /// **'Selected'**
  String get agentModeSelected;

  /// Selectable
  ///
  /// In en, this message translates to:
  /// **'Selectable'**
  String get agentModeSelectable;

  /// Not selectable
  ///
  /// In en, this message translates to:
  /// **'Not selectable'**
  String get agentModeNotSelectable;

  /// Loading modes
  ///
  /// In en, this message translates to:
  /// **'Loading conversation modes'**
  String get agentLoadingModes;

  /// Cannot load modes
  ///
  /// In en, this message translates to:
  /// **'The current Provider cannot load conversation modes'**
  String get agentCannotLoadModes;

  /// Turn starting activity
  ///
  /// In en, this message translates to:
  /// **'Starting'**
  String get agentStarting;

  /// Turn responding activity
  ///
  /// In en, this message translates to:
  /// **'Responding'**
  String get agentResponding;

  /// Plan execution handoff title
  ///
  /// In en, this message translates to:
  /// **'Plan ready'**
  String get agentPlanReady;

  /// Model reroute event title
  ///
  /// In en, this message translates to:
  /// **'Model rerouted'**
  String get agentModelRerouted;

  /// Model reroute notice
  ///
  /// In en, this message translates to:
  /// **'Rerouted to {model}'**
  String agentModelReroutedTo(String model);

  /// Deprecation event title
  ///
  /// In en, this message translates to:
  /// **'Adapter deprecation notice'**
  String get agentDeprecationNotice;

  /// Deprecation upgrade hint
  ///
  /// In en, this message translates to:
  /// **'Please upgrade the Codex adapter to stay compatible with protocol changes.'**
  String get agentDeprecationUpgradeHint;

  /// Known reroute reason
  ///
  /// In en, this message translates to:
  /// **'Reason: high-risk cyber activity policy'**
  String get agentRerouteReasonHighRisk;

  /// Unknown reroute reason
  ///
  /// In en, this message translates to:
  /// **'Reason: {reason}'**
  String agentRerouteReasonUnknown(String reason);

  /// Turn failed prefix
  ///
  /// In en, this message translates to:
  /// **'Turn failed: '**
  String get agentTurnFailedPrefix;

  /// Unknown provider error
  ///
  /// In en, this message translates to:
  /// **'Unknown provider error'**
  String get agentUnknownProviderError;

  /// Automatic retry hint
  ///
  /// In en, this message translates to:
  /// **' (the server will retry automatically)'**
  String get agentServerWillRetry;

  /// Overloaded guidance
  ///
  /// In en, this message translates to:
  /// **'. The selected model is at capacity. Switch models or try again later.'**
  String get agentErrorGuidanceServerOverloaded;

  /// Usage limit guidance
  ///
  /// In en, this message translates to:
  /// **'. Usage or rate limit reached. Check your quota or try again later.'**
  String get agentErrorGuidanceUsageLimit;

  /// Session budget guidance
  ///
  /// In en, this message translates to:
  /// **'. Session budget is exhausted. Start a new session or adjust the budget.'**
  String get agentErrorGuidanceSessionBudget;

  /// Unauthorized guidance
  ///
  /// In en, this message translates to:
  /// **'. Authentication failed. Check sign-in or API credentials and retry.'**
  String get agentErrorGuidanceUnauthorized;

  /// Internal error guidance
  ///
  /// In en, this message translates to:
  /// **'. The server reported an internal error. Retry later or switch models.'**
  String get agentErrorGuidanceInternalServer;

  /// Network guidance
  ///
  /// In en, this message translates to:
  /// **'. Network connection failed. Check the network and retry.'**
  String get agentErrorGuidanceNetwork;

  /// Too many attempts guidance
  ///
  /// In en, this message translates to:
  /// **'. Too many failed retries. Try again later or switch models.'**
  String get agentErrorGuidanceTooManyAttempts;

  /// Web search tool title
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get agentWebSearch;

  /// View image tool title
  ///
  /// In en, this message translates to:
  /// **'View image'**
  String get agentViewImage;

  /// Generate image tool title
  ///
  /// In en, this message translates to:
  /// **'Generate image'**
  String get agentGenerateImage;

  /// Collaborate tool prefix
  ///
  /// In en, this message translates to:
  /// **'Collaborate'**
  String get agentCollaboratePrefix;

  /// Opaque tool title fallback
  ///
  /// In en, this message translates to:
  /// **'Tool call'**
  String get agentToolCallFallback;

  /// Review mode entered
  ///
  /// In en, this message translates to:
  /// **'Entered review mode'**
  String get agentReviewModeEntered;

  /// Review mode exited
  ///
  /// In en, this message translates to:
  /// **'Exited review mode'**
  String get agentReviewModeExited;

  /// Context compacted title
  ///
  /// In en, this message translates to:
  /// **'Context compacted'**
  String get agentContextCompacted;

  /// Context compacted body
  ///
  /// In en, this message translates to:
  /// **'Session context was compacted to free window space.'**
  String get agentContextCompactedDescription;

  /// Hook prompt title
  ///
  /// In en, this message translates to:
  /// **'Hook prompt'**
  String get agentHookPrompt;

  /// Sleep waiting title
  ///
  /// In en, this message translates to:
  /// **'Waiting'**
  String get agentWaiting;

  /// Sleep minutes
  ///
  /// In en, this message translates to:
  /// **'Slept {minutes} minutes'**
  String agentSleepMinutes(String minutes);

  /// Sleep minutes and seconds
  ///
  /// In en, this message translates to:
  /// **'Slept {minutes} min {seconds} s'**
  String agentSleepMinutesSeconds(String minutes, String seconds);

  /// Sleep seconds
  ///
  /// In en, this message translates to:
  /// **'Slept {seconds} seconds'**
  String agentSleepSeconds(String seconds);

  /// Sub-agent activity title
  ///
  /// In en, this message translates to:
  /// **'Sub-agent activity'**
  String get agentSubAgentActivity;

  /// Sub-agent started
  ///
  /// In en, this message translates to:
  /// **'Started'**
  String get agentSubAgentStarted;

  /// Sub-agent interacted
  ///
  /// In en, this message translates to:
  /// **'Interacted'**
  String get agentSubAgentInteracted;

  /// Sub-agent interrupted
  ///
  /// In en, this message translates to:
  /// **'Interrupted'**
  String get agentSubAgentInterrupted;

  /// Sub-agent updated
  ///
  /// In en, this message translates to:
  /// **'Updated'**
  String get agentSubAgentUpdated;

  /// User cancelled turn
  ///
  /// In en, this message translates to:
  /// **'Cancelled by user'**
  String get agentUserCancelled;

  /// Ask permission description
  ///
  /// In en, this message translates to:
  /// **'Ask before every high-risk tool'**
  String get agentPermissionAskDescription;

  /// Accept edits description
  ///
  /// In en, this message translates to:
  /// **'Allow edit tools automatically; still ask for others'**
  String get agentPermissionAcceptEditsDescription;

  /// Plan permission description
  ///
  /// In en, this message translates to:
  /// **'Read-only planning; no side effects'**
  String get agentPermissionPlanDescription;

  /// Bypass permission description
  ///
  /// In en, this message translates to:
  /// **'Skip permission checks (high risk)'**
  String get agentPermissionBypassDescription;

  /// Plan quota fallback
  ///
  /// In en, this message translates to:
  /// **'Plan quota'**
  String get agentPlanQuota;

  /// On-demand quota fallback
  ///
  /// In en, this message translates to:
  /// **'On-demand quota'**
  String get agentOnDemandQuota;

  /// Primary quota fallback
  ///
  /// In en, this message translates to:
  /// **'Primary quota'**
  String get agentPrimaryQuota;

  /// Extra quota fallback
  ///
  /// In en, this message translates to:
  /// **'Extra quota'**
  String get agentExtraQuota;

  /// Desktop notification title for a finished turn
  ///
  /// In en, this message translates to:
  /// **'Task completed'**
  String get desktopAttentionTurnCompleted;

  /// Desktop notification title for a failed turn
  ///
  /// In en, this message translates to:
  /// **'Task failed'**
  String get desktopAttentionTurnFailed;

  /// Desktop notification title for an interrupted turn
  ///
  /// In en, this message translates to:
  /// **'Task interrupted'**
  String get desktopAttentionTurnInterrupted;

  /// Desktop notification title for a permission request
  ///
  /// In en, this message translates to:
  /// **'Permission required'**
  String get desktopAttentionPermissionRequired;

  /// Desktop notification title for a user question
  ///
  /// In en, this message translates to:
  /// **'Question required'**
  String get desktopAttentionQuestionRequired;

  /// Desktop notification title for plan approval
  ///
  /// In en, this message translates to:
  /// **'Plan approval required'**
  String get desktopAttentionPlanApprovalRequired;

  /// Desktop notification title for plan execution handoff
  ///
  /// In en, this message translates to:
  /// **'Plan ready to execute'**
  String get desktopAttentionPlanExecutionRequired;

  /// Fallback project name in desktop notification body
  ///
  /// In en, this message translates to:
  /// **'Current project'**
  String get desktopAttentionCurrentProject;

  /// Safe desktop notification body
  ///
  /// In en, this message translates to:
  /// **'{project} · Agent session'**
  String desktopAttentionSessionBody(String project);

  /// Linux notification default action
  ///
  /// In en, this message translates to:
  /// **'Open Zeta'**
  String get desktopAttentionLinuxAction;

  /// Scroll-to-end button semantics
  ///
  /// In en, this message translates to:
  /// **'Scroll to the end of the conversation'**
  String get timelineScrollToEnd;

  /// Relative time under one minute
  ///
  /// In en, this message translates to:
  /// **'Just now'**
  String get relativeTimeJustNow;

  /// Relative time in minutes
  ///
  /// In en, this message translates to:
  /// **'{count} minutes ago'**
  String relativeTimeMinutesAgo(String count);

  /// Relative time in hours
  ///
  /// In en, this message translates to:
  /// **'{count} hours ago'**
  String relativeTimeHoursAgo(String count);

  /// Relative time in days
  ///
  /// In en, this message translates to:
  /// **'{count} days ago'**
  String relativeTimeDaysAgo(String count);

  /// Context panel user message kind
  ///
  /// In en, this message translates to:
  /// **'User'**
  String get contextRoleUser;

  /// Context panel assistant message kind
  ///
  /// In en, this message translates to:
  /// **'Assistant'**
  String get contextRoleAssistant;

  /// Context panel system message kind
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get contextRoleSystem;

  /// Context panel plan message kind
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get contextRolePlan;

  /// Context panel permission event
  ///
  /// In en, this message translates to:
  /// **'Approval'**
  String get contextEventPermission;

  /// Context panel warning event
  ///
  /// In en, this message translates to:
  /// **'Warning'**
  String get contextEventWarning;

  /// Empty usage statistic placeholder
  ///
  /// In en, this message translates to:
  /// **'No data'**
  String get usageNoData;

  /// Unknown usage plan name
  ///
  /// In en, this message translates to:
  /// **'Unknown plan'**
  String get usageUnknownPlan;

  /// Model capability text
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get mgmtCapText;

  /// Model capability image
  ///
  /// In en, this message translates to:
  /// **'Image'**
  String get mgmtCapImage;

  /// Model capability code
  ///
  /// In en, this message translates to:
  /// **'Code'**
  String get mgmtCapCode;

  /// Model capability file ops
  ///
  /// In en, this message translates to:
  /// **'File operations'**
  String get mgmtCapFileOps;

  /// Model capability tools
  ///
  /// In en, this message translates to:
  /// **'Tool calls'**
  String get mgmtCapToolCall;

  /// Model capability terminal
  ///
  /// In en, this message translates to:
  /// **'Terminal'**
  String get mgmtCapTerminal;

  /// Model capability streaming
  ///
  /// In en, this message translates to:
  /// **'Streaming'**
  String get mgmtCapStreaming;

  /// Claude quota enrichment subtitle
  ///
  /// In en, this message translates to:
  /// **'OAuth credentials · Usage REST'**
  String get mgmtQuotaEnrichmentSubtitle;

  /// Claude setup guide title
  ///
  /// In en, this message translates to:
  /// **'Setup guide'**
  String get mgmtSetupGuideTitle;

  /// Claude setup guide subtitle
  ///
  /// In en, this message translates to:
  /// **'Install · Sign in · Docs'**
  String get mgmtSetupGuideSubtitle;

  /// Claude setup install title
  ///
  /// In en, this message translates to:
  /// **'1. Install the Claude Code CLI'**
  String get mgmtSetupInstallTitle;

  /// Claude setup install body
  ///
  /// In en, this message translates to:
  /// **'Run npm install -g @anthropic-ai/claude-code in a terminal, and make sure claude is on PATH.'**
  String get mgmtSetupInstallBody;

  /// Claude setup login title
  ///
  /// In en, this message translates to:
  /// **'2. Sign in'**
  String get mgmtSetupLoginTitle;

  /// Claude setup login body
  ///
  /// In en, this message translates to:
  /// **'Run claude auth login to sign in to your Anthropic account. Auto-detect never reads credential contents; quota enrichment only does the read-only query described above and never writes the credential file.'**
  String get mgmtSetupLoginBody;

  /// Claude setup docs title
  ///
  /// In en, this message translates to:
  /// **'3. Official docs'**
  String get mgmtSetupDocsTitle;

  /// Claude setup docs body
  ///
  /// In en, this message translates to:
  /// **'See the Anthropic Claude Code docs for full capabilities and protocol details: {url}'**
  String mgmtSetupDocsBody(String url);

  /// Bundled Geist font label
  ///
  /// In en, this message translates to:
  /// **'Geist (built-in default)'**
  String get fontGeistBundled;

  /// Search alias for system default font
  ///
  /// In en, this message translates to:
  /// **'System default'**
  String get fontSystemDefaultAlias;

  /// Bundled JetBrains Mono label
  ///
  /// In en, this message translates to:
  /// **'JetBrainsMono (built-in default)'**
  String get fontJetBrainsBundled;

  /// Conversation mode load error
  ///
  /// In en, this message translates to:
  /// **'Could not load conversation modes. Please retry.'**
  String get agentModeLoadFailed;

  /// Fast vs reasoning conflict
  ///
  /// In en, this message translates to:
  /// **'Fast is incompatible with “{effort}”'**
  String agentFastIncompatible(String effort);

  /// Resolve Fast conflict by disabling Fast
  ///
  /// In en, this message translates to:
  /// **'Turn off Fast and switch to {effort}'**
  String agentFastDisableAndSwitch(String effort);

  /// Resolve Fast conflict by lowering effort
  ///
  /// In en, this message translates to:
  /// **'Switch to {effort} and turn on Fast'**
  String agentFastSwitchAndEnable(String effort);

  /// Model config save failure
  ///
  /// In en, this message translates to:
  /// **'Could not save the configuration. The last valid settings were restored.'**
  String get agentModelSaveFailed;

  /// Model fallback notice
  ///
  /// In en, this message translates to:
  /// **'Model “{previous}” is unavailable. Switched to {current}.'**
  String agentModelUnavailableSwitched(String previous, String current);

  /// Permission apply scope next session
  ///
  /// In en, this message translates to:
  /// **'Applies to the next session'**
  String get agentPermNextSession;

  /// Permission apply scope current turn
  ///
  /// In en, this message translates to:
  /// **'Applies to this turn'**
  String get agentPermCurrentTurn;

  /// Permission selection unsupported
  ///
  /// In en, this message translates to:
  /// **'The current Provider does not support permission selection'**
  String get agentPermUnsupported;

  /// Permission applies next send
  ///
  /// In en, this message translates to:
  /// **'Applies the next time you send'**
  String get agentPermNextSend;

  /// Permission persist failed after update
  ///
  /// In en, this message translates to:
  /// **'Permission preference updated, but saving failed. You can retry.'**
  String get agentPermSavedButPersistFailed;

  /// Permission persist failed after apply
  ///
  /// In en, this message translates to:
  /// **'Permission preference applied, but saving failed. You can retry.'**
  String get agentPermAppliedButPersistFailed;

  /// Permission runtime stale
  ///
  /// In en, this message translates to:
  /// **'The Provider runtime is no longer valid. Please retry.'**
  String get agentPermRuntimeStale;

  /// Permission mode switch failed
  ///
  /// In en, this message translates to:
  /// **'Could not switch the permission mode'**
  String get agentPermSwitchFailed;

  /// Plan handoff provider default permission
  ///
  /// In en, this message translates to:
  /// **'Provider default permission'**
  String get agentProviderDefaultPermission;

  /// Shell cannot mutate disabled provider thread
  ///
  /// In en, this message translates to:
  /// **'{name} is disabled or unavailable; the session cannot be modified.'**
  String agentThreadDisabled(String name);

  /// Context raw empty
  ///
  /// In en, this message translates to:
  /// **'(No raw data)'**
  String get agentNoRawPayload;

  /// Live turn spinner semantics
  ///
  /// In en, this message translates to:
  /// **'Turn running'**
  String get agentTurnRunning;

  /// Tool spinner semantics
  ///
  /// In en, this message translates to:
  /// **'Tool running'**
  String get agentToolRunning;

  /// Empty navigation prompt
  ///
  /// In en, this message translates to:
  /// **'(No prompt summary)'**
  String get agentNoPromptSummary;

  /// Navigation status line
  ///
  /// In en, this message translates to:
  /// **'Status: {status}'**
  String agentStatusWithValue(String status);

  /// Navigation time line
  ///
  /// In en, this message translates to:
  /// **'Time: {time}'**
  String agentTimeWithValue(String time);

  /// History loading semantics
  ///
  /// In en, this message translates to:
  /// **'Loading thread history'**
  String get agentLoadingHistory;

  /// Skill picker empty
  ///
  /// In en, this message translates to:
  /// **'No skills found'**
  String get agentNoSkills;

  /// Slash picker empty
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get agentNoMatches;

  /// Tool kind count
  ///
  /// In en, this message translates to:
  /// **'{count}×{kind}'**
  String agentCountTimes(String count, String kind);

  /// Turn elapsed total
  ///
  /// In en, this message translates to:
  /// **'Total {duration}'**
  String agentElapsedTotal(String duration);

  /// Nav tick current suffix
  ///
  /// In en, this message translates to:
  /// **', currently viewing'**
  String get agentCurrentlyViewing;

  /// Evidence line count
  ///
  /// In en, this message translates to:
  /// **'{count} lines'**
  String agentLineCount(String count);

  /// Evidence add/remove
  ///
  /// In en, this message translates to:
  /// **'Added {added} lines, removed {removed} lines'**
  String agentAddedRemovedLines(String added, String removed);

  /// Missing file evidence
  ///
  /// In en, this message translates to:
  /// **'The Provider did not supply content evidence'**
  String get agentNoContentEvidence;

  /// Permission origin before plan
  ///
  /// In en, this message translates to:
  /// **'Before Plan'**
  String get agentBeforePlan;

  /// Question card semantics
  ///
  /// In en, this message translates to:
  /// **'Agent question'**
  String get agentAsk;

  /// Custom mode hint
  ///
  /// In en, this message translates to:
  /// **'This is a read-only custom mode. You can override it with a built-in mode.'**
  String get agentReadOnlyCustomMode;

  /// Mode selector loading semantics
  ///
  /// In en, this message translates to:
  /// **'Mode…, conversation mode, loading'**
  String get agentModeLoadingSemantic;

  /// Mode selector error semantics
  ///
  /// In en, this message translates to:
  /// **'Mode unavailable, conversation mode, {detail}'**
  String agentModeErrorSemantic(String detail);

  /// Mode applies next turn
  ///
  /// In en, this message translates to:
  /// **'{label} · next turn'**
  String agentNextTurnShort(String label);

  /// Mode read-only suffix
  ///
  /// In en, this message translates to:
  /// **', current mode is read-only'**
  String get agentModeReadOnlySuffix;

  /// Mode next-turn suffix
  ///
  /// In en, this message translates to:
  /// **', applies on the next turn'**
  String get agentNextTurnSuffix;

  /// Unknown mode tooltip
  ///
  /// In en, this message translates to:
  /// **'The current mode comes from the Provider. You can override it with a built-in mode.'**
  String get agentModeProviderSet;

  /// Next turn tooltip
  ///
  /// In en, this message translates to:
  /// **'{label}\nApplies on the next turn'**
  String agentNextTurnAppliesTooltip(String label);

  /// Mode trigger semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, conversation mode{suffix}'**
  String agentConversationModeSemantic(String label, String suffix);

  /// Mode option semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, {state}'**
  String agentModeOptionSemantic(String label, String state);

  /// Model tooltip effort
  ///
  /// In en, this message translates to:
  /// **'Reasoning effort: {value}'**
  String agentReasoningEffortValue(String value);

  /// Model tooltip Fast
  ///
  /// In en, this message translates to:
  /// **'Fast: {value}'**
  String agentFastValue(String value);

  /// Model trigger semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, model configuration'**
  String agentModelConfigSemantic(String label);

  /// Model trigger error semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, {error}'**
  String agentModelConfigErrorSemantic(String label, String error);

  /// Composer plan badge next turn
  ///
  /// In en, this message translates to:
  /// **'Plan, conversation mode, applies next turn, tap to clear'**
  String get agentPlanModeClearNextTurn;

  /// Composer plan badge
  ///
  /// In en, this message translates to:
  /// **'Plan, conversation mode, tap to clear'**
  String get agentPlanModeClear;

  /// Composer plan tooltip
  ///
  /// In en, this message translates to:
  /// **'Plan\nApplies on the next turn'**
  String get agentPlanNextTurnTooltip;

  /// ViewModel mode loading
  ///
  /// In en, this message translates to:
  /// **'Loading conversation modes…'**
  String get agentLoadingModesStatus;

  /// ViewModel unknown mode
  ///
  /// In en, this message translates to:
  /// **'The current mode cannot be selected directly'**
  String get agentModeNotSelectableNow;

  /// Model catalog cache fallback
  ///
  /// In en, this message translates to:
  /// **'Model catalog refresh failed. Using the local cache.'**
  String get agentModelCatalogRefreshFailed;

  /// Model list refresh failed
  ///
  /// In en, this message translates to:
  /// **'Model list refresh failed. The current configuration was kept.'**
  String get agentModelListRefreshFailed;

  /// Permission switch blocked
  ///
  /// In en, this message translates to:
  /// **'A turn is running. Wait until it finishes before changing the permission mode.'**
  String get agentCannotSwitchPermissionDuringTurn;

  /// Provider ready status
  ///
  /// In en, this message translates to:
  /// **'{name} ready'**
  String agentProviderReady(String name);

  /// Provider load failed
  ///
  /// In en, this message translates to:
  /// **'Could not load Agent providers'**
  String get agentCouldNotLoadProviders;

  /// Provider working status
  ///
  /// In en, this message translates to:
  /// **'Agent is working'**
  String get agentIsWorking;

  /// Branch creation status
  ///
  /// In en, this message translates to:
  /// **'Creating branch'**
  String get agentCreatingBranch;

  /// Session option update failed
  ///
  /// In en, this message translates to:
  /// **'Could not update session option'**
  String get agentCouldNotUpdateSessionOption;

  /// Provider operation failed
  ///
  /// In en, this message translates to:
  /// **'Agent provider operation failed'**
  String get agentProviderOperationFailed;

  /// Replacement evidence semantics
  ///
  /// In en, this message translates to:
  /// **'Replacement snippet, {before} lines before, {after} lines after'**
  String agentEvidenceReplaceSemantics(String before, String after);

  /// Written evidence semantics
  ///
  /// In en, this message translates to:
  /// **'Written content, {status}, {count} lines'**
  String agentWrittenContentSemantics(String status, String count);

  /// Patch evidence semantics
  ///
  /// In en, this message translates to:
  /// **'Unified diff, {count} lines'**
  String agentUnifiedDiffSemantics(String count);

  /// Evidence viewport semantics
  ///
  /// In en, this message translates to:
  /// **'{title}, scrollable, {count} lines'**
  String agentScrollableLines(String title, String count);

  /// Evidence keyboard scroll hint
  ///
  /// In en, this message translates to:
  /// **'Use arrow keys, Page Up, Page Down, Home, or End to scroll'**
  String get agentKeyboardScrollHint;

  /// Evidence line semantics
  ///
  /// In en, this message translates to:
  /// **'{kind}, line {n}: {text}'**
  String agentLineAt(String kind, String n, String text);

  /// Question pager
  ///
  /// In en, this message translates to:
  /// **'{current} of {total}'**
  String agentQuestionProgress(String current, String total);

  /// Composer remove image tooltip
  ///
  /// In en, this message translates to:
  /// **'Remove image'**
  String get agentRemoveImage;

  /// Permission trigger tooltip with hint
  ///
  /// In en, this message translates to:
  /// **'Permission mode · {hint}'**
  String agentPermissionModeHint(String hint);

  /// Permission trigger semantics with hint
  ///
  /// In en, this message translates to:
  /// **'{label}, permission mode, {hint}'**
  String agentPermissionModeSemantic(String label, String hint);

  /// Permission trigger semantics
  ///
  /// In en, this message translates to:
  /// **'{label}, permission mode'**
  String agentPermissionModeOnly(String label);

  /// Fast switch semantics
  ///
  /// In en, this message translates to:
  /// **'{model}, Fast, {state}'**
  String agentFastSemantic(String model, String state);

  /// Disabled model tooltip
  ///
  /// In en, this message translates to:
  /// **'This model is currently unavailable'**
  String get agentModelUnavailableNow;

  /// Selected option suffix
  ///
  /// In en, this message translates to:
  /// **', selected'**
  String get agentOptionSelectedSuffix;

  /// Generic labeled value
  ///
  /// In en, this message translates to:
  /// **'{label}: {value}'**
  String agentLabeledValue(String label, String value);

  /// Provider starting status
  ///
  /// In en, this message translates to:
  /// **'Starting {name}'**
  String agentStartingProvider(String name);

  /// Provider preparing status
  ///
  /// In en, this message translates to:
  /// **'Preparing {name}'**
  String agentPreparingProvider(String name);

  /// Provider start failed
  ///
  /// In en, this message translates to:
  /// **'Could not start {name}'**
  String agentCouldNotStart(String name);

  /// Provider protocol warning
  ///
  /// In en, this message translates to:
  /// **'{name} protocol warning'**
  String agentProtocolWarning(String name);

  /// Provider request timeout
  ///
  /// In en, this message translates to:
  /// **'{name} request timed out. Please try again.'**
  String agentRequestTimedOut(String name);

  /// Provider connection closed retry
  ///
  /// In en, this message translates to:
  /// **'{name} connection closed. Reconnect and try again.'**
  String agentConnectionClosedRetry(String name);

  /// App-server connection closed
  ///
  /// In en, this message translates to:
  /// **'{name} App Server connection closed'**
  String agentAppServerConnectionClosed(String name);

  /// Provider process exited
  ///
  /// In en, this message translates to:
  /// **'{name} process exited'**
  String agentProcessExited(String name);

  /// Prompt send failed
  ///
  /// In en, this message translates to:
  /// **'Failed to send prompt'**
  String get agentFailedToSendPrompt;

  /// Waiting approval status
  ///
  /// In en, this message translates to:
  /// **'Waiting for approval: {title}'**
  String agentWaitingApprovalFor(String title);

  /// Waiting answers status
  ///
  /// In en, this message translates to:
  /// **'Waiting for answers: {title}'**
  String agentWaitingAnswersFor(String title);

  /// Waiting plan approval status
  ///
  /// In en, this message translates to:
  /// **'Waiting for plan approval'**
  String get agentWaitingPlanApproval;

  /// Plan approval request title
  ///
  /// In en, this message translates to:
  /// **'Plan approval'**
  String get agentPlanApprovalTitle;

  /// Session identity mismatch
  ///
  /// In en, this message translates to:
  /// **'{name} changed session identity unexpectedly'**
  String agentSessionIdentityChanged(String name);

  /// Session restore failed
  ///
  /// In en, this message translates to:
  /// **'{name} could not restore the requested session'**
  String agentCouldNotRestoreSession(String name);

  /// Permission request description
  ///
  /// In en, this message translates to:
  /// **'{name} requests permission to use {tool}'**
  String agentPermissionRequestDescription(String name, String tool);

  /// History apply-patch title
  ///
  /// In en, this message translates to:
  /// **'Apply patch'**
  String get agentApplyPatch;

  /// History tool-search title
  ///
  /// In en, this message translates to:
  /// **'Tool search'**
  String get agentHistoryToolSearch;

  /// History web-search title
  ///
  /// In en, this message translates to:
  /// **'Web search'**
  String get agentHistoryWebSearch;

  /// Question request fallback title
  ///
  /// In en, this message translates to:
  /// **'Agent requests input'**
  String get agentRequestsInput;

  /// Local placeholder thread title
  ///
  /// In en, this message translates to:
  /// **'New conversation'**
  String get agentDefaultThreadTitle;

  /// Quota window weeks
  ///
  /// In en, this message translates to:
  /// **'{count} weeks'**
  String agentUsageWindowWeeks(String count);

  /// Quota window days
  ///
  /// In en, this message translates to:
  /// **'{count} days'**
  String agentUsageWindowDays(String count);

  /// Quota window hours
  ///
  /// In en, this message translates to:
  /// **'{count} hours'**
  String agentUsageWindowHours(String count);

  /// Quota window hours and minutes
  ///
  /// In en, this message translates to:
  /// **'{hours} hours {minutes} minutes'**
  String agentUsageWindowHoursMinutes(String hours, String minutes);

  /// Quota window minutes
  ///
  /// In en, this message translates to:
  /// **'{count} minutes'**
  String agentUsageWindowMinutes(String count);

  /// Quota window one week
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get agentUsageWindowOneWeek;

  /// Quota window one day
  ///
  /// In en, this message translates to:
  /// **'1 day'**
  String get agentUsageWindowOneDay;

  /// Claude five-hour quota label
  ///
  /// In en, this message translates to:
  /// **'5h'**
  String get agentQuotaFiveHours;

  /// Claude weekly quota label
  ///
  /// In en, this message translates to:
  /// **'1 week'**
  String get agentQuotaOneWeek;

  /// Claude Sonnet weekly quota
  ///
  /// In en, this message translates to:
  /// **'Sonnet 1 week'**
  String get agentQuotaSonnetOneWeek;

  /// Claude Opus weekly quota
  ///
  /// In en, this message translates to:
  /// **'Opus 1 week'**
  String get agentQuotaOpusOneWeek;

  /// Claude Code quota limit name
  ///
  /// In en, this message translates to:
  /// **'Claude Code subscription quota'**
  String get agentClaudeCodeSubscriptionQuota;

  /// Thread list load failed
  ///
  /// In en, this message translates to:
  /// **'Could not load threads'**
  String get agentCouldNotLoadThreads;

  /// No enabled providers for thread list
  ///
  /// In en, this message translates to:
  /// **'No enabled Agent providers'**
  String get agentNoEnabledProviders;

  /// Claude initialize probe success
  ///
  /// In en, this message translates to:
  /// **'Claude Code initialize succeeded. The CLI and current auth path are available.'**
  String get mgmtClaudeInitializeSuccess;

  /// Claude initialize probe timeout
  ///
  /// In en, this message translates to:
  /// **'Claude Code initialize did not finish within 20 seconds.'**
  String get mgmtClaudeInitializeTimeout;

  /// Claude initialize probe failed
  ///
  /// In en, this message translates to:
  /// **'Claude Code initialize probe failed.'**
  String get mgmtClaudeInitializeFailed;

  /// CLI version detection failed
  ///
  /// In en, this message translates to:
  /// **'{name} version detection failed.'**
  String mgmtVersionDetectFailed(String name);

  /// Claude login evidence missing
  ///
  /// In en, this message translates to:
  /// **'Claude Code login evidence is unavailable'**
  String get mgmtClaudeLoginEvidenceUnavailable;

  /// Claude initialize process exited
  ///
  /// In en, this message translates to:
  /// **'The Claude Code process exited before initialize finished.'**
  String get mgmtClaudeInitializeProcessExited;

  /// Claude initialize rejected
  ///
  /// In en, this message translates to:
  /// **'Claude Code rejected the initialize request.'**
  String get mgmtClaudeInitializeRejected;

  /// Claude initialize invalid response
  ///
  /// In en, this message translates to:
  /// **'Claude Code returned an invalid initialize response.'**
  String get mgmtClaudeInitializeInvalidResponse;

  /// Claude initialize invalid stream
  ///
  /// In en, this message translates to:
  /// **'Claude Code returned invalid stream-json data.'**
  String get mgmtClaudeInitializeInvalidStream;

  /// Claude initialize transport failed
  ///
  /// In en, this message translates to:
  /// **'Claude Code initialize communication failed.'**
  String get mgmtClaudeInitializeCommunicationFailed;

  /// Claude.ai logged in
  ///
  /// In en, this message translates to:
  /// **'Signed in to Claude.ai'**
  String get mgmtClaudeAiLoggedIn;

  /// Claude.ai logged in with plan
  ///
  /// In en, this message translates to:
  /// **'Signed in to Claude.ai · {plan}'**
  String mgmtClaudeAiLoggedInAs(String plan);

  /// Provider not logged in
  ///
  /// In en, this message translates to:
  /// **'{name} is not signed in.'**
  String mgmtNotLoggedIn(String name);

  /// Grok login cache empty
  ///
  /// In en, this message translates to:
  /// **'The Grok login cache is empty.'**
  String get mgmtGrokLoginCacheEmpty;

  /// Grok ACP connection ok
  ///
  /// In en, this message translates to:
  /// **'Grok ACP connection is healthy'**
  String get mgmtGrokAcpOk;

  /// Grok ACP connection failed
  ///
  /// In en, this message translates to:
  /// **'Grok ACP connection failed.'**
  String get mgmtGrokAcpFailed;

  /// Grok latest version network hint
  ///
  /// In en, this message translates to:
  /// **'Check the network and detect again, or run grok update --check in a terminal.'**
  String get mgmtGrokLatestVersionNetworkHint;

  /// Codex app-server probe failed
  ///
  /// In en, this message translates to:
  /// **'Codex app-server connection failed.'**
  String get mgmtCodexAppServerFailed;

  /// Agent detection incomplete
  ///
  /// In en, this message translates to:
  /// **'Agent detection did not finish: {error}'**
  String mgmtDetectionIncomplete(String error);

  /// Agent detection progress
  ///
  /// In en, this message translates to:
  /// **'[{index}/{total}] {name}: {message}'**
  String mgmtDetectionProgress(
    String index,
    String total,
    String name,
    String message,
  );

  /// Usage session dir incomplete
  ///
  /// In en, this message translates to:
  /// **'The {name} session directory could not be fully enumerated. Readable data is shown.'**
  String usageSessionDirIncomplete(String name);

  /// Usage session files unreadable
  ///
  /// In en, this message translates to:
  /// **'{count} {name} session files could not be read. Other data is shown.'**
  String usageSessionFilesUnreadable(String count, String name);

  /// Usage history rows corrupt
  ///
  /// In en, this message translates to:
  /// **'{count} {name} history lines were corrupt and skipped.'**
  String usageHistoryRowsCorrupt(String count, String name);
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

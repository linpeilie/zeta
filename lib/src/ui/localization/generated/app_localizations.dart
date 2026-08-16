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

  /// Virtual scrollbar
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
  /// **'Continue recent work, or open a project to start.'**
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

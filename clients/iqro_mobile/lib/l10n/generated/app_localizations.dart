import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_ar.dart';
import 'app_localizations_en.dart';
import 'app_localizations_ru.dart';
import 'app_localizations_tr.dart';

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
    Locale('ar'),
    Locale('en'),
    Locale('ru'),
    Locale('tr'),
  ];

  /// No description provided for @appName.
  ///
  /// In en, this message translates to:
  /// **'IQRO'**
  String get appName;

  /// No description provided for @navHome.
  ///
  /// In en, this message translates to:
  /// **'Home'**
  String get navHome;

  /// No description provided for @navQuran.
  ///
  /// In en, this message translates to:
  /// **'Quran'**
  String get navQuran;

  /// No description provided for @navPlan.
  ///
  /// In en, this message translates to:
  /// **'Plan'**
  String get navPlan;

  /// No description provided for @navAudio.
  ///
  /// In en, this message translates to:
  /// **'Audio'**
  String get navAudio;

  /// No description provided for @navMore.
  ///
  /// In en, this message translates to:
  /// **'More'**
  String get navMore;

  /// No description provided for @back.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get back;

  /// No description provided for @open.
  ///
  /// In en, this message translates to:
  /// **'Open'**
  String get open;

  /// No description provided for @save.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get save;

  /// No description provided for @cancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get cancel;

  /// No description provided for @close.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get close;

  /// No description provided for @retry.
  ///
  /// In en, this message translates to:
  /// **'Try again'**
  String get retry;

  /// No description provided for @continueLabel.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get continueLabel;

  /// No description provided for @done.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get done;

  /// No description provided for @soon.
  ///
  /// In en, this message translates to:
  /// **'Soon'**
  String get soon;

  /// No description provided for @search.
  ///
  /// In en, this message translates to:
  /// **'Search'**
  String get search;

  /// No description provided for @settings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settings;

  /// No description provided for @welcomeTitle.
  ///
  /// In en, this message translates to:
  /// **'A calmer daily practice'**
  String get welcomeTitle;

  /// No description provided for @welcomeBody.
  ///
  /// In en, this message translates to:
  /// **'Read, listen and keep your rhythm in one private, focused app.'**
  String get welcomeBody;

  /// No description provided for @chooseLanguage.
  ///
  /// In en, this message translates to:
  /// **'Choose language'**
  String get chooseLanguage;

  /// No description provided for @chooseGoal.
  ///
  /// In en, this message translates to:
  /// **'What would you like to focus on?'**
  String get chooseGoal;

  /// No description provided for @goalReading.
  ///
  /// In en, this message translates to:
  /// **'Daily reading'**
  String get goalReading;

  /// No description provided for @goalMemorization.
  ///
  /// In en, this message translates to:
  /// **'Memorization'**
  String get goalMemorization;

  /// No description provided for @goalPrayer.
  ///
  /// In en, this message translates to:
  /// **'Prayer support'**
  String get goalPrayer;

  /// No description provided for @goalDua.
  ///
  /// In en, this message translates to:
  /// **'Dua'**
  String get goalDua;

  /// No description provided for @dailyNorm.
  ///
  /// In en, this message translates to:
  /// **'Choose a comfortable daily norm'**
  String get dailyNorm;

  /// No description provided for @minutes.
  ///
  /// In en, this message translates to:
  /// **'minutes'**
  String get minutes;

  /// No description provided for @pages.
  ///
  /// In en, this message translates to:
  /// **'pages'**
  String get pages;

  /// No description provided for @ayahs.
  ///
  /// In en, this message translates to:
  /// **'ayahs'**
  String get ayahs;

  /// No description provided for @startAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Start privately'**
  String get startAsGuest;

  /// No description provided for @guestNote.
  ///
  /// In en, this message translates to:
  /// **'Your progress starts on this device. You can connect an account later.'**
  String get guestNote;

  /// No description provided for @greeting.
  ///
  /// In en, this message translates to:
  /// **'Assalamu alaikum'**
  String get greeting;

  /// No description provided for @continueReading.
  ///
  /// In en, this message translates to:
  /// **'Continue reading'**
  String get continueReading;

  /// No description provided for @read.
  ///
  /// In en, this message translates to:
  /// **'Read'**
  String get read;

  /// No description provided for @savedAutomatically.
  ///
  /// In en, this message translates to:
  /// **'Position saved automatically'**
  String get savedAutomatically;

  /// No description provided for @nextPrayer.
  ///
  /// In en, this message translates to:
  /// **'Next prayer'**
  String get nextPrayer;

  /// No description provided for @yourRhythm.
  ///
  /// In en, this message translates to:
  /// **'Your rhythm'**
  String get yourRhythm;

  /// No description provided for @today.
  ///
  /// In en, this message translates to:
  /// **'Today'**
  String get today;

  /// No description provided for @openPlan.
  ///
  /// In en, this message translates to:
  /// **'Open plan'**
  String get openPlan;

  /// No description provided for @calmPace.
  ///
  /// In en, this message translates to:
  /// **'A calm pace'**
  String get calmPace;

  /// No description provided for @afterPrayer.
  ///
  /// In en, this message translates to:
  /// **'After prayer'**
  String get afterPrayer;

  /// No description provided for @memorization.
  ///
  /// In en, this message translates to:
  /// **'Memorization'**
  String get memorization;

  /// No description provided for @recentReciter.
  ///
  /// In en, this message translates to:
  /// **'Recent reciter'**
  String get recentReciter;

  /// No description provided for @duaOfDay.
  ///
  /// In en, this message translates to:
  /// **'Dua of the day'**
  String get duaOfDay;

  /// No description provided for @readingAsGuest.
  ///
  /// In en, this message translates to:
  /// **'Reading as guest'**
  String get readingAsGuest;

  /// No description provided for @guestSyncHint.
  ///
  /// In en, this message translates to:
  /// **'Sign in to continue on another device'**
  String get guestSyncHint;

  /// No description provided for @quranSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Madani Mushaf · Hafs'**
  String get quranSubtitle;

  /// No description provided for @alFatiha.
  ///
  /// In en, this message translates to:
  /// **'Al-Fatiha'**
  String get alFatiha;

  /// No description provided for @textMode.
  ///
  /// In en, this message translates to:
  /// **'Text'**
  String get textMode;

  /// No description provided for @mushafMode.
  ///
  /// In en, this message translates to:
  /// **'Mushaf'**
  String get mushafMode;

  /// No description provided for @selectedMushaf.
  ///
  /// In en, this message translates to:
  /// **'Selected Mushaf'**
  String get selectedMushaf;

  /// No description provided for @chooseMushaf.
  ///
  /// In en, this message translates to:
  /// **'Choose Mushaf'**
  String get chooseMushaf;

  /// No description provided for @mushafScanName.
  ///
  /// In en, this message translates to:
  /// **'Madani Mushaf'**
  String get mushafScanName;

  /// No description provided for @mushafScanDescription.
  ///
  /// In en, this message translates to:
  /// **'Original pages · Hafs'**
  String get mushafScanDescription;

  /// No description provided for @mushafTextDescription.
  ///
  /// In en, this message translates to:
  /// **'Crisp text adapted to your screen'**
  String get mushafTextDescription;

  /// No description provided for @mushafWebOnly.
  ///
  /// In en, this message translates to:
  /// **'This font is currently available in the web version only'**
  String get mushafWebOnly;

  /// No description provided for @mushafUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Temporarily unavailable from the source'**
  String get mushafUnavailable;

  /// No description provided for @mushafCachedDescription.
  ///
  /// In en, this message translates to:
  /// **'Downloaded on first open · then available offline'**
  String get mushafCachedDescription;

  /// No description provided for @mushafLoading.
  ///
  /// In en, this message translates to:
  /// **'Loading the page and official font…'**
  String get mushafLoading;

  /// No description provided for @mushafFontError.
  ///
  /// In en, this message translates to:
  /// **'The official font could not be opened. Try again while online.'**
  String get mushafFontError;

  /// No description provided for @mushafOfflineMissing.
  ///
  /// In en, this message translates to:
  /// **'This page has not been saved on this device yet. Connect to the internet and try again.'**
  String get mushafOfflineMissing;

  /// No description provided for @continueSaved.
  ///
  /// In en, this message translates to:
  /// **'Continue from saved position'**
  String get continueSaved;

  /// No description provided for @surahs.
  ///
  /// In en, this message translates to:
  /// **'Surahs'**
  String get surahs;

  /// No description provided for @juz.
  ///
  /// In en, this message translates to:
  /// **'Juz'**
  String get juz;

  /// No description provided for @hizb.
  ///
  /// In en, this message translates to:
  /// **'Hizb'**
  String get hizb;

  /// No description provided for @rubElHizb.
  ///
  /// In en, this message translates to:
  /// **'Rub al-hizb'**
  String get rubElHizb;

  /// No description provided for @page.
  ///
  /// In en, this message translates to:
  /// **'Page'**
  String get page;

  /// No description provided for @surah.
  ///
  /// In en, this message translates to:
  /// **'Surah'**
  String get surah;

  /// No description provided for @ayah.
  ///
  /// In en, this message translates to:
  /// **'Ayah'**
  String get ayah;

  /// No description provided for @quickJump.
  ///
  /// In en, this message translates to:
  /// **'Quick jump'**
  String get quickJump;

  /// No description provided for @navigation.
  ///
  /// In en, this message translates to:
  /// **'Navigation'**
  String get navigation;

  /// No description provided for @meccan.
  ///
  /// In en, this message translates to:
  /// **'Meccan'**
  String get meccan;

  /// No description provided for @medinan.
  ///
  /// In en, this message translates to:
  /// **'Medinan'**
  String get medinan;

  /// No description provided for @noQuranData.
  ///
  /// In en, this message translates to:
  /// **'Quran catalog is unavailable'**
  String get noQuranData;

  /// No description provided for @offlineUsingCache.
  ///
  /// In en, this message translates to:
  /// **'Offline — showing saved content'**
  String get offlineUsingCache;

  /// No description provided for @readerSettings.
  ///
  /// In en, this message translates to:
  /// **'Reading settings'**
  String get readerSettings;

  /// No description provided for @textAppearance.
  ///
  /// In en, this message translates to:
  /// **'Text appearance'**
  String get textAppearance;

  /// No description provided for @arabicTextSize.
  ///
  /// In en, this message translates to:
  /// **'Arabic text size'**
  String get arabicTextSize;

  /// No description provided for @lineSpacing.
  ///
  /// In en, this message translates to:
  /// **'Line spacing'**
  String get lineSpacing;

  /// No description provided for @ayahSpacing.
  ///
  /// In en, this message translates to:
  /// **'Spacing between ayahs'**
  String get ayahSpacing;

  /// No description provided for @focusMode.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get focusMode;

  /// No description provided for @focusModeDescription.
  ///
  /// In en, this message translates to:
  /// **'Hide the top bar and secondary hints'**
  String get focusModeDescription;

  /// No description provided for @exitFocusMode.
  ///
  /// In en, this message translates to:
  /// **'Exit focus mode'**
  String get exitFocusMode;

  /// No description provided for @translation.
  ///
  /// In en, this message translates to:
  /// **'Translation'**
  String get translation;

  /// No description provided for @tafsir.
  ///
  /// In en, this message translates to:
  /// **'Tafsir'**
  String get tafsir;

  /// No description provided for @loadOnDemand.
  ///
  /// In en, this message translates to:
  /// **'Load on demand'**
  String get loadOnDemand;

  /// No description provided for @translationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'No approved translation is connected for this locale yet.'**
  String get translationUnavailable;

  /// No description provided for @tafsirUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Tafsir is available only after an approved edition is selected.'**
  String get tafsirUnavailable;

  /// No description provided for @bookmarkAdded.
  ///
  /// In en, this message translates to:
  /// **'Added to favorites'**
  String get bookmarkAdded;

  /// No description provided for @bookmarkRemoved.
  ///
  /// In en, this message translates to:
  /// **'Bookmark removed'**
  String get bookmarkRemoved;

  /// No description provided for @listen.
  ///
  /// In en, this message translates to:
  /// **'Listen'**
  String get listen;

  /// No description provided for @tapForControls.
  ///
  /// In en, this message translates to:
  /// **'Tap to show controls'**
  String get tapForControls;

  /// No description provided for @zoom.
  ///
  /// In en, this message translates to:
  /// **'Zoom'**
  String get zoom;

  /// No description provided for @listenPage.
  ///
  /// In en, this message translates to:
  /// **'Listen to this page'**
  String get listenPage;

  /// No description provided for @tapAyahForDetails.
  ///
  /// In en, this message translates to:
  /// **'Tap an ayah for audio, translation and tafsir'**
  String get tapAyahForDetails;

  /// No description provided for @audioTitle.
  ///
  /// In en, this message translates to:
  /// **'Listen to the Quran'**
  String get audioTitle;

  /// No description provided for @chooseReciter.
  ///
  /// In en, this message translates to:
  /// **'Choose reciter'**
  String get chooseReciter;

  /// No description provided for @allReciters.
  ///
  /// In en, this message translates to:
  /// **'All reciters'**
  String get allReciters;

  /// No description provided for @recitationStyle.
  ///
  /// In en, this message translates to:
  /// **'Recitation style'**
  String get recitationStyle;

  /// No description provided for @chooseRecitationStyle.
  ///
  /// In en, this message translates to:
  /// **'Choose recitation style'**
  String get chooseRecitationStyle;

  /// No description provided for @styleMurattal.
  ///
  /// In en, this message translates to:
  /// **'Murattal'**
  String get styleMurattal;

  /// No description provided for @styleMujawwad.
  ///
  /// In en, this message translates to:
  /// **'Mujawwad'**
  String get styleMujawwad;

  /// No description provided for @styleMuallim.
  ///
  /// In en, this message translates to:
  /// **'Muallim'**
  String get styleMuallim;

  /// No description provided for @refreshReciters.
  ///
  /// In en, this message translates to:
  /// **'Refresh reciter catalog'**
  String get refreshReciters;

  /// No description provided for @recitersUpdated.
  ///
  /// In en, this message translates to:
  /// **'Reciter catalog updated'**
  String get recitersUpdated;

  /// No description provided for @recitersRefreshFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not refresh the catalog. Saved data is shown.'**
  String get recitersRefreshFailed;

  /// No description provided for @noAudio.
  ///
  /// In en, this message translates to:
  /// **'No playable audio is available'**
  String get noAudio;

  /// No description provided for @nowPlaying.
  ///
  /// In en, this message translates to:
  /// **'Now playing'**
  String get nowPlaying;

  /// No description provided for @play.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get play;

  /// No description provided for @pause.
  ///
  /// In en, this message translates to:
  /// **'Pause'**
  String get pause;

  /// No description provided for @previousSurah.
  ///
  /// In en, this message translates to:
  /// **'Previous surah'**
  String get previousSurah;

  /// No description provided for @nextSurah.
  ///
  /// In en, this message translates to:
  /// **'Next surah'**
  String get nextSurah;

  /// No description provided for @chooseSurah.
  ///
  /// In en, this message translates to:
  /// **'Choose surah'**
  String get chooseSurah;

  /// No description provided for @speed.
  ///
  /// In en, this message translates to:
  /// **'Speed'**
  String get speed;

  /// No description provided for @audioQuality.
  ///
  /// In en, this message translates to:
  /// **'Audio quality'**
  String get audioQuality;

  /// No description provided for @qualityAutomatic.
  ///
  /// In en, this message translates to:
  /// **'Automatic'**
  String get qualityAutomatic;

  /// No description provided for @qualityEconomy.
  ///
  /// In en, this message translates to:
  /// **'Data saver'**
  String get qualityEconomy;

  /// No description provided for @qualityStandard.
  ///
  /// In en, this message translates to:
  /// **'Standard'**
  String get qualityStandard;

  /// No description provided for @qualityHigh.
  ///
  /// In en, this message translates to:
  /// **'High'**
  String get qualityHigh;

  /// No description provided for @audioBitrate.
  ///
  /// In en, this message translates to:
  /// **'{bitrate} kbps'**
  String audioBitrate(int bitrate);

  /// No description provided for @range.
  ///
  /// In en, this message translates to:
  /// **'Range'**
  String get range;

  /// No description provided for @sleepTimer.
  ///
  /// In en, this message translates to:
  /// **'Sleep timer'**
  String get sleepTimer;

  /// No description provided for @repeat.
  ///
  /// In en, this message translates to:
  /// **'Repeat'**
  String get repeat;

  /// No description provided for @repeatOff.
  ///
  /// In en, this message translates to:
  /// **'Repeat off'**
  String get repeatOff;

  /// No description provided for @repeatOn.
  ///
  /// In en, this message translates to:
  /// **'Repeat on'**
  String get repeatOn;

  /// No description provided for @off.
  ///
  /// In en, this message translates to:
  /// **'Off'**
  String get off;

  /// No description provided for @backgroundPlayback.
  ///
  /// In en, this message translates to:
  /// **'Background and lock-screen controls'**
  String get backgroundPlayback;

  /// No description provided for @dailyPlan.
  ///
  /// In en, this message translates to:
  /// **'Daily plan'**
  String get dailyPlan;

  /// No description provided for @dailyGoal.
  ///
  /// In en, this message translates to:
  /// **'Daily goal'**
  String get dailyGoal;

  /// No description provided for @completed.
  ///
  /// In en, this message translates to:
  /// **'Completed'**
  String get completed;

  /// No description provided for @remaining.
  ///
  /// In en, this message translates to:
  /// **'Remaining'**
  String get remaining;

  /// No description provided for @history.
  ///
  /// In en, this message translates to:
  /// **'History'**
  String get history;

  /// No description provided for @manualEntry.
  ///
  /// In en, this message translates to:
  /// **'Add reading'**
  String get manualEntry;

  /// No description provided for @addPages.
  ///
  /// In en, this message translates to:
  /// **'Add pages'**
  String get addPages;

  /// No description provided for @afterPrayerPlan.
  ///
  /// In en, this message translates to:
  /// **'After-prayer plan'**
  String get afterPrayerPlan;

  /// No description provided for @prayer.
  ///
  /// In en, this message translates to:
  /// **'Prayer times'**
  String get prayer;

  /// No description provided for @calculationMethod.
  ///
  /// In en, this message translates to:
  /// **'Calculation method'**
  String get calculationMethod;

  /// No description provided for @prayerLocationPrivacy.
  ///
  /// In en, this message translates to:
  /// **'Your coordinates stay on this device and are never added to analytics.'**
  String get prayerLocationPrivacy;

  /// No description provided for @useMyLocation.
  ///
  /// In en, this message translates to:
  /// **'Use my location'**
  String get useMyLocation;

  /// No description provided for @locationDenied.
  ///
  /// In en, this message translates to:
  /// **'Location access is off. You can enable it in the device settings.'**
  String get locationDenied;

  /// No description provided for @locationServicesDisabled.
  ///
  /// In en, this message translates to:
  /// **'Location is turned off'**
  String get locationServicesDisabled;

  /// No description provided for @locationServicesDisabledBody.
  ///
  /// In en, this message translates to:
  /// **'Turn on location services, then return to IQRO to calculate prayer times automatically.'**
  String get locationServicesDisabledBody;

  /// No description provided for @locationPermissionRequired.
  ///
  /// In en, this message translates to:
  /// **'Location access is required'**
  String get locationPermissionRequired;

  /// No description provided for @locationPermissionRequiredBody.
  ///
  /// In en, this message translates to:
  /// **'Allow access once to calculate prayer times. Coordinates stay on this device.'**
  String get locationPermissionRequiredBody;

  /// No description provided for @locationUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Location could not be determined'**
  String get locationUnavailable;

  /// No description provided for @prayerCalculationFailed.
  ///
  /// In en, this message translates to:
  /// **'Prayer times could not be calculated. Check the calculation method and try again.'**
  String get prayerCalculationFailed;

  /// No description provided for @prayerUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Prayer times are not calculated yet'**
  String get prayerUnavailable;

  /// No description provided for @fajr.
  ///
  /// In en, this message translates to:
  /// **'Fajr'**
  String get fajr;

  /// No description provided for @dhuhr.
  ///
  /// In en, this message translates to:
  /// **'Dhuhr'**
  String get dhuhr;

  /// No description provided for @asr.
  ///
  /// In en, this message translates to:
  /// **'Asr'**
  String get asr;

  /// No description provided for @maghrib.
  ///
  /// In en, this message translates to:
  /// **'Maghrib'**
  String get maghrib;

  /// No description provided for @isha.
  ///
  /// In en, this message translates to:
  /// **'Isha'**
  String get isha;

  /// No description provided for @memorizationTitle.
  ///
  /// In en, this message translates to:
  /// **'Memorization practice'**
  String get memorizationTitle;

  /// No description provided for @memorizationCreatePlan.
  ///
  /// In en, this message translates to:
  /// **'Create a memorization plan'**
  String get memorizationCreatePlan;

  /// No description provided for @memorizationEditPlan.
  ///
  /// In en, this message translates to:
  /// **'Edit plan'**
  String get memorizationEditPlan;

  /// No description provided for @memorizationPlanDescription.
  ///
  /// In en, this message translates to:
  /// **'Choose a surah, ayah range, daily target, pause, and recitation. The plan syncs with your account.'**
  String get memorizationPlanDescription;

  /// No description provided for @memorizationDailyRepetitions.
  ///
  /// In en, this message translates to:
  /// **'Repetitions per day'**
  String get memorizationDailyRepetitions;

  /// No description provided for @memorizationPauseSeconds.
  ///
  /// In en, this message translates to:
  /// **'Pause between repetitions, sec.'**
  String get memorizationPauseSeconds;

  /// No description provided for @memorizationReciter.
  ///
  /// In en, this message translates to:
  /// **'Reciter for practice'**
  String get memorizationReciter;

  /// No description provided for @memorizationWithoutAudio.
  ///
  /// In en, this message translates to:
  /// **'Without audio'**
  String get memorizationWithoutAudio;

  /// No description provided for @memorizationSavePlan.
  ///
  /// In en, this message translates to:
  /// **'Save plan'**
  String get memorizationSavePlan;

  /// No description provided for @memorizationPlanSaved.
  ///
  /// In en, this message translates to:
  /// **'Memorization plan saved'**
  String get memorizationPlanSaved;

  /// No description provided for @memorizationRangeInvalid.
  ///
  /// In en, this message translates to:
  /// **'Check the start and end of the ayah range'**
  String get memorizationRangeInvalid;

  /// No description provided for @memorizationTodayCompleted.
  ///
  /// In en, this message translates to:
  /// **'Today\'s target is complete'**
  String get memorizationTodayCompleted;

  /// No description provided for @memorizationRemaining.
  ///
  /// In en, this message translates to:
  /// **'Repetitions remaining'**
  String get memorizationRemaining;

  /// No description provided for @repetitionTarget.
  ///
  /// In en, this message translates to:
  /// **'Repetitions'**
  String get repetitionTarget;

  /// No description provided for @again.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get again;

  /// No description provided for @hard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get hard;

  /// No description provided for @good.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get good;

  /// No description provided for @resetToday.
  ///
  /// In en, this message translates to:
  /// **'Reset today'**
  String get resetToday;

  /// No description provided for @resetConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear only today\'s repetition result?'**
  String get resetConfirm;

  /// No description provided for @dua.
  ///
  /// In en, this message translates to:
  /// **'Dua'**
  String get dua;

  /// No description provided for @duaSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Duas and adhkar from traceable sources'**
  String get duaSubtitle;

  /// No description provided for @duaCount.
  ///
  /// In en, this message translates to:
  /// **'{count} duas'**
  String duaCount(int count);

  /// No description provided for @noDuaCategories.
  ///
  /// In en, this message translates to:
  /// **'No dua categories are available yet'**
  String get noDuaCategories;

  /// No description provided for @noDuaFound.
  ///
  /// In en, this message translates to:
  /// **'No matching dua found'**
  String get noDuaFound;

  /// No description provided for @duaSearchMinCharacters.
  ///
  /// In en, this message translates to:
  /// **'Enter at least 2 characters to search'**
  String get duaSearchMinCharacters;

  /// No description provided for @duaUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This dua is unavailable'**
  String get duaUnavailable;

  /// No description provided for @cachedDuaWarning.
  ///
  /// In en, this message translates to:
  /// **'A saved copy is shown. Audio becomes available after the current version is verified.'**
  String get cachedDuaWarning;

  /// No description provided for @duaAudio.
  ///
  /// In en, this message translates to:
  /// **'Dua audio'**
  String get duaAudio;

  /// No description provided for @duaAudioStreaming.
  ///
  /// In en, this message translates to:
  /// **'An internet connection is required to listen'**
  String get duaAudioStreaming;

  /// No description provided for @duaAudioFailed.
  ///
  /// In en, this message translates to:
  /// **'The audio could not be played'**
  String get duaAudioFailed;

  /// No description provided for @duaPractice.
  ///
  /// In en, this message translates to:
  /// **'Repetition practice'**
  String get duaPractice;

  /// No description provided for @duaPracticeHint.
  ///
  /// In en, this message translates to:
  /// **'Tap after each reading. This counter stays on this screen only.'**
  String get duaPracticeHint;

  /// No description provided for @reset.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get reset;

  /// No description provided for @sourceAndVerification.
  ///
  /// In en, this message translates to:
  /// **'Source and verification'**
  String get sourceAndVerification;

  /// No description provided for @sourceDeclared.
  ///
  /// In en, this message translates to:
  /// **'Source provided'**
  String get sourceDeclared;

  /// No description provided for @sourceUnavailable.
  ///
  /// In en, this message translates to:
  /// **'Source details unavailable'**
  String get sourceUnavailable;

  /// No description provided for @editoriallyVerified.
  ///
  /// In en, this message translates to:
  /// **'Editorially verified'**
  String get editoriallyVerified;

  /// No description provided for @copyText.
  ///
  /// In en, this message translates to:
  /// **'Copy text'**
  String get copyText;

  /// No description provided for @textCopied.
  ///
  /// In en, this message translates to:
  /// **'Text copied'**
  String get textCopied;

  /// No description provided for @shareDua.
  ///
  /// In en, this message translates to:
  /// **'Share dua'**
  String get shareDua;

  /// No description provided for @duaReader.
  ///
  /// In en, this message translates to:
  /// **'Reader'**
  String get duaReader;

  /// No description provided for @practiceStage.
  ///
  /// In en, this message translates to:
  /// **'Stage'**
  String get practiceStage;

  /// No description provided for @markRepetition.
  ///
  /// In en, this message translates to:
  /// **'Count repetition'**
  String get markRepetition;

  /// No description provided for @author.
  ///
  /// In en, this message translates to:
  /// **'Author'**
  String get author;

  /// No description provided for @translator.
  ///
  /// In en, this message translates to:
  /// **'Translator'**
  String get translator;

  /// No description provided for @reviewer.
  ///
  /// In en, this message translates to:
  /// **'Reviewer'**
  String get reviewer;

  /// No description provided for @sourceVersion.
  ///
  /// In en, this message translates to:
  /// **'Source version'**
  String get sourceVersion;

  /// No description provided for @sourceReference.
  ///
  /// In en, this message translates to:
  /// **'Reference'**
  String get sourceReference;

  /// No description provided for @grade.
  ///
  /// In en, this message translates to:
  /// **'Grade'**
  String get grade;

  /// No description provided for @rights.
  ///
  /// In en, this message translates to:
  /// **'Usage terms'**
  String get rights;

  /// No description provided for @favorites.
  ///
  /// In en, this message translates to:
  /// **'Favorites'**
  String get favorites;

  /// No description provided for @all.
  ///
  /// In en, this message translates to:
  /// **'All'**
  String get all;

  /// No description provided for @emptyFavorites.
  ///
  /// In en, this message translates to:
  /// **'Save an ayah or dua to find it here.'**
  String get emptyFavorites;

  /// No description provided for @account.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get account;

  /// No description provided for @personalProfile.
  ///
  /// In en, this message translates to:
  /// **'Personal profile'**
  String get personalProfile;

  /// No description provided for @signIn.
  ///
  /// In en, this message translates to:
  /// **'Sign in'**
  String get signIn;

  /// No description provided for @email.
  ///
  /// In en, this message translates to:
  /// **'Email'**
  String get email;

  /// No description provided for @verificationCode.
  ///
  /// In en, this message translates to:
  /// **'Verification code'**
  String get verificationCode;

  /// No description provided for @sendCode.
  ///
  /// In en, this message translates to:
  /// **'Send code'**
  String get sendCode;

  /// No description provided for @verify.
  ///
  /// In en, this message translates to:
  /// **'Verify'**
  String get verify;

  /// No description provided for @signOut.
  ///
  /// In en, this message translates to:
  /// **'Sign out'**
  String get signOut;

  /// No description provided for @devices.
  ///
  /// In en, this message translates to:
  /// **'Devices'**
  String get devices;

  /// No description provided for @syncNow.
  ///
  /// In en, this message translates to:
  /// **'Sync now'**
  String get syncNow;

  /// No description provided for @syncHint.
  ///
  /// In en, this message translates to:
  /// **'Send local changes and receive updates from your other devices.'**
  String get syncHint;

  /// No description provided for @language.
  ///
  /// In en, this message translates to:
  /// **'Language'**
  String get language;

  /// No description provided for @theme.
  ///
  /// In en, this message translates to:
  /// **'Theme'**
  String get theme;

  /// No description provided for @systemTheme.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get systemTheme;

  /// No description provided for @lightTheme.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get lightTheme;

  /// No description provided for @darkTheme.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get darkTheme;

  /// No description provided for @shareApp.
  ///
  /// In en, this message translates to:
  /// **'Share IQRO'**
  String get shareApp;

  /// No description provided for @shareTitle.
  ///
  /// In en, this message translates to:
  /// **'Invite someone to IQRO'**
  String get shareTitle;

  /// No description provided for @shareBody.
  ///
  /// In en, this message translates to:
  /// **'Share a calm way to read and listen to the Quran.'**
  String get shareBody;

  /// No description provided for @shareButton.
  ///
  /// In en, this message translates to:
  /// **'Share app'**
  String get shareButton;

  /// No description provided for @copyLink.
  ///
  /// In en, this message translates to:
  /// **'Copy link'**
  String get copyLink;

  /// No description provided for @linkCopied.
  ///
  /// In en, this message translates to:
  /// **'Link copied'**
  String get linkCopied;

  /// No description provided for @referralSummary.
  ///
  /// In en, this message translates to:
  /// **'Your invitations'**
  String get referralSummary;

  /// No description provided for @invited.
  ///
  /// In en, this message translates to:
  /// **'Invited'**
  String get invited;

  /// No description provided for @qualified.
  ///
  /// In en, this message translates to:
  /// **'Qualified'**
  String get qualified;

  /// No description provided for @rewardBalance.
  ///
  /// In en, this message translates to:
  /// **'Reward balance'**
  String get rewardBalance;

  /// No description provided for @referralRequiresAccount.
  ///
  /// In en, this message translates to:
  /// **'Personal referral links become available after email verification.'**
  String get referralRequiresAccount;

  /// No description provided for @remoteCopy.
  ///
  /// In en, this message translates to:
  /// **'Campaign text is managed by IQRO'**
  String get remoteCopy;

  /// No description provided for @bundledCopy.
  ///
  /// In en, this message translates to:
  /// **'Using the built-in sharing text'**
  String get bundledCopy;

  /// No description provided for @networkError.
  ///
  /// In en, this message translates to:
  /// **'Could not reach IQRO'**
  String get networkError;

  /// No description provided for @sessionExpired.
  ///
  /// In en, this message translates to:
  /// **'Your session expired. Offline work is safe.'**
  String get sessionExpired;

  /// No description provided for @syncConflict.
  ///
  /// In en, this message translates to:
  /// **'Your other device has newer progress.'**
  String get syncConflict;

  /// No description provided for @loading.
  ///
  /// In en, this message translates to:
  /// **'Loading…'**
  String get loading;

  /// No description provided for @offline.
  ///
  /// In en, this message translates to:
  /// **'Offline'**
  String get offline;

  /// No description provided for @offlineMushaf.
  ///
  /// In en, this message translates to:
  /// **'Offline Mushaf'**
  String get offlineMushaf;

  /// No description provided for @offlineMushafDescription.
  ///
  /// In en, this message translates to:
  /// **'Download every page and ayah map. Files are verified before activation.'**
  String get offlineMushafDescription;

  /// No description provided for @downloadForOffline.
  ///
  /// In en, this message translates to:
  /// **'Download'**
  String get downloadForOffline;

  /// No description provided for @mushafDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading Mushaf'**
  String get mushafDownloading;

  /// No description provided for @mushafAvailableOffline.
  ///
  /// In en, this message translates to:
  /// **'Available offline'**
  String get mushafAvailableOffline;

  /// No description provided for @mushafDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'The download stopped. You can resume from the saved point.'**
  String get mushafDownloadFailed;

  /// No description provided for @resumeDownload.
  ///
  /// In en, this message translates to:
  /// **'Resume'**
  String get resumeDownload;

  /// No description provided for @offlineAudio.
  ///
  /// In en, this message translates to:
  /// **'Offline audio'**
  String get offlineAudio;

  /// No description provided for @offlineAudioDescription.
  ///
  /// In en, this message translates to:
  /// **'Download all 114 surahs for this recitation. Every file is verified before activation.'**
  String get offlineAudioDescription;

  /// No description provided for @audioDownloading.
  ///
  /// In en, this message translates to:
  /// **'Downloading audio'**
  String get audioDownloading;

  /// No description provided for @audioAvailableOffline.
  ///
  /// In en, this message translates to:
  /// **'Audio available offline'**
  String get audioAvailableOffline;

  /// No description provided for @audioDownloadFailed.
  ///
  /// In en, this message translates to:
  /// **'The audio download stopped. You can resume from the saved point.'**
  String get audioDownloadFailed;

  /// No description provided for @audioOfflineUnavailable.
  ///
  /// In en, this message translates to:
  /// **'This recording is not licensed for offline download.'**
  String get audioOfflineUnavailable;

  /// No description provided for @offlineStorage.
  ///
  /// In en, this message translates to:
  /// **'Offline storage'**
  String get offlineStorage;

  /// No description provided for @offlineStorageSettingsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Downloaded Mushaf pages and audio'**
  String get offlineStorageSettingsSubtitle;

  /// No description provided for @offlineStorageUsed.
  ///
  /// In en, this message translates to:
  /// **'Used offline: {size}'**
  String offlineStorageUsed(String size);

  /// No description provided for @offlineStorageDescription.
  ///
  /// In en, this message translates to:
  /// **'Only files downloaded by the app are shown here. Nothing is removed automatically.'**
  String get offlineStorageDescription;

  /// No description provided for @offlineStorageQuota.
  ///
  /// In en, this message translates to:
  /// **'App limit: {size}'**
  String offlineStorageQuota(String size);

  /// No description provided for @offlineStorageQuotaExceeded.
  ///
  /// In en, this message translates to:
  /// **'This package does not fit within the offline storage limit. Delete an unneeded package first.'**
  String get offlineStorageQuotaExceeded;

  /// No description provided for @downloadOfflineConfirmation.
  ///
  /// In en, this message translates to:
  /// **'The complete package will use about {size}. Start downloading?'**
  String downloadOfflineConfirmation(String size);

  /// No description provided for @downloadedContent.
  ///
  /// In en, this message translates to:
  /// **'Downloaded content'**
  String get downloadedContent;

  /// No description provided for @noOfflinePackages.
  ///
  /// In en, this message translates to:
  /// **'No offline packages have been downloaded yet.'**
  String get noOfflinePackages;

  /// No description provided for @storageReadFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not read offline storage'**
  String get storageReadFailed;

  /// No description provided for @tryAgain.
  ///
  /// In en, this message translates to:
  /// **'Please try again.'**
  String get tryAgain;

  /// No description provided for @refresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get refresh;

  /// No description provided for @deleteOfflinePackage.
  ///
  /// In en, this message translates to:
  /// **'Delete offline package'**
  String get deleteOfflinePackage;

  /// No description provided for @deleteOfflinePackageConfirmation.
  ///
  /// In en, this message translates to:
  /// **'Delete “{name}” ({size}) from this device? You will need to download it again for offline use.'**
  String deleteOfflinePackageConfirmation(String name, String size);

  /// No description provided for @deletePlayingAudioConfirmation.
  ///
  /// In en, this message translates to:
  /// **'“{name}” is playing now. Stop the player and delete its offline package ({size}) from this device?'**
  String deletePlayingAudioConfirmation(String name, String size);

  /// No description provided for @offlinePackageDeleted.
  ///
  /// In en, this message translates to:
  /// **'Offline package deleted'**
  String get offlinePackageDeleted;

  /// No description provided for @offlinePackageDeleteFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not delete the offline package'**
  String get offlinePackageDeleteFailed;

  /// No description provided for @packageTotalSize.
  ///
  /// In en, this message translates to:
  /// **'full size {size}'**
  String packageTotalSize(String size);

  /// No description provided for @completeMushafPages.
  ///
  /// In en, this message translates to:
  /// **'Complete Mushaf pages'**
  String get completeMushafPages;

  /// No description provided for @completeRecitation.
  ///
  /// In en, this message translates to:
  /// **'Complete Quran recitation'**
  String get completeRecitation;

  /// No description provided for @downloadInProgress.
  ///
  /// In en, this message translates to:
  /// **'Download in progress'**
  String get downloadInProgress;

  /// No description provided for @downloadFailed.
  ///
  /// In en, this message translates to:
  /// **'Download interrupted'**
  String get downloadFailed;

  /// No description provided for @notReady.
  ///
  /// In en, this message translates to:
  /// **'Not ready'**
  String get notReady;

  /// No description provided for @availableOffline.
  ///
  /// In en, this message translates to:
  /// **'Available offline'**
  String get availableOffline;

  /// No description provided for @moreTools.
  ///
  /// In en, this message translates to:
  /// **'Practice and tools'**
  String get moreTools;

  /// No description provided for @books.
  ///
  /// In en, this message translates to:
  /// **'Books'**
  String get books;

  /// No description provided for @quizzes.
  ///
  /// In en, this message translates to:
  /// **'Quizzes'**
  String get quizzes;

  /// No description provided for @support.
  ///
  /// In en, this message translates to:
  /// **'Support'**
  String get support;

  /// No description provided for @privacy.
  ///
  /// In en, this message translates to:
  /// **'Privacy'**
  String get privacy;

  /// No description provided for @reminders.
  ///
  /// In en, this message translates to:
  /// **'Reminders'**
  String get reminders;

  /// No description provided for @remindersSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Prayer and Quran review'**
  String get remindersSubtitle;

  /// No description provided for @notificationAccess.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications'**
  String get notificationAccess;

  /// No description provided for @notificationAccessBody.
  ///
  /// In en, this message translates to:
  /// **'IQRO will remind you at the selected time, even when the app is closed.'**
  String get notificationAccessBody;

  /// No description provided for @allowNotifications.
  ///
  /// In en, this message translates to:
  /// **'Allow notifications'**
  String get allowNotifications;

  /// No description provided for @notificationDenied.
  ///
  /// In en, this message translates to:
  /// **'Notifications are disabled in device settings.'**
  String get notificationDenied;

  /// No description provided for @approximateDelivery.
  ///
  /// In en, this message translates to:
  /// **'The system may deliver reminders with a small delay to save battery.'**
  String get approximateDelivery;

  /// No description provided for @prayerReminders.
  ///
  /// In en, this message translates to:
  /// **'Prayer reminders'**
  String get prayerReminders;

  /// No description provided for @prayerReminderSetup.
  ///
  /// In en, this message translates to:
  /// **'First choose a calculation method and set your location in Prayer times.'**
  String get prayerReminderSetup;

  /// No description provided for @quranReviewReminders.
  ///
  /// In en, this message translates to:
  /// **'Quran review'**
  String get quranReviewReminders;

  /// No description provided for @addReminder.
  ///
  /// In en, this message translates to:
  /// **'Add reminder'**
  String get addReminder;

  /// No description provided for @noReminders.
  ///
  /// In en, this message translates to:
  /// **'No review reminders yet.'**
  String get noReminders;

  /// No description provided for @reviewReminder.
  ///
  /// In en, this message translates to:
  /// **'Verse review'**
  String get reviewReminder;

  /// No description provided for @reminderTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get reminderTime;

  /// No description provided for @reminderDays.
  ///
  /// In en, this message translates to:
  /// **'Days'**
  String get reminderDays;

  /// No description provided for @everyDay.
  ///
  /// In en, this message translates to:
  /// **'Every day'**
  String get everyDay;

  /// No description provided for @signal.
  ///
  /// In en, this message translates to:
  /// **'Alert'**
  String get signal;

  /// No description provided for @sound.
  ///
  /// In en, this message translates to:
  /// **'Sound'**
  String get sound;

  /// No description provided for @vibration.
  ///
  /// In en, this message translates to:
  /// **'Vibration'**
  String get vibration;

  /// No description provided for @silent.
  ///
  /// In en, this message translates to:
  /// **'Silent'**
  String get silent;

  /// No description provided for @timezone.
  ///
  /// In en, this message translates to:
  /// **'Time zone'**
  String get timezone;

  /// No description provided for @deviceTimezone.
  ///
  /// In en, this message translates to:
  /// **'Use device time zone'**
  String get deviceTimezone;

  /// No description provided for @fixedTimezone.
  ///
  /// In en, this message translates to:
  /// **'Fixed'**
  String get fixedTimezone;

  /// No description provided for @timezoneName.
  ///
  /// In en, this message translates to:
  /// **'IANA time zone'**
  String get timezoneName;

  /// No description provided for @startAyah.
  ///
  /// In en, this message translates to:
  /// **'First verse'**
  String get startAyah;

  /// No description provided for @endAyah.
  ///
  /// In en, this message translates to:
  /// **'Last verse'**
  String get endAyah;

  /// No description provided for @delete.
  ///
  /// In en, this message translates to:
  /// **'Delete'**
  String get delete;

  /// No description provided for @deleteReminderConfirm.
  ///
  /// In en, this message translates to:
  /// **'Delete this reminder?'**
  String get deleteReminderConfirm;

  /// No description provided for @reminderSaved.
  ///
  /// In en, this message translates to:
  /// **'Reminder saved'**
  String get reminderSaved;

  /// No description provided for @mondayShort.
  ///
  /// In en, this message translates to:
  /// **'Mon'**
  String get mondayShort;

  /// No description provided for @tuesdayShort.
  ///
  /// In en, this message translates to:
  /// **'Tue'**
  String get tuesdayShort;

  /// No description provided for @wednesdayShort.
  ///
  /// In en, this message translates to:
  /// **'Wed'**
  String get wednesdayShort;

  /// No description provided for @thursdayShort.
  ///
  /// In en, this message translates to:
  /// **'Thu'**
  String get thursdayShort;

  /// No description provided for @fridayShort.
  ///
  /// In en, this message translates to:
  /// **'Fri'**
  String get fridayShort;

  /// No description provided for @saturdayShort.
  ///
  /// In en, this message translates to:
  /// **'Sat'**
  String get saturdayShort;

  /// No description provided for @sundayShort.
  ///
  /// In en, this message translates to:
  /// **'Sun'**
  String get sundayShort;
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
      <String>['ar', 'en', 'ru', 'tr'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'ar':
      return AppLocalizationsAr();
    case 'en':
      return AppLocalizationsEn();
    case 'ru':
      return AppLocalizationsRu();
    case 'tr':
      return AppLocalizationsTr();
  }

  throw FlutterError(
    'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String homePrayerIn(String time) {
    return 'In $time';
  }

  @override
  String get homeSavedHint => 'Saved ayahs and duas';

  @override
  String get homeDownloads => 'Downloads';

  @override
  String get bookmarks => 'Bookmarks';

  @override
  String get emptyBookmarks =>
      'No bookmarks yet. Save an ayah using the bookmark icon in the reader.';

  @override
  String get bookmarksLoadError => 'Could not load bookmarks';

  @override
  String get mushafFitWidth => 'Fit width';

  @override
  String get mushafFitPage => 'Whole page';

  @override
  String get checkMushafUpdates => 'Check for updates';

  @override
  String get mushafUpToDate => 'Your downloaded Mushaf is up to date';

  @override
  String get updateMushaf => 'Update Mushaf';

  @override
  String updateMushafConfirmation(String size) {
    return 'Download the updated pages ($size). Your current Mushaf stays available until the new package has been downloaded and verified.';
  }

  @override
  String get hijriCalendar => 'Hijri calendar';

  @override
  String get hijriMethod => 'Umm al-Qura · offline';

  @override
  String get hijriDisclaimer =>
      'Calculated dates may differ from local moon sighting. Confirm Ramadan and Eid with your local community. The Islamic day begins at sunset on the preceding civil day.';

  @override
  String get hijriAdjustment => 'Date adjustment';

  @override
  String get hijriAdjustmentHint =>
      'Match your local community\'s calendar. The adjustment applies throughout the calendar.';

  @override
  String get hijriSources => 'References and sources';

  @override
  String get hijriNoEvents => 'No special markers for this day.';

  @override
  String get hijriUnavailable =>
      'Date outside the supported calendar (1937–2077).';

  @override
  String get hijriToday => 'Today in Hijri';

  @override
  String get hijriCivilDate => 'Civil date';

  @override
  String get hijriSunsetDate => 'Date adjusted for local Maghrib';

  @override
  String get hijriCivilHint =>
      'Without today\'s Maghrib time, the civil day\'s date is shown.';

  @override
  String get hijriYearSuffix => 'AH';

  @override
  String get hijriEventHint =>
      'These are reference markers, not a personal religious ruling. Eid is not marked as a voluntary fasting day; pilgrims have separate guidance for Arafah.';

  @override
  String get appLicenses => 'Component licenses';

  @override
  String hijriMonthName(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'Muharram',
      'm2': 'Safar',
      'm3': 'Rabi al-Awwal',
      'm4': 'Rabi al-Thani',
      'm5': 'Jumada al-Ula',
      'm6': 'Jumada al-Thani',
      'm7': 'Rajab',
      'm8': 'Shaban',
      'm9': 'Ramadan',
      'm10': 'Shawwal',
      'm11': 'Dhul-Qadah',
      'm12': 'Dhul-Hijjah',
      'other': 'Hijri',
    });
    return '$_temp0';
  }

  @override
  String hijriEventName(String event) {
    String _temp0 = intl.Intl.selectLogic(event, {
      'ramadan': 'Ramadan',
      'eidFitr': 'Eid al-Fitr',
      'arafah': 'Day of Arafah',
      'eidAdha': 'Eid al-Adha',
      'tashriq': 'Days of Tashriq',
      'ashura': 'Ashura',
      'whiteDays': 'White days · 13–15',
      'lastTenNights': 'Last ten nights of Ramadan',
      'other': 'Notable date',
    });
    return '$_temp0';
  }

  @override
  String get appName => 'IQRO';

  @override
  String get navHome => 'Home';

  @override
  String get navQuran => 'Quran';

  @override
  String get navPlan => 'Plan';

  @override
  String get navAudio => 'Audio';

  @override
  String get navMore => 'More';

  @override
  String get back => 'Back';

  @override
  String get open => 'Open';

  @override
  String get save => 'Save';

  @override
  String get cancel => 'Cancel';

  @override
  String get close => 'Close';

  @override
  String get retry => 'Try again';

  @override
  String get continueLabel => 'Continue';

  @override
  String get done => 'Done';

  @override
  String get soon => 'Soon';

  @override
  String get search => 'Search';

  @override
  String get settings => 'Settings';

  @override
  String get welcomeTitle => 'A calmer daily practice';

  @override
  String get welcomeBody =>
      'Read, listen and keep your rhythm in one private, focused app.';

  @override
  String get chooseLanguage => 'Choose language';

  @override
  String get chooseGoal => 'What would you like to focus on?';

  @override
  String get goalReading => 'Daily reading';

  @override
  String get goalMemorization => 'Memorization';

  @override
  String get goalPrayer => 'Prayer support';

  @override
  String get goalDua => 'Dua';

  @override
  String get dailyNorm => 'Choose a comfortable daily norm';

  @override
  String get minutes => 'minutes';

  @override
  String get pages => 'pages';

  @override
  String get ayahs => 'ayahs';

  @override
  String get startAsGuest => 'Start privately';

  @override
  String get guestNote =>
      'Your progress starts on this device. You can connect an account later.';

  @override
  String get greeting => 'Assalamu alaikum';

  @override
  String get continueReading => 'Continue reading';

  @override
  String get read => 'Read';

  @override
  String get savedAutomatically => 'Position saved automatically';

  @override
  String get nextPrayer => 'Next prayer';

  @override
  String get yourRhythm => 'Your rhythm';

  @override
  String get today => 'Today';

  @override
  String get openPlan => 'Open plan';

  @override
  String get calmPace => 'A calm pace';

  @override
  String get afterPrayer => 'After prayer';

  @override
  String get memorization => 'Memorization';

  @override
  String get recentReciter => 'Recent reciter';

  @override
  String get duaOfDay => 'Dua of the day';

  @override
  String get readingAsGuest => 'Reading as guest';

  @override
  String get guestSyncHint => 'Sign in to continue on another device';

  @override
  String get quranSubtitle => 'Madani Mushaf · Hafs';

  @override
  String get alFatiha => 'Al-Fatiha';

  @override
  String get textMode => 'Text';

  @override
  String get mushafMode => 'Mushaf';

  @override
  String get selectedMushaf => 'Selected Mushaf';

  @override
  String get chooseMushaf => 'Choose Mushaf';

  @override
  String get mushafCatalogEmpty => 'Mushafs have not been loaded yet';

  @override
  String get mushafPreviewDescription => 'Hafs · IQRO layout · preview';

  @override
  String get mushafPublishedDescription => 'Hafs · online and offline reading';

  @override
  String get mushafTextDescription => 'Crisp text adapted to your screen';

  @override
  String get mushafWebOnly =>
      'This font is currently available in the web version only';

  @override
  String get mushafUnavailable => 'Temporarily unavailable from the source';

  @override
  String get mushafCachedDescription =>
      'Downloaded on first open · then available offline';

  @override
  String get mushafLoading => 'Loading the page and official font…';

  @override
  String get mushafFontError =>
      'The official font could not be opened. Try again while online.';

  @override
  String get mushafOfflineMissing =>
      'This page has not been saved on this device yet. Connect to the internet and try again.';

  @override
  String get continueSaved => 'Continue from saved position';

  @override
  String get surahs => 'Surahs';

  @override
  String get juz => 'Juz';

  @override
  String get hizb => 'Hizb';

  @override
  String get rubElHizb => 'Rub al-hizb';

  @override
  String get page => 'Page';

  @override
  String get surah => 'Surah';

  @override
  String get ayah => 'Ayah';

  @override
  String get quickJump => 'Quick jump';

  @override
  String get navigation => 'Navigation';

  @override
  String get meccan => 'Meccan';

  @override
  String get medinan => 'Medinan';

  @override
  String get noQuranData => 'Quran catalog is unavailable';

  @override
  String get offlineUsingCache => 'Offline — showing saved content';

  @override
  String get readerSettings => 'Reading settings';

  @override
  String get textAppearance => 'Text appearance';

  @override
  String get arabicTextSize => 'Arabic text size';

  @override
  String get lineSpacing => 'Line spacing';

  @override
  String get ayahSpacing => 'Spacing between ayahs';

  @override
  String get focusMode => 'Focus mode';

  @override
  String get focusModeDescription => 'Hide the top bar and secondary hints';

  @override
  String get exitFocusMode => 'Exit focus mode';

  @override
  String get translation => 'Translation';

  @override
  String get tafsir => 'Tafsir';

  @override
  String get loadOnDemand => 'Load on demand';

  @override
  String get translationUnavailable =>
      'No approved translation is connected for this locale yet.';

  @override
  String get tafsirUnavailable =>
      'Tafsir is available only after an approved edition is selected.';

  @override
  String get bookmarkAdded => 'Added to favorites';

  @override
  String get bookmarkRemoved => 'Bookmark removed';

  @override
  String get listen => 'Listen';

  @override
  String get tapForControls => 'Tap for player and controls';

  @override
  String get zoom => 'Zoom';

  @override
  String get listenPage => 'Listen to this page';

  @override
  String get tapAyahForDetails => 'Hold an ayah for translation and tafsir';

  @override
  String get audioTitle => 'Listen to the Quran';

  @override
  String get chooseReciter => 'Choose reciter';

  @override
  String get allReciters => 'All reciters';

  @override
  String get recitationStyle => 'Recitation style';

  @override
  String get chooseRecitationStyle => 'Choose recitation style';

  @override
  String get styleMurattal => 'Murattal';

  @override
  String get styleMujawwad => 'Mujawwad';

  @override
  String get styleMuallim => 'Muallim';

  @override
  String get refreshReciters => 'Refresh reciter catalog';

  @override
  String get recitersUpdated => 'Reciter catalog updated';

  @override
  String get recitersRefreshFailed =>
      'Could not refresh the catalog. Saved data is shown.';

  @override
  String get noAudio => 'No playable audio is available';

  @override
  String get nowPlaying => 'Now playing';

  @override
  String get play => 'Play';

  @override
  String get pause => 'Pause';

  @override
  String get previousSurah => 'Previous surah';

  @override
  String get nextSurah => 'Next surah';

  @override
  String get chooseSurah => 'Choose surah';

  @override
  String get speed => 'Speed';

  @override
  String get audioQuality => 'Audio quality';

  @override
  String get qualityAutomatic => 'Automatic';

  @override
  String get qualityEconomy => 'Data saver';

  @override
  String get qualityStandard => 'Standard';

  @override
  String get qualityHigh => 'High';

  @override
  String audioBitrate(int bitrate) {
    return '$bitrate kbps';
  }

  @override
  String get range => 'Range';

  @override
  String get sleepTimer => 'Sleep timer';

  @override
  String get repeat => 'Repeat';

  @override
  String get repeatOff => 'Repeat off';

  @override
  String get repeatOn => 'Repeat on';

  @override
  String get off => 'Off';

  @override
  String get backgroundPlayback => 'Background and lock-screen controls';

  @override
  String get dailyPlan => 'Daily plan';

  @override
  String get dailyGoal => 'Daily goal';

  @override
  String get completed => 'Completed';

  @override
  String get remaining => 'Remaining';

  @override
  String get history => 'History';

  @override
  String get manualEntry => 'Add reading';

  @override
  String get addPages => 'Add pages';

  @override
  String get afterPrayerPlan => 'After-prayer plan';

  @override
  String get prayer => 'Prayer times';

  @override
  String get calculationMethod => 'Calculation method';

  @override
  String get prayerCalculationSettings => 'Prayer calculation settings';

  @override
  String get prayerSettingsDefault => 'Standard Asr · no manual adjustments';

  @override
  String get prayerAdjustedTimes => 'times adjusted';

  @override
  String get savedOnDevice => 'Saved on this device';

  @override
  String get prayerSettingsSyncPending =>
      'The settings work offline and will sync with your account when the network returns.';

  @override
  String get asrCalculation => 'Asr calculation';

  @override
  String get asrStandard => 'Standard';

  @override
  String get asrHanafi => 'Hanafi';

  @override
  String get asrStandardHint =>
      'Shadow factor 1, used by the Shafi\'i, Maliki and Hanbali schools.';

  @override
  String get asrHanafiHint => 'Shadow factor 2, used by the Hanafi school.';

  @override
  String get manualPrayerAdjustments => 'Manual time adjustments';

  @override
  String get manualPrayerAdjustmentsHint =>
      'Add or subtract minutes only when your trusted local timetable requires it.';

  @override
  String get advancedCalculationRules => 'Advanced rules';

  @override
  String get highLatitudeRule => 'High-latitude rule';

  @override
  String get polarResolution => 'Polar-circle handling';

  @override
  String get middleOfNight => 'Middle of the night';

  @override
  String get seventhOfNight => 'Seventh of the night';

  @override
  String get twilightAngle => 'Twilight angle';

  @override
  String get noPolarSubstitution => 'No substitution';

  @override
  String get nearestLatitude => 'Nearest latitude';

  @override
  String get nearestDay => 'Nearest day';

  @override
  String get sunrise => 'Sunrise';

  @override
  String get decrease => 'Decrease';

  @override
  String get increase => 'Increase';

  @override
  String get currentLocation => 'Current location';

  @override
  String get locationNotSelected => 'Location not selected';

  @override
  String get cityFallbackHint => 'Use device location or choose a city';

  @override
  String get chooseCity => 'Choose city';

  @override
  String get chooseCityInstead => 'Choose a city instead';

  @override
  String get cityFallbackDescription =>
      'A city is a private on-device fallback when precise location is unavailable.';

  @override
  String get searchCity => 'Search city';

  @override
  String get cityNotFound => 'No matching city';

  @override
  String get qibla => 'Qibla';

  @override
  String get qiblaDirection => 'Qibla direction';

  @override
  String get fromGeographicNorth => 'from geographic north';

  @override
  String get qiblaNorthHint =>
      'This is a geographic bearing, not a live compass. Align the top of the phone with north before following the arrow.';

  @override
  String get prayerCalendar => 'Monthly prayer calendar';

  @override
  String get prayerCalendarHint =>
      'All daily times for the selected month, available offline';

  @override
  String get prayerCalendarUnavailable => 'Could not calculate this month';

  @override
  String get prayerCalendarNeedsLocation =>
      'Choose a location on the prayer screen first';

  @override
  String get previousMonth => 'Previous month';

  @override
  String get nextMonth => 'Next month';

  @override
  String get prayerWidget => 'Prayer times widget';

  @override
  String get prayerWidgetHint =>
      'The next prayer and all five times on your home screen, even offline';

  @override
  String get addPrayerWidget => 'Add widget';

  @override
  String get homeWidgetAlreadyAdded =>
      'Widget already added. Its data has been updated.';

  @override
  String get prayerWidgetPinRequested =>
      'Choose where to place the IQRO widget on your home screen';

  @override
  String get prayerWidgetManualAndroid =>
      'Touch and hold an empty area of the home screen, open Widgets, and choose IQRO.';

  @override
  String get prayerWidgetManualIos =>
      'Touch and hold the home screen, tap +, find IQRO, and add the widget.';

  @override
  String get prayerWidgetNeedsLocation =>
      'Choose a location and calculate prayer times first';

  @override
  String get prayerLocationPrivacy =>
      'Your coordinates stay on this device and are never added to analytics.';

  @override
  String get useMyLocation => 'Use my location';

  @override
  String get locationDenied =>
      'Location access is off. You can enable it in the device settings.';

  @override
  String get locationServicesDisabled => 'Location is turned off';

  @override
  String get locationServicesDisabledBody =>
      'Turn on location services, then return to IQRO to calculate prayer times automatically.';

  @override
  String get locationPermissionRequired => 'Location access is required';

  @override
  String get locationPermissionRequiredBody =>
      'Allow access once to calculate prayer times. Coordinates stay on this device.';

  @override
  String get locationUnavailable => 'Location could not be determined';

  @override
  String get prayerCalculationFailed =>
      'Prayer times could not be calculated. Check the calculation method and try again.';

  @override
  String get prayerUnavailable => 'Prayer times are not calculated yet';

  @override
  String get fajr => 'Fajr';

  @override
  String get dhuhr => 'Dhuhr';

  @override
  String get asr => 'Asr';

  @override
  String get maghrib => 'Maghrib';

  @override
  String get isha => 'Isha';

  @override
  String get memorizationTitle => 'Memorization practice';

  @override
  String get memorizationCreatePlan => 'Create a memorization plan';

  @override
  String get memorizationEditPlan => 'Edit plan';

  @override
  String get memorizationPlanDescription =>
      'Choose a surah, ayah range, daily target, pause, and recitation. The plan syncs with your account.';

  @override
  String get memorizationDailyRepetitions => 'Repetitions per day';

  @override
  String get memorizationPauseSeconds => 'Pause between repetitions, sec.';

  @override
  String get memorizationReciter => 'Reciter for practice';

  @override
  String get memorizationWithoutAudio => 'Without audio';

  @override
  String get memorizationSavePlan => 'Save plan';

  @override
  String get memorizationPlanSaved => 'Memorization plan saved';

  @override
  String get memorizationRangeInvalid =>
      'Check the start and end of the ayah range';

  @override
  String get memorizationTodayCompleted => 'Today\'s target is complete';

  @override
  String get memorizationRemaining => 'Repetitions remaining';

  @override
  String get repetitionTarget => 'Repetitions';

  @override
  String get again => 'Again';

  @override
  String get hard => 'Hard';

  @override
  String get good => 'Good';

  @override
  String get resetToday => 'Reset today';

  @override
  String get resetConfirm => 'Clear only today\'s repetition result?';

  @override
  String get dua => 'Dua';

  @override
  String get duaSubtitle => 'Duas and adhkar from traceable sources';

  @override
  String duaCount(int count) {
    return '$count duas';
  }

  @override
  String get noDuaCategories => 'No dua categories are available yet';

  @override
  String get noDuaFound => 'No matching dua found';

  @override
  String get duaSearchMinCharacters => 'Enter at least 2 characters to search';

  @override
  String get duaUnavailable => 'This dua is unavailable';

  @override
  String get cachedDuaWarning =>
      'A saved copy is shown. Audio becomes available after the current version is verified.';

  @override
  String get duaAudio => 'Dua audio';

  @override
  String get duaAudioStreaming =>
      'An internet connection is required to listen';

  @override
  String get duaAudioFailed => 'The audio could not be played';

  @override
  String get duaPractice => 'Repetition practice';

  @override
  String get duaPracticeHint =>
      'Tap after each reading. This counter stays on this screen only.';

  @override
  String get reset => 'Reset';

  @override
  String get sourceAndVerification => 'Source and verification';

  @override
  String get sourceDeclared => 'Source provided';

  @override
  String get sourceUnavailable => 'Source details unavailable';

  @override
  String get editoriallyVerified => 'Editorially verified';

  @override
  String get copyText => 'Copy text';

  @override
  String get textCopied => 'Text copied';

  @override
  String get shareDua => 'Share dua';

  @override
  String get duaReader => 'Reader';

  @override
  String get practiceStage => 'Stage';

  @override
  String get markRepetition => 'Count repetition';

  @override
  String get author => 'Author';

  @override
  String get translator => 'Translator';

  @override
  String get reviewer => 'Reviewer';

  @override
  String get sourceVersion => 'Source version';

  @override
  String get sourceReference => 'Reference';

  @override
  String get grade => 'Grade';

  @override
  String get rights => 'Usage terms';

  @override
  String get favorites => 'Favorites';

  @override
  String get all => 'All';

  @override
  String get emptyFavorites => 'Save an ayah or dua to find it here.';

  @override
  String get account => 'Account';

  @override
  String get personalProfile => 'Personal profile';

  @override
  String get signIn => 'Sign in';

  @override
  String get email => 'Email';

  @override
  String get invalidEmail => 'Check the email format.';

  @override
  String get verificationCode => 'Verification code';

  @override
  String get sendCode => 'Send code';

  @override
  String get verify => 'Verify';

  @override
  String get signOut => 'Sign out';

  @override
  String get devices => 'Devices';

  @override
  String get currentDevice => 'This device';

  @override
  String get noDevices => 'No devices found.';

  @override
  String get feedbackTitle => 'Feedback and religious audit';

  @override
  String get feedbackAccountHint =>
      'Report an issue with text, audio, prayer times or the app.';

  @override
  String get feedbackSignInRequired => 'Sign in to send a request';

  @override
  String get feedbackDescription =>
      'Report inaccuracies in text, timings, or prayer calculations to the religious editorial team.';

  @override
  String get feedbackCreate => 'Create request';

  @override
  String get feedbackCategory => 'Request category';

  @override
  String get feedbackSubject => 'Subject';

  @override
  String get feedbackSubjectPlaceholder => 'Brief description';

  @override
  String get feedbackMessage => 'Message';

  @override
  String get feedbackMessagePlaceholder =>
      'Detailed description of the question or issue…';

  @override
  String get feedbackSend => 'Send request';

  @override
  String get feedbackNone => 'No active requests.';

  @override
  String feedbackTicket(String id) {
    return 'Request $id';
  }

  @override
  String feedbackTeam(String team) {
    return 'Team: $team';
  }

  @override
  String get feedbackNoMessages => 'No messages yet.';

  @override
  String get feedbackAddMessage => 'Add a message';

  @override
  String get feedbackReplyPlaceholder => 'Your reply to editorial or support';

  @override
  String get feedbackSendMessage => 'Send message';

  @override
  String get feedbackReopen => 'Reopen';

  @override
  String get feedbackCloseTicket => 'Close request';

  @override
  String get feedbackCloseConfirmation =>
      'Close this request? You can reopen it later.';

  @override
  String get feedbackNoFurtherActions =>
      'No more messages can be sent for this request.';

  @override
  String get feedbackRequiredFields => 'Enter a subject and message.';

  @override
  String get feedbackRateLimited => 'Too many requests. Try again later.';

  @override
  String get feedbackActionError =>
      'Could not complete this request action. Try again later.';

  @override
  String get feedbackCategoryReligious => 'Religious content';

  @override
  String get feedbackCategoryLayout => 'Mushaf page or layout';

  @override
  String get feedbackCategoryAudio => 'Audio, timing or reciter';

  @override
  String get feedbackCategoryAdvertisement => 'Advertisement';

  @override
  String get feedbackCategoryTechnical => 'Technical problem';

  @override
  String get feedbackCategoryAccount => 'Account or synchronization';

  @override
  String get feedbackCategoryDonation => 'Donation or external link';

  @override
  String get feedbackCategoryAccessibility => 'Accessibility or localization';

  @override
  String get feedbackCategoryGeneral => 'General suggestion';

  @override
  String get feedbackCategoryOther => 'Other';

  @override
  String get feedbackStatusNew => 'New';

  @override
  String get feedbackStatusTriaged => 'Triaged';

  @override
  String get feedbackStatusProgress => 'In progress';

  @override
  String get feedbackStatusWaiting => 'Waiting for you';

  @override
  String get feedbackStatusResolved => 'Resolved';

  @override
  String get feedbackStatusRejected => 'Rejected';

  @override
  String get feedbackStatusDuplicate => 'Duplicate';

  @override
  String get feedbackStatusClosed => 'Closed';

  @override
  String get feedbackSupport => 'Support';

  @override
  String get feedbackYou => 'You';

  @override
  String get feedbackSystem => 'System';

  @override
  String get signOutConfirmation => 'Sign out of this device?';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncHint =>
      'Send local changes and receive updates from your other devices.';

  @override
  String get language => 'Language';

  @override
  String get theme => 'Theme';

  @override
  String get systemTheme => 'System';

  @override
  String get lightTheme => 'Light';

  @override
  String get darkTheme => 'Dark';

  @override
  String get shareApp => 'Share IQRO';

  @override
  String get shareTitle => 'Invite someone to IQRO';

  @override
  String get shareBody => 'Share a calm way to read and listen to the Quran.';

  @override
  String get shareButton => 'Share app';

  @override
  String get copyLink => 'Copy link';

  @override
  String get linkCopied => 'Link copied';

  @override
  String get referralSummary => 'Your invitations';

  @override
  String get invited => 'Invited';

  @override
  String get qualified => 'Qualified';

  @override
  String get rewardBalance => 'Reward balance';

  @override
  String get referralRequiresAccount =>
      'Personal referral links become available after email verification.';

  @override
  String get remoteCopy => 'Campaign text is managed by IQRO';

  @override
  String get bundledCopy => 'Using the built-in sharing text';

  @override
  String get networkError => 'Could not reach IQRO';

  @override
  String get sessionExpired => 'Your session expired. Offline work is safe.';

  @override
  String get syncConflict => 'Your other device has newer progress.';

  @override
  String get loading => 'Loading…';

  @override
  String get offline => 'Offline';

  @override
  String get offlineMushaf => 'Offline Mushaf';

  @override
  String get offlineMushafDescription =>
      'Download every page and ayah map. Files are verified before activation.';

  @override
  String get downloadForOffline => 'Download';

  @override
  String get mushafDownloading => 'Downloading Mushaf';

  @override
  String get mushafAvailableOffline => 'Available offline';

  @override
  String get mushafDownloadFailed =>
      'The download stopped. You can resume from the saved point.';

  @override
  String get resumeDownload => 'Resume';

  @override
  String get offlineAudio => 'Offline audio';

  @override
  String get offlineAudioDescription =>
      'Download all 114 surahs for this recitation. Every file is verified before activation.';

  @override
  String get audioDownloading => 'Downloading audio';

  @override
  String get audioAvailableOffline => 'Audio available offline';

  @override
  String get audioDownloadFailed =>
      'The audio download stopped. You can resume from the saved point.';

  @override
  String get audioOfflineUnavailable =>
      'This recording is not licensed for offline download.';

  @override
  String get offlineStorage => 'Offline storage';

  @override
  String get offlineStorageSettingsSubtitle =>
      'Downloaded Mushaf pages and audio';

  @override
  String offlineStorageUsed(String size) {
    return 'Used offline: $size';
  }

  @override
  String get offlineStorageDescription =>
      'Only files downloaded by the app are shown here. Nothing is removed automatically.';

  @override
  String offlineStorageQuota(String size) {
    return 'App limit: $size';
  }

  @override
  String get offlineStorageQuotaExceeded =>
      'This package does not fit within the offline storage limit. Delete an unneeded package first.';

  @override
  String downloadOfflineConfirmation(String size) {
    return 'The complete package will use about $size. Start downloading?';
  }

  @override
  String get downloadedContent => 'Downloaded content';

  @override
  String get noOfflinePackages =>
      'No offline packages have been downloaded yet.';

  @override
  String get storageReadFailed => 'Could not read offline storage';

  @override
  String get tryAgain => 'Please try again.';

  @override
  String get refresh => 'Refresh';

  @override
  String get deleteOfflinePackage => 'Delete offline package';

  @override
  String deleteOfflinePackageConfirmation(String name, String size) {
    return 'Delete “$name” ($size) from this device? You will need to download it again for offline use.';
  }

  @override
  String deletePlayingAudioConfirmation(String name, String size) {
    return '“$name” is playing now. Stop the player and delete its offline package ($size) from this device?';
  }

  @override
  String get offlinePackageDeleted => 'Offline package deleted';

  @override
  String get offlinePackageDeleteFailed =>
      'Could not delete the offline package';

  @override
  String packageTotalSize(String size) {
    return 'full size $size';
  }

  @override
  String get completeMushafPages => 'Complete Mushaf pages';

  @override
  String get completeRecitation => 'Complete Quran recitation';

  @override
  String get downloadInProgress => 'Download in progress';

  @override
  String get downloadFailed => 'Download interrupted';

  @override
  String get notReady => 'Not ready';

  @override
  String get availableOffline => 'Available offline';

  @override
  String get moreTools => 'Practice and tools';

  @override
  String get books => 'Books';

  @override
  String get quizzes => 'Quizzes';

  @override
  String get support => 'Support';

  @override
  String get privacy => 'Privacy';

  @override
  String get reminders => 'Reminders';

  @override
  String get remindersSubtitle => 'Prayer and Quran review';

  @override
  String get notificationAccess => 'Allow notifications';

  @override
  String get notificationAccessBody =>
      'IQRO will remind you at the selected time, even when the app is closed.';

  @override
  String get allowNotifications => 'Allow notifications';

  @override
  String get notificationDenied =>
      'Notifications are disabled in device settings.';

  @override
  String get approximateDelivery =>
      'The system may deliver reminders with a small delay to save battery.';

  @override
  String get prayerReminders => 'Prayer reminders';

  @override
  String get prayerReminderSetup =>
      'First choose a calculation method and set your location in Prayer times.';

  @override
  String get quranReviewReminders => 'Quran review';

  @override
  String get addReminder => 'Add reminder';

  @override
  String get noReminders => 'No review reminders yet.';

  @override
  String get reviewReminder => 'Verse review';

  @override
  String get reminderTime => 'Time';

  @override
  String get reminderDays => 'Days';

  @override
  String get everyDay => 'Every day';

  @override
  String get signal => 'Alert';

  @override
  String get sound => 'Sound';

  @override
  String get vibration => 'Vibration';

  @override
  String get silent => 'Silent';

  @override
  String get timezone => 'Time zone';

  @override
  String get deviceTimezone => 'Use device time zone';

  @override
  String get fixedTimezone => 'Fixed';

  @override
  String get timezoneName => 'IANA time zone';

  @override
  String get startAyah => 'First verse';

  @override
  String get endAyah => 'Last verse';

  @override
  String get delete => 'Delete';

  @override
  String get deleteReminderConfirm => 'Delete this reminder?';

  @override
  String get reminderSaved => 'Reminder saved';

  @override
  String get mondayShort => 'Mon';

  @override
  String get tuesdayShort => 'Tue';

  @override
  String get wednesdayShort => 'Wed';

  @override
  String get thursdayShort => 'Thu';

  @override
  String get fridayShort => 'Fri';

  @override
  String get saturdayShort => 'Sat';

  @override
  String get sundayShort => 'Sun';

  @override
  String get readerHaptics => 'Page-turn vibration';

  @override
  String get readerHapticsHint =>
      'A short pulse when the Mushaf page changes. Android touch feedback must also be enabled.';

  @override
  String get mushafPageCaching =>
      'Pages load as you read. Opened pages and their fonts are saved on this device and remain available offline.';

  @override
  String get planCreditedToday => 'Credited today';

  @override
  String get planGoalLabel => 'Daily target';

  @override
  String get planEditGoal => 'Change target';

  @override
  String get planGoalReached => 'Daily target reached';

  @override
  String planRemainingAmount(String amount) {
    return 'Left to reach your target: $amount';
  }

  @override
  String planGoalAmount(String amount) {
    return 'Target: $amount';
  }

  @override
  String planCreditedAmount(String amount) {
    return 'Credited: $amount';
  }

  @override
  String get planManualEntry => 'Add reading manually';

  @override
  String get planManualHelp =>
      'Add reading that has not already been counted. This increases today’s progress; it does not change your target.';

  @override
  String get planHowCounted => 'How progress is counted';

  @override
  String get planPagesHelp =>
      'Turning to the next page in the reader adds a page automatically. Manual entries also count. Turning pages does not confirm that you have read them.';

  @override
  String get planMinutesHelp =>
      'Active time in the reader is counted automatically. Minutes added manually also count.';

  @override
  String get planAyahsHelp =>
      'Sequential progress through ayahs in the reader is counted automatically. Ayahs added manually also count.';

  @override
  String get planDailyHelp =>
      'Progress is counted separately for each day. Changing your target does not reset it; previous days stay in your history.';

  @override
  String get planResetHelp =>
      'Use − to undo pages marked after prayer. This screen cannot reset all of today’s progress.';

  @override
  String get planPrayerTitle => 'After-prayer reading';

  @override
  String get planPrayerSummary =>
      'Pages you marked today. These are completed entries, not a target.';

  @override
  String get planEditPrayer => 'Edit today’s entries';

  @override
  String get planPrayerInstructions =>
      'Mark pages read after each prayer. + adds one page, − removes one. Zero means no pages are marked.';

  @override
  String planRemovePage(String prayer) {
    return 'Remove one page: $prayer';
  }

  @override
  String planAddPage(String prayer) {
    return 'Add one page: $prayer';
  }

  @override
  String get planUnavailable =>
      'The plan could not be updated. Saved progress is shown; changes will be available after a successful refresh.';

  @override
  String get planGoalHint =>
      'Choose your daily target in minutes, pages or ayahs. This sets a target; it does not record completed reading.';

  @override
  String planBestStreak(String streak) {
    return 'Best streak: $streak';
  }

  @override
  String planActiveTime(String amount) {
    return 'Active reading: $amount';
  }

  @override
  String planPages(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString pages',
      one: '$countString page',
    );
    return '$_temp0';
  }

  @override
  String planMinutes(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString minutes',
      one: '$countString minute',
    );
    return '$_temp0';
  }

  @override
  String planAyahs(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString ayahs',
      one: '$countString ayah',
    );
    return '$_temp0';
  }

  @override
  String planStreak(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString days in a row',
      one: '$countString day in a row',
    );
    return '$_temp0';
  }

  @override
  String get planSummaryTitle => 'Progress summary';

  @override
  String planSummaryRange(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days days',
      one: '$days day',
    );
    return 'Last $_temp0';
  }

  @override
  String get planReadingDays => 'reading days';

  @override
  String get planCompletedDays => 'targets met';

  @override
  String get planPartialDays => 'partial days';

  @override
  String get planCalendarTitle => 'Progress calendar';

  @override
  String get planCalendarHint =>
      'Choose a day to see its target, reading and after-prayer marks.';

  @override
  String get planCalendarEmpty => 'There is no data for this period.';

  @override
  String get planSelectedDay => 'Selected day';

  @override
  String get planRelatedTools => 'Related sections';

  @override
  String get planHistoryEmpty => 'No reading records for this period.';

  @override
  String planPrayerCount(num count) {
    return 'After-prayer marks: $count';
  }

  @override
  String planAutomaticSessions(num count) {
    return 'Automatic sessions: $count';
  }

  @override
  String get planManualRecord => 'Added manually';

  @override
  String get planEditEntry => 'Edit entry';

  @override
  String get planDeleteEntry => 'Delete entry';

  @override
  String get planDeleteEntryTitle => 'Delete entry?';

  @override
  String get planDeleteEntryConfirm =>
      'This manual entry will be deleted and progress recalculated.';

  @override
  String get planReadingAmount => 'Amount';

  @override
  String get planReadingDate => 'Reading date';

  @override
  String get planStateNoGoal => 'No target';

  @override
  String get planStatePending => 'Today';

  @override
  String get planStateMissed => 'Missed';

  @override
  String get planStatePartial => 'Partial';

  @override
  String get planStateCompleted => 'Completed';

  @override
  String planDays(num count) {
    return '$count days';
  }
}

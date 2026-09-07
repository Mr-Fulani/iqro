// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String get hijriCalendar => 'التقويم الهجري';

  @override
  String get hijriMethod => 'أم القرى · دون إنترنت';

  @override
  String get hijriDisclaimer =>
      'قد تختلف التواريخ الحسابية عن رؤية الهلال المحلية. تحقّق من بداية رمضان والعيدين لدى الجهات المعتمدة في بلدك. يبدأ اليوم الهجري عند غروب شمس اليوم المدني السابق.';

  @override
  String get hijriAdjustment => 'تصحيح التاريخ';

  @override
  String get hijriAdjustmentHint =>
      'اضبط التاريخ وفق التقويم المعتمد محلياً. يسري التصحيح على التقويم كله.';

  @override
  String get hijriSources => 'المراجع والمصادر';

  @override
  String get hijriNoEvents => 'لا توجد علامات خاصة لهذا اليوم.';

  @override
  String get hijriUnavailable =>
      'التاريخ خارج نطاق التقويم المدعوم (١٩٣٧–٢٠٧٧).';

  @override
  String get hijriToday => 'اليوم هجرياً';

  @override
  String get hijriCivilDate => 'التاريخ المدني';

  @override
  String get hijriSunsetDate => 'التاريخ وفق المغرب المحلي';

  @override
  String get hijriCivilHint =>
      'عند غياب وقت المغرب لليوم يُعرض تاريخ اليوم المدني.';

  @override
  String get hijriYearSuffix => 'هـ';

  @override
  String get hijriEventHint =>
      'هذه علامات مرجعية وليست فتوى شخصية. لا تُعرض أيام العيد كأيام صيام تطوع، وللحجاج أحكام خاصة بيوم عرفة.';

  @override
  String get appLicenses => 'تراخيص المكونات';

  @override
  String hijriMonthName(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'محرم',
      'm2': 'صفر',
      'm3': 'ربيع الأول',
      'm4': 'ربيع الآخر',
      'm5': 'جمادى الأولى',
      'm6': 'جمادى الآخرة',
      'm7': 'رجب',
      'm8': 'شعبان',
      'm9': 'رمضان',
      'm10': 'شوال',
      'm11': 'ذو القعدة',
      'm12': 'ذو الحجة',
      'other': 'هجري',
    });
    return '$_temp0';
  }

  @override
  String hijriEventName(String event) {
    String _temp0 = intl.Intl.selectLogic(event, {
      'ramadan': 'رمضان',
      'eidFitr': 'عيد الفطر',
      'arafah': 'يوم عرفة',
      'eidAdha': 'عيد الأضحى',
      'tashriq': 'أيام التشريق',
      'ashura': 'عاشوراء',
      'whiteDays': 'الأيام البيض · ١٣–١٥',
      'lastTenNights': 'العشر الأواخر من رمضان',
      'other': 'تاريخ مميز',
    });
    return '$_temp0';
  }

  @override
  String get appName => 'إقرأ';

  @override
  String get navHome => 'الرئيسية';

  @override
  String get navQuran => 'القرآن';

  @override
  String get navPlan => 'الخطة';

  @override
  String get navAudio => 'الصوت';

  @override
  String get navMore => 'المزيد';

  @override
  String get back => 'رجوع';

  @override
  String get open => 'فتح';

  @override
  String get save => 'حفظ';

  @override
  String get cancel => 'إلغاء';

  @override
  String get close => 'إغلاق';

  @override
  String get retry => 'إعادة المحاولة';

  @override
  String get continueLabel => 'متابعة';

  @override
  String get done => 'تم';

  @override
  String get soon => 'قريبًا';

  @override
  String get search => 'بحث';

  @override
  String get settings => 'الإعدادات';

  @override
  String get welcomeTitle => 'ورد يومي بهدوء';

  @override
  String get welcomeBody =>
      'اقرأ واستمع وحافظ على إيقاعك في تطبيق واحد خاص ومركّز.';

  @override
  String get chooseLanguage => 'اختر اللغة';

  @override
  String get chooseGoal => 'ما الذي تريد التركيز عليه؟';

  @override
  String get goalReading => 'القراءة اليومية';

  @override
  String get goalMemorization => 'الحفظ';

  @override
  String get goalPrayer => 'مواقيت الصلاة';

  @override
  String get goalDua => 'الدعاء';

  @override
  String get dailyNorm => 'اختر وردًا يوميًا مناسبًا';

  @override
  String get minutes => 'دقائق';

  @override
  String get pages => 'صفحات';

  @override
  String get ayahs => 'آيات';

  @override
  String get startAsGuest => 'ابدأ بخصوصية';

  @override
  String get guestNote =>
      'يبدأ حفظ تقدمك على هذا الجهاز، ويمكنك ربط حساب لاحقًا.';

  @override
  String get greeting => 'السلام عليكم';

  @override
  String get continueReading => 'متابعة القراءة';

  @override
  String get read => 'اقرأ';

  @override
  String get savedAutomatically => 'تم حفظ موضعك تلقائيًا';

  @override
  String get nextPrayer => 'الصلاة التالية';

  @override
  String get yourRhythm => 'إيقاعك';

  @override
  String get today => 'اليوم';

  @override
  String get openPlan => 'فتح الخطة';

  @override
  String get calmPace => 'وتيرة هادئة';

  @override
  String get afterPrayer => 'بعد الصلاة';

  @override
  String get memorization => 'الحفظ';

  @override
  String get recentReciter => 'القارئ الأخير';

  @override
  String get duaOfDay => 'دعاء اليوم';

  @override
  String get readingAsGuest => 'تقرأ كضيف';

  @override
  String get guestSyncHint => 'سجّل الدخول للمتابعة على جهاز آخر';

  @override
  String get quranSubtitle => 'مصحف المدينة · حفص';

  @override
  String get alFatiha => 'الفاتحة';

  @override
  String get textMode => 'النص';

  @override
  String get mushafMode => 'المصحف';

  @override
  String get selectedMushaf => 'المصحف المختار';

  @override
  String get chooseMushaf => 'اختر المصحف';

  @override
  String get mushafScanName => 'مصحف المدينة';

  @override
  String get mushafScanDescription => 'صفحات أصلية · حفص';

  @override
  String get mushafPreviewDescription => 'حفص · تنسيق IQRO · نسخة تجريبية';

  @override
  String get mushafTextDescription => 'نص واضح متكيف مع الشاشة';

  @override
  String get mushafWebOnly => 'هذا الخط متاح حاليًا في نسخة الويب فقط';

  @override
  String get mushafUnavailable => 'هذا الخيار غير متاح مؤقتًا من المصدر';

  @override
  String get mushafCachedDescription =>
      'يُحمّل عند الفتح أول مرة · ثم يتاح دون اتصال';

  @override
  String get mushafLoading => 'جارٍ تحميل الصفحة والخط الرسمي…';

  @override
  String get mushafFontError =>
      'تعذر فتح الخط الرسمي. حاول مرة أخرى عند الاتصال بالإنترنت.';

  @override
  String get mushafOfflineMissing =>
      'لم تُحفظ هذه الصفحة على الجهاز بعد. اتصل بالإنترنت وحاول مرة أخرى.';

  @override
  String get continueSaved => 'متابعة من الموضع المحفوظ';

  @override
  String get surahs => 'السور';

  @override
  String get juz => 'الجزء';

  @override
  String get hizb => 'الحزب';

  @override
  String get rubElHizb => 'ربع الحزب';

  @override
  String get page => 'الصفحة';

  @override
  String get surah => 'السورة';

  @override
  String get ayah => 'الآية';

  @override
  String get quickJump => 'انتقال سريع';

  @override
  String get navigation => 'التنقل';

  @override
  String get meccan => 'مكية';

  @override
  String get medinan => 'مدنية';

  @override
  String get noQuranData => 'فهرس القرآن غير متاح';

  @override
  String get offlineUsingCache => 'غير متصل — نعرض المحتوى المحفوظ';

  @override
  String get readerSettings => 'إعدادات القراءة';

  @override
  String get textAppearance => 'تنسيق النص';

  @override
  String get arabicTextSize => 'حجم النص العربي';

  @override
  String get lineSpacing => 'تباعد الأسطر';

  @override
  String get ayahSpacing => 'المسافة بين الآيات';

  @override
  String get focusMode => 'وضع التركيز';

  @override
  String get focusModeDescription => 'إخفاء الشريط العلوي والتلميحات الإضافية';

  @override
  String get exitFocusMode => 'الخروج من وضع التركيز';

  @override
  String get translation => 'الترجمة';

  @override
  String get tafsir => 'التفسير';

  @override
  String get loadOnDemand => 'التحميل عند الطلب';

  @override
  String get translationUnavailable =>
      'لا توجد ترجمة معتمدة متصلة لهذه اللغة بعد.';

  @override
  String get tafsirUnavailable => 'يتاح التفسير بعد اختيار نسخة معتمدة.';

  @override
  String get bookmarkAdded => 'أُضيف إلى المفضلة';

  @override
  String get bookmarkRemoved => 'تمت إزالة العلامة';

  @override
  String get listen => 'استمع';

  @override
  String get tapForControls => 'اضغط لإظهار المشغّل والأدوات';

  @override
  String get zoom => 'التكبير';

  @override
  String get listenPage => 'استمع إلى الصفحة الحالية';

  @override
  String get tapAyahForDetails => 'اضغط مطولًا على الآية للترجمة والتفسير';

  @override
  String get audioTitle => 'استمع إلى القرآن';

  @override
  String get chooseReciter => 'اختر القارئ';

  @override
  String get allReciters => 'جميع القراء';

  @override
  String get recitationStyle => 'نمط التلاوة';

  @override
  String get chooseRecitationStyle => 'اختر نمط التلاوة';

  @override
  String get styleMurattal => 'مرتل';

  @override
  String get styleMujawwad => 'مجود';

  @override
  String get styleMuallim => 'معلّم';

  @override
  String get refreshReciters => 'تحديث قائمة القراء';

  @override
  String get recitersUpdated => 'تم تحديث قائمة القراء';

  @override
  String get recitersRefreshFailed =>
      'تعذر تحديث القائمة. يتم عرض البيانات المحفوظة.';

  @override
  String get noAudio => 'لا يوجد تسجيل صوتي متاح';

  @override
  String get nowPlaying => 'يُشغّل الآن';

  @override
  String get play => 'تشغيل';

  @override
  String get pause => 'إيقاف مؤقت';

  @override
  String get previousSurah => 'السورة السابقة';

  @override
  String get nextSurah => 'السورة التالية';

  @override
  String get chooseSurah => 'اختر السورة';

  @override
  String get speed => 'السرعة';

  @override
  String get audioQuality => 'جودة الصوت';

  @override
  String get qualityAutomatic => 'تلقائي';

  @override
  String get qualityEconomy => 'توفير البيانات';

  @override
  String get qualityStandard => 'قياسية';

  @override
  String get qualityHigh => 'عالية';

  @override
  String audioBitrate(int bitrate) {
    return '$bitrate كيلوبت/ث';
  }

  @override
  String get range => 'النطاق';

  @override
  String get sleepTimer => 'مؤقت النوم';

  @override
  String get repeat => 'التكرار';

  @override
  String get repeatOff => 'التكرار متوقف';

  @override
  String get repeatOn => 'التكرار مفعّل';

  @override
  String get off => 'متوقف';

  @override
  String get backgroundPlayback => 'التشغيل في الخلفية وأدوات شاشة القفل';

  @override
  String get dailyPlan => 'خطة اليوم';

  @override
  String get dailyGoal => 'الهدف اليومي';

  @override
  String get completed => 'تم';

  @override
  String get remaining => 'المتبقي';

  @override
  String get history => 'السجل';

  @override
  String get manualEntry => 'إضافة قراءة';

  @override
  String get addPages => 'إضافة صفحات';

  @override
  String get afterPrayerPlan => 'خطة ما بعد الصلاة';

  @override
  String get prayer => 'مواقيت الصلاة';

  @override
  String get calculationMethod => 'طريقة الحساب';

  @override
  String get prayerCalculationSettings => 'إعدادات حساب الصلاة';

  @override
  String get prayerSettingsDefault => 'العصر القياسي · بلا تعديلات يدوية';

  @override
  String get prayerAdjustedTimes => 'أوقات معدّلة';

  @override
  String get savedOnDevice => 'تم الحفظ على هذا الجهاز';

  @override
  String get prayerSettingsSyncPending =>
      'تعمل الإعدادات دون اتصال وستتم مزامنتها مع حسابك عند عودة الشبكة.';

  @override
  String get asrCalculation => 'حساب العصر';

  @override
  String get asrStandard => 'قياسي';

  @override
  String get asrHanafi => 'حنفي';

  @override
  String get asrStandardHint =>
      'معامل الظل 1، ويُستخدم في المذاهب الشافعي والمالكي والحنبلي.';

  @override
  String get asrHanafiHint => 'معامل الظل 2، ويُستخدم في المذهب الحنفي.';

  @override
  String get manualPrayerAdjustments => 'تعديلات الوقت اليدوية';

  @override
  String get manualPrayerAdjustmentsHint =>
      'أضف أو اطرح الدقائق فقط لمطابقة تقويم محلي موثوق.';

  @override
  String get advancedCalculationRules => 'القواعد المتقدمة';

  @override
  String get highLatitudeRule => 'قاعدة خطوط العرض العليا';

  @override
  String get polarResolution => 'معالجة الدائرة القطبية';

  @override
  String get middleOfNight => 'منتصف الليل';

  @override
  String get seventhOfNight => 'سُبع الليل';

  @override
  String get twilightAngle => 'زاوية الشفق';

  @override
  String get noPolarSubstitution => 'دون استبدال';

  @override
  String get nearestLatitude => 'أقرب خط عرض';

  @override
  String get nearestDay => 'أقرب يوم';

  @override
  String get sunrise => 'الشروق';

  @override
  String get decrease => 'إنقاص';

  @override
  String get increase => 'زيادة';

  @override
  String get currentLocation => 'الموقع الحالي';

  @override
  String get locationNotSelected => 'لم يتم اختيار الموقع';

  @override
  String get cityFallbackHint => 'استخدم موقع الجهاز أو اختر مدينة';

  @override
  String get chooseCity => 'اختيار مدينة';

  @override
  String get chooseCityInstead => 'اختيار مدينة بدلًا من ذلك';

  @override
  String get cityFallbackDescription =>
      'المدينة خيار احتياطي خاص محفوظ على الجهاز عند تعذر الموقع الدقيق.';

  @override
  String get searchCity => 'البحث عن مدينة';

  @override
  String get cityNotFound => 'لم يتم العثور على مدينة مطابقة';

  @override
  String get qibla => 'القبلة';

  @override
  String get qiblaDirection => 'اتجاه القبلة';

  @override
  String get fromGeographicNorth => 'من الشمال الجغرافي';

  @override
  String get qiblaNorthHint =>
      'هذا اتجاه جغرافي وليس بوصلة مباشرة. حاذِ أعلى الهاتف مع الشمال أولًا ثم اتبع السهم.';

  @override
  String get prayerCalendar => 'تقويم الصلاة الشهري';

  @override
  String get prayerCalendarHint => 'جميع أوقات الشهر المحدد متاحة دون اتصال';

  @override
  String get prayerCalendarUnavailable => 'تعذّر حساب هذا الشهر';

  @override
  String get prayerCalendarNeedsLocation => 'اختر الموقع من شاشة الصلاة أولًا';

  @override
  String get previousMonth => 'الشهر السابق';

  @override
  String get nextMonth => 'الشهر التالي';

  @override
  String get prayerWidget => 'ويدجت أوقات الصلاة';

  @override
  String get prayerWidgetHint =>
      'الصلاة القادمة والأوقات الخمسة على الشاشة الرئيسية، حتى بدون إنترنت';

  @override
  String get addPrayerWidget => 'إضافة الويدجت';

  @override
  String get prayerWidgetPinRequested =>
      'اختر موضع ويدجت IQRO على الشاشة الرئيسية';

  @override
  String get prayerWidgetManualAndroid =>
      'اضغط مطولاً على مساحة فارغة في الشاشة الرئيسية، ثم افتح الويدجت واختر IQRO.';

  @override
  String get prayerWidgetManualIos =>
      'اضغط مطولاً على الشاشة الرئيسية، ثم اضغط +، وابحث عن IQRO وأضف الويدجت.';

  @override
  String get prayerWidgetNeedsLocation =>
      'اختر الموقع واحسب أوقات الصلاة أولاً';

  @override
  String get prayerLocationPrivacy =>
      'تبقى إحداثياتك على هذا الجهاز ولا تُضاف إلى التحليلات.';

  @override
  String get useMyLocation => 'استخدم موقعي';

  @override
  String get locationDenied =>
      'الوصول إلى الموقع متوقف. يمكنك تفعيله من إعدادات الجهاز.';

  @override
  String get locationServicesDisabled => 'خدمة الموقع متوقفة';

  @override
  String get locationServicesDisabledBody =>
      'فعّل خدمات الموقع ثم ارجع إلى IQRO ليُستأنف حساب أوقات الصلاة تلقائيًا.';

  @override
  String get locationPermissionRequired => 'يلزم السماح بالوصول إلى الموقع';

  @override
  String get locationPermissionRequiredBody =>
      'اسمح بالوصول مرة واحدة لحساب أوقات الصلاة. تبقى الإحداثيات على هذا الجهاز.';

  @override
  String get locationUnavailable => 'تعذر تحديد الموقع';

  @override
  String get prayerCalculationFailed =>
      'تعذر حساب أوقات الصلاة. تحقق من طريقة الحساب وحاول مرة أخرى.';

  @override
  String get prayerUnavailable => 'لم تُحسب مواقيت الصلاة بعد';

  @override
  String get fajr => 'الفجر';

  @override
  String get dhuhr => 'الظهر';

  @override
  String get asr => 'العصر';

  @override
  String get maghrib => 'المغرب';

  @override
  String get isha => 'العشاء';

  @override
  String get memorizationTitle => 'تدريب الحفظ';

  @override
  String get memorizationCreatePlan => 'إنشاء خطة للحفظ';

  @override
  String get memorizationEditPlan => 'تعديل الخطة';

  @override
  String get memorizationPlanDescription =>
      'اختر السورة ونطاق الآيات والهدف اليومي ومدة التوقف والتلاوة. تتم مزامنة الخطة مع حسابك.';

  @override
  String get memorizationDailyRepetitions => 'التكرارات اليومية';

  @override
  String get memorizationPauseSeconds => 'التوقف بين التكرارات بالثواني';

  @override
  String get memorizationReciter => 'القارئ للتدريب';

  @override
  String get memorizationWithoutAudio => 'بدون صوت';

  @override
  String get memorizationSavePlan => 'حفظ الخطة';

  @override
  String get memorizationPlanSaved => 'تم حفظ خطة الحفظ';

  @override
  String get memorizationRangeInvalid => 'تحقق من بداية نطاق الآيات ونهايته';

  @override
  String get memorizationTodayCompleted => 'اكتمل هدف اليوم';

  @override
  String get memorizationRemaining => 'التكرارات المتبقية';

  @override
  String get repetitionTarget => 'التكرارات';

  @override
  String get again => 'مرة أخرى';

  @override
  String get hard => 'صعب';

  @override
  String get good => 'جيد';

  @override
  String get resetToday => 'إعادة ضبط اليوم';

  @override
  String get resetConfirm => 'هل تريد مسح نتيجة تكرارات اليوم فقط؟';

  @override
  String get dua => 'الدعاء';

  @override
  String get duaSubtitle => 'أدعية وأذكار من مصادر قابلة للتتبع';

  @override
  String duaCount(int count) {
    return 'عدد الأدعية: $count';
  }

  @override
  String get noDuaCategories => 'لا توجد فئات أدعية متاحة بعد';

  @override
  String get noDuaFound => 'لم يتم العثور على دعاء مطابق';

  @override
  String get duaSearchMinCharacters => 'أدخل حرفين على الأقل للبحث';

  @override
  String get duaUnavailable => 'هذا الدعاء غير متاح';

  @override
  String get cachedDuaWarning =>
      'يتم عرض نسخة محفوظة. سيتاح الصوت بعد التحقق من الإصدار الحالي.';

  @override
  String get duaAudio => 'صوت الدعاء';

  @override
  String get duaAudioStreaming => 'يلزم الاتصال بالإنترنت للاستماع';

  @override
  String get duaAudioFailed => 'تعذر تشغيل الصوت';

  @override
  String get duaPractice => 'تدريب التكرار';

  @override
  String get duaPracticeHint =>
      'اضغط بعد كل قراءة. يبقى هذا العداد في هذه الشاشة فقط.';

  @override
  String get reset => 'إعادة ضبط';

  @override
  String get sourceAndVerification => 'المصدر والتحقق';

  @override
  String get sourceDeclared => 'المصدر مذكور';

  @override
  String get sourceUnavailable => 'تفاصيل المصدر غير متاحة';

  @override
  String get editoriallyVerified => 'تم التحقق تحريرياً';

  @override
  String get copyText => 'نسخ النص';

  @override
  String get textCopied => 'تم نسخ النص';

  @override
  String get shareDua => 'مشاركة الدعاء';

  @override
  String get duaReader => 'القارئ';

  @override
  String get practiceStage => 'المرحلة';

  @override
  String get markRepetition => 'تسجيل تكرار';

  @override
  String get author => 'المؤلف';

  @override
  String get translator => 'المترجم';

  @override
  String get reviewer => 'المراجع';

  @override
  String get sourceVersion => 'إصدار المصدر';

  @override
  String get sourceReference => 'المرجع';

  @override
  String get grade => 'الدرجة';

  @override
  String get rights => 'شروط الاستخدام';

  @override
  String get favorites => 'المفضلة';

  @override
  String get all => 'الكل';

  @override
  String get emptyFavorites => 'احفظ آية أو دعاء لتجده هنا.';

  @override
  String get account => 'الحساب';

  @override
  String get personalProfile => 'الملف الشخصي';

  @override
  String get signIn => 'تسجيل الدخول';

  @override
  String get email => 'البريد الإلكتروني';

  @override
  String get verificationCode => 'رمز التحقق';

  @override
  String get sendCode => 'إرسال الرمز';

  @override
  String get verify => 'تحقق';

  @override
  String get signOut => 'تسجيل الخروج';

  @override
  String get devices => 'الأجهزة';

  @override
  String get syncNow => 'مزامنة الآن';

  @override
  String get syncHint =>
      'أرسل التغييرات المحلية واستقبل تحديثات أجهزتك الأخرى.';

  @override
  String get language => 'اللغة';

  @override
  String get theme => 'المظهر';

  @override
  String get systemTheme => 'النظام';

  @override
  String get lightTheme => 'فاتح';

  @override
  String get darkTheme => 'داكن';

  @override
  String get shareApp => 'شارك إقرأ';

  @override
  String get shareTitle => 'ادعُ من تحب إلى إقرأ';

  @override
  String get shareBody => 'شارك طريقة هادئة لقراءة القرآن والاستماع إليه.';

  @override
  String get shareButton => 'مشاركة التطبيق';

  @override
  String get copyLink => 'نسخ الرابط';

  @override
  String get linkCopied => 'تم نسخ الرابط';

  @override
  String get referralSummary => 'دعواتك';

  @override
  String get invited => 'المدعوون';

  @override
  String get qualified => 'المؤهلون';

  @override
  String get rewardBalance => 'رصيد المكافآت';

  @override
  String get referralRequiresAccount =>
      'يتاح رابط الدعوة الشخصي بعد تأكيد البريد الإلكتروني.';

  @override
  String get remoteCopy => 'تدير إقرأ نص الحملة';

  @override
  String get bundledCopy => 'يُستخدم نص المشاركة المضمّن';

  @override
  String get networkError => 'تعذر الاتصال بإقرأ';

  @override
  String get sessionExpired => 'انتهت الجلسة، وعملك دون اتصال محفوظ.';

  @override
  String get syncConflict => 'يوجد تقدم أحدث على جهازك الآخر.';

  @override
  String get loading => 'جارٍ التحميل…';

  @override
  String get offline => 'غير متصل';

  @override
  String get offlineMushaf => 'المصحف دون إنترنت';

  @override
  String get offlineMushafDescription =>
      'نزّل جميع الصفحات وخريطة الآيات. تُفحص الملفات قبل تفعيلها.';

  @override
  String get downloadForOffline => 'تنزيل';

  @override
  String get mushafDownloading => 'جارٍ تنزيل المصحف';

  @override
  String get mushafAvailableOffline => 'متاح دون إنترنت';

  @override
  String get mushafDownloadFailed =>
      'توقف التنزيل. يمكنك المتابعة من الموضع المحفوظ.';

  @override
  String get resumeDownload => 'متابعة';

  @override
  String get offlineAudio => 'الصوت دون إنترنت';

  @override
  String get offlineAudioDescription =>
      'نزّل السور الـ114 لهذه التلاوة. يُفحص كل ملف قبل تفعيله.';

  @override
  String get audioDownloading => 'جارٍ تنزيل الصوت';

  @override
  String get audioAvailableOffline => 'الصوت متاح دون إنترنت';

  @override
  String get audioDownloadFailed =>
      'توقف تنزيل الصوت. يمكنك المتابعة من الموضع المحفوظ.';

  @override
  String get audioOfflineUnavailable =>
      'هذه التلاوة غير مرخّصة للتنزيل دون إنترنت.';

  @override
  String get offlineStorage => 'التخزين دون إنترنت';

  @override
  String get offlineStorageSettingsSubtitle => 'صفحات المصحف والصوت المنزّلة';

  @override
  String offlineStorageUsed(String size) {
    return 'المستخدم دون إنترنت: $size';
  }

  @override
  String get offlineStorageDescription =>
      'تظهر هنا الملفات التي نزّلها التطبيق فقط. لا يُحذف أي شيء تلقائياً.';

  @override
  String offlineStorageQuota(String size) {
    return 'حد التطبيق: $size';
  }

  @override
  String get offlineStorageQuotaExceeded =>
      'لا تتسع الحزمة ضمن حد التخزين دون إنترنت. احذف حزمة غير ضرورية أولاً.';

  @override
  String downloadOfflineConfirmation(String size) {
    return 'ستشغل الحزمة الكاملة نحو $size. هل تريد بدء التنزيل؟';
  }

  @override
  String get downloadedContent => 'المحتوى المنزّل';

  @override
  String get noOfflinePackages => 'لم يتم تنزيل حزم للعمل دون إنترنت بعد.';

  @override
  String get storageReadFailed => 'تعذرت قراءة التخزين دون إنترنت';

  @override
  String get tryAgain => 'يرجى المحاولة مرة أخرى.';

  @override
  String get refresh => 'تحديث';

  @override
  String get deleteOfflinePackage => 'حذف حزمة دون إنترنت';

  @override
  String deleteOfflinePackageConfirmation(String name, String size) {
    return 'حذف «$name» ($size) من هذا الجهاز؟ ستحتاج إلى تنزيلها مجدداً للاستخدام دون إنترنت.';
  }

  @override
  String deletePlayingAudioConfirmation(String name, String size) {
    return 'يتم تشغيل «$name» الآن. هل تريد إيقاف المشغّل وحذف الحزمة ($size) من هذا الجهاز؟';
  }

  @override
  String get offlinePackageDeleted => 'تم حذف الحزمة';

  @override
  String get offlinePackageDeleteFailed => 'تعذر حذف الحزمة';

  @override
  String packageTotalSize(String size) {
    return 'الحجم الكامل $size';
  }

  @override
  String get completeMushafPages => 'صفحات المصحف كاملة';

  @override
  String get completeRecitation => 'تلاوة القرآن كاملة';

  @override
  String get downloadInProgress => 'التنزيل جارٍ';

  @override
  String get downloadFailed => 'توقف التنزيل';

  @override
  String get notReady => 'غير جاهز';

  @override
  String get availableOffline => 'متاح دون إنترنت';

  @override
  String get moreTools => 'التدريب والأدوات';

  @override
  String get books => 'الكتب';

  @override
  String get quizzes => 'الاختبارات';

  @override
  String get support => 'الدعم';

  @override
  String get privacy => 'الخصوصية';

  @override
  String get reminders => 'التذكيرات';

  @override
  String get remindersSubtitle => 'الصلاة ومراجعة القرآن';

  @override
  String get notificationAccess => 'السماح بالإشعارات';

  @override
  String get notificationAccessBody =>
      'سيذكّرك IQRO في الوقت المحدد حتى عند إغلاق التطبيق.';

  @override
  String get allowNotifications => 'السماح بالإشعارات';

  @override
  String get notificationDenied => 'الإشعارات متوقفة في إعدادات الجهاز.';

  @override
  String get approximateDelivery =>
      'قد يرسل النظام التذكير بتأخير بسيط لتوفير البطارية.';

  @override
  String get prayerReminders => 'تذكيرات الصلاة';

  @override
  String get prayerReminderSetup =>
      'اختر أولاً طريقة الحساب وحدد الموقع في قسم مواقيت الصلاة.';

  @override
  String get quranReviewReminders => 'مراجعة القرآن';

  @override
  String get addReminder => 'إضافة تذكير';

  @override
  String get noReminders => 'لا توجد تذكيرات للمراجعة بعد.';

  @override
  String get reviewReminder => 'مراجعة الآيات';

  @override
  String get reminderTime => 'الوقت';

  @override
  String get reminderDays => 'الأيام';

  @override
  String get everyDay => 'كل يوم';

  @override
  String get signal => 'التنبيه';

  @override
  String get sound => 'بصوت';

  @override
  String get vibration => 'اهتزاز';

  @override
  String get silent => 'صامت';

  @override
  String get timezone => 'المنطقة الزمنية';

  @override
  String get deviceTimezone => 'منطقة الجهاز';

  @override
  String get fixedTimezone => 'ثابتة';

  @override
  String get timezoneName => 'منطقة IANA الزمنية';

  @override
  String get startAyah => 'الآية الأولى';

  @override
  String get endAyah => 'الآية الأخيرة';

  @override
  String get delete => 'حذف';

  @override
  String get deleteReminderConfirm => 'هل تريد حذف هذا التذكير؟';

  @override
  String get reminderSaved => 'تم حفظ التذكير';

  @override
  String get mondayShort => 'ن';

  @override
  String get tuesdayShort => 'ث';

  @override
  String get wednesdayShort => 'ر';

  @override
  String get thursdayShort => 'خ';

  @override
  String get fridayShort => 'ج';

  @override
  String get saturdayShort => 'س';

  @override
  String get sundayShort => 'ح';

  @override
  String get readerHaptics => 'الاهتزاز عند تقليب الصفحات';

  @override
  String get readerHapticsHint =>
      'اهتزاز قصير عند تغيير صفحة المصحف. يجب أيضاً تفعيل اهتزاز اللمس في إعدادات أندرويد.';
}

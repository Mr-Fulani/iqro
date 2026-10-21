// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Arabic (`ar`).
class AppLocalizationsAr extends AppLocalizations {
  AppLocalizationsAr([String locale = 'ar']) : super(locale);

  @override
  String homePrayerIn(String time) {
    return 'بعد $time';
  }

  @override
  String get homeSavedHint => 'الآيات والأدعية المحفوظة';

  @override
  String get homeDownloads => 'التنزيلات';

  @override
  String get bookmarks => 'العلامات المرجعية';

  @override
  String get emptyBookmarks =>
      'لا توجد علامات مرجعية بعد. احفظ آية باستخدام رمز العلامة المرجعية في المصحف.';

  @override
  String get bookmarksLoadError => 'تعذر تحميل العلامات المرجعية';

  @override
  String get notes => 'ملاحظات';

  @override
  String get emptyNotes => 'لا توجد ملاحظات بعد. أضف ملاحظة إلى آية في المصحف.';

  @override
  String get addNote => 'إضافة ملاحظة';

  @override
  String get editNote => 'تعديل الملاحظة';

  @override
  String get noteHint => 'اكتب ملاحظة حول هذه الآية';

  @override
  String get noteLabel => 'ملاحظتك';

  @override
  String noteWordCount(int count) {
    return 'عدد الكلمات: $count';
  }

  @override
  String get removeNote => 'حذف الملاحظة';

  @override
  String get noteSaved => 'تم حفظ الملاحظة';

  @override
  String get noteRemoved => 'تم حذف الملاحظة';

  @override
  String get highlightAyah => 'تمييز';

  @override
  String get chooseHighlightColor => 'اختر لون التمييز';

  @override
  String get highlightColorEmerald => 'زمردي';

  @override
  String get highlightColorYellow => 'أصفر';

  @override
  String get highlightColorPink => 'وردي';

  @override
  String get highlightColorLime => 'ليموني';

  @override
  String get highlightColorBlue => 'أزرق';

  @override
  String get highlightColorLavender => 'لافندر';

  @override
  String get removeHighlight => 'إزالة التمييز';

  @override
  String get removeHighlightWithNote => 'ستُحذف ملاحظة هذه الآية أيضًا.';

  @override
  String get highlightRemoved => 'أُزيل التمييز';

  @override
  String get repeatSelectedAyah => 'تكرار الآية المحددة';

  @override
  String get copyAyah => 'نسخ الآية';

  @override
  String get shareAyah => 'مشاركة الآية';

  @override
  String get copied => 'تم نسخ الآية';

  @override
  String get copyAyahFailed => 'تعذّر نسخ الآية';

  @override
  String get mushafFitWidth => 'ملاءمة العرض';

  @override
  String get mushafFitPage => 'الصفحة كاملة';

  @override
  String get checkMushafUpdates => 'التحقق من التحديثات';

  @override
  String get mushafUpToDate => 'المصحف المحمّل محدّث';

  @override
  String get updateMushaf => 'تحديث المصحف';

  @override
  String updateMushafConfirmation(String size) {
    return 'تنزيل الصفحات المحدّثة ($size). سيبقى المصحف الحالي متاحًا حتى اكتمال تنزيل الحزمة الجديدة والتحقق منها.';
  }

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
  String get namesOfAllah => 'أسماء الله الحسنى';

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
  String get mushafCatalogEmpty => 'لم يتم تحميل المصاحف بعد';

  @override
  String get mushafPreviewDescription => 'حفص · تنسيق IQRO · نسخة تجريبية';

  @override
  String get mushafPublishedDescription => 'حفص · القراءة مع الإنترنت وبدونه';

  @override
  String get mushafPickerHint => 'اضغط على الصفحة لمعاينتها عن قرب';

  @override
  String get mushafMakePrimary => 'اجعله المصحف الأساسي';

  @override
  String get mushafIsPrimary => 'المصحف الأساسي';

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
  String get styleKidsRepeat => 'للأطفال مع التكرار';

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
  String get playerBackground => 'خلفية المشغل';

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
  String get qiblaNorth => 'ش';

  @override
  String get qiblaLiveHint =>
      'بوصلة الجهاز مفعّلة: أمسك الهاتف أفقيًا — يشير السهم إلى القبلة بالنسبة إلى أعلاه.';

  @override
  String get qiblaFacing => 'أنت متجه إلى القبلة';

  @override
  String get qiblaCalibrationNeeded => 'البوصلة تحتاج إلى معايرة';

  @override
  String get qiblaCalibrationHint =>
      'حرّك الهاتف في الهواء على شكل رقم ثمانية عدة مرات، بعيدًا عن المعادن والمغناطيس، بما في ذلك الأغطية المغناطيسية.';

  @override
  String get qiblaCompassUnavailable => 'البوصلة غير متاحة على هذا الجهاز.';

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
  String get homeWidgetAlreadyAdded =>
      'تمت إضافة الأداة بالفعل. تم تحديث بياناتها.';

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
  String get duaFavoritesSubtitle => 'الأدعية المحفوظة';

  @override
  String duaChapterNumber(int number) {
    return 'الباب $number';
  }

  @override
  String duaCounterRemaining(int count) {
    return 'المتبقي: $count';
  }

  @override
  String get duaAudioFailed => 'تعذر تشغيل الصوت';

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
  String get shareReadInIqro => 'اقرأ في IQRO';

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
  String get invalidEmail => 'تحقق من البريد الإلكتروني.';

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
  String get currentDevice => 'هذا الجهاز';

  @override
  String get noDevices => 'لم يتم العثور على أجهزة.';

  @override
  String get feedbackTitle => 'الملاحظات والتدقيق الديني';

  @override
  String get feedbackAccountHint =>
      'أبلغ عن مشكلة في النص أو الصوت أو أوقات الصلاة أو التطبيق.';

  @override
  String get feedbackSignInRequired => 'سجّل الدخول لإرسال طلب';

  @override
  String get feedbackDescription =>
      'أبلغ هيئة التحرير الدينية عن أي خطأ في النص أو التوقيت أو حساب الصلاة.';

  @override
  String get feedbackCreate => 'إنشاء طلب';

  @override
  String get feedbackCategory => 'فئة الطلب';

  @override
  String get feedbackSubject => 'الموضوع';

  @override
  String get feedbackSubjectPlaceholder => 'وصف موجز';

  @override
  String get feedbackMessage => 'الرسالة';

  @override
  String get feedbackMessagePlaceholder => 'وصف تفصيلي للسؤال أو الملاحظة…';

  @override
  String get feedbackSend => 'إرسال الطلب';

  @override
  String get feedbackNone => 'لا توجد طلبات نشطة.';

  @override
  String feedbackTicket(String id) {
    return 'الطلب $id';
  }

  @override
  String feedbackTeam(String team) {
    return 'الفريق: $team';
  }

  @override
  String get feedbackNoMessages => 'لا توجد رسائل بعد.';

  @override
  String get feedbackAddMessage => 'إضافة رسالة';

  @override
  String get feedbackReplyPlaceholder => 'ردك إلى التحرير أو الدعم';

  @override
  String get feedbackSendMessage => 'إرسال الرسالة';

  @override
  String get feedbackReopen => 'إعادة الفتح';

  @override
  String get feedbackCloseTicket => 'إغلاق الطلب';

  @override
  String get feedbackCloseConfirmation =>
      'هل تريد إغلاق هذا الطلب؟ يمكنك إعادة فتحه لاحقًا.';

  @override
  String get feedbackNoFurtherActions => 'لا يمكن إرسال رسائل أخرى لهذا الطلب.';

  @override
  String get feedbackRequiredFields => 'أدخل الموضوع والرسالة.';

  @override
  String get feedbackRateLimited => 'طلبات كثيرة جدًا. حاول لاحقًا.';

  @override
  String get feedbackActionError => 'تعذر تنفيذ إجراء الطلب. حاول لاحقًا.';

  @override
  String get feedbackCategoryReligious => 'المحتوى الديني';

  @override
  String get feedbackCategoryLayout => 'صفحة المصحف أو التخطيط';

  @override
  String get feedbackCategoryAudio => 'الصوت أو التوقيت أو القارئ';

  @override
  String get feedbackCategoryAdvertisement => 'إعلان';

  @override
  String get feedbackCategoryTechnical => 'مشكلة تقنية';

  @override
  String get feedbackCategoryAccount => 'الحساب أو المزامنة';

  @override
  String get feedbackCategoryDonation => 'تبرع أو رابط خارجي';

  @override
  String get feedbackCategoryAccessibility => 'إمكانية الوصول أو الترجمة';

  @override
  String get feedbackCategoryGeneral => 'اقتراح عام';

  @override
  String get feedbackCategoryOther => 'أخرى';

  @override
  String get feedbackStatusNew => 'جديد';

  @override
  String get feedbackStatusTriaged => 'قيد الفرز';

  @override
  String get feedbackStatusProgress => 'قيد التنفيذ';

  @override
  String get feedbackStatusWaiting => 'بانتظار ردك';

  @override
  String get feedbackStatusResolved => 'تم الحل';

  @override
  String get feedbackStatusRejected => 'مرفوض';

  @override
  String get feedbackStatusDuplicate => 'مكرر';

  @override
  String get feedbackStatusClosed => 'مغلق';

  @override
  String get feedbackSupport => 'الدعم';

  @override
  String get feedbackYou => 'أنت';

  @override
  String get feedbackSystem => 'النظام';

  @override
  String get signOutConfirmation => 'هل تريد تسجيل الخروج من هذا الجهاز؟';

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
  String get offlineStorageSettingsSubtitle =>
      'صفحات المصحف والصوت وصور دورة الصلاة المنزّلة';

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

  @override
  String get mushafPageCaching =>
      'تُحمّل الصفحات أثناء القراءة. تُحفظ الصفحات المفتوحة وخطوطها على الجهاز لتبقى متاحة دون اتصال.';

  @override
  String get planCreditedToday => 'المحتسب اليوم';

  @override
  String get planGoalLabel => 'الهدف اليومي';

  @override
  String get planEditGoal => 'تعديل الهدف';

  @override
  String get planGoalReached => 'تم بلوغ الهدف اليومي';

  @override
  String planRemainingAmount(String amount) {
    return 'المتبقي لبلوغ الهدف: $amount';
  }

  @override
  String planGoalAmount(String amount) {
    return 'الهدف: $amount';
  }

  @override
  String planCreditedAmount(String amount) {
    return 'المحتسب: $amount';
  }

  @override
  String get planManualEntry => 'إضافة قراءة يدوياً';

  @override
  String get planManualHelp =>
      'أضف قراءة لم تُحتسب من قبل. يزيد ذلك تقدم اليوم ولا يغيّر هدفك.';

  @override
  String get planHowCounted => 'كيف يُحتسب التقدم';

  @override
  String get planPagesHelp =>
      'يُحتسب الانتقال إلى الصفحة التالية في القارئ تلقائياً، وتُضاف الإدخالات اليدوية أيضاً. تقليب الصفحات لا يؤكد قراءتها.';

  @override
  String get planMinutesHelp =>
      'يُحتسب الوقت النشط في القارئ تلقائياً، وتُضاف الدقائق المسجلة يدوياً أيضاً.';

  @override
  String get planAyahsHelp =>
      'يُحتسب التقدم المتتابع بين الآيات في القارئ تلقائياً، وتُضاف الآيات المسجلة يدوياً أيضاً.';

  @override
  String get planDailyHelp =>
      'يُحتسب التقدم لكل يوم على حدة. تغيير الهدف لا يصفر التقدم، وتبقى الأيام السابقة في السجل.';

  @override
  String get planResetHelp =>
      'يمكن تقليل الصفحات المسجلة بعد الصلاة بزر −. لا يمكن تصفير تقدم اليوم بالكامل من هذه الشاشة.';

  @override
  String get planPrayerTitle => 'القراءة بعد الصلاة';

  @override
  String get planPrayerSummary =>
      'الصفحات التي سجلتها اليوم. هذه قراءات مسجلة وليست هدفاً.';

  @override
  String get planEditPrayer => 'تعديل تسجيلات اليوم';

  @override
  String get planPrayerInstructions =>
      'سجّل الصفحات المقروءة بعد كل صلاة. يضيف + صفحة واحدة ويزيل − صفحة واحدة. الصفر يعني عدم وجود صفحات مسجلة.';

  @override
  String planRemovePage(String prayer) {
    return 'إزالة صفحة واحدة: $prayer';
  }

  @override
  String planAddPage(String prayer) {
    return 'إضافة صفحة واحدة: $prayer';
  }

  @override
  String get planUnavailable =>
      'تعذر تحديث الخطة. يُعرض التقدم المحفوظ، ويمكن التعديل بعد نجاح التحديث.';

  @override
  String get planGoalHint =>
      'اختر هدفك اليومي بالدقائق أو الصفحات أو الآيات. هذا يحدد الهدف ولا يسجل قراءة مكتملة.';

  @override
  String planBestStreak(String streak) {
    return 'أفضل سلسلة: $streak';
  }

  @override
  String planActiveTime(String amount) {
    return 'القراءة النشطة: $amount';
  }

  @override
  String planPages(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString صفحة',
      many: '$countString صفحة',
      few: '$countString صفحات',
      two: '$countString صفحتان',
      one: '$countString صفحة',
      zero: '$countString صفحة',
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
      other: '$countString دقيقة',
      many: '$countString دقيقة',
      few: '$countString دقائق',
      two: '$countString دقيقتان',
      one: '$countString دقيقة',
      zero: '$countString دقيقة',
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
      other: '$countString آية',
      many: '$countString آية',
      few: '$countString آيات',
      two: '$countString آيتان',
      one: '$countString آية',
      zero: '$countString آية',
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
      other: '$countString يوم متتالٍ',
      many: '$countString يوماً متتالياً',
      few: '$countString أيام متتالية',
      two: '$countString يومان متتاليان',
      one: '$countString يوم متتالٍ',
      zero: '$countString يوم متتالٍ',
    );
    return '$_temp0';
  }

  @override
  String get palmTitle => 'نخلتك';

  @override
  String get palmStageSeed => 'نواة التمر';

  @override
  String get palmStageSprout => 'برعم';

  @override
  String get palmStageSeedling => 'فسيلة';

  @override
  String get palmStageYoungPalm => 'نخلة فتية';

  @override
  String get palmStagePalm => 'نخلة';

  @override
  String get palmStageFruitingPalm => 'نخلة مثمرة';

  @override
  String get palmMoodPlanting => 'ازرع النواة: اقرأ أول صفحة';

  @override
  String get palmMoodFlourishing => 'أتممت هدف اليوم — النخلة تمتدّ نحو الشمس';

  @override
  String get palmMoodGrowing => 'قراءة اليوم تسقي نخلتك';

  @override
  String get palmMoodWaiting => 'نخلتك تنتظر قراءة اليوم';

  @override
  String get palmMoodResting => 'نخلتك تستريح في الظل، وصفحة واحدة تُسعدها';

  @override
  String palmNextStage(String stage) {
    return 'التالي: $stage';
  }

  @override
  String get palmFullyGrown => 'اكتمل نموّها — بارك الله في ثمرها';

  @override
  String get palmHowItGrows =>
      'يوم القراءة +1، وإتمام الهدف +2. الأيام الفائتة لا تضرّ النخلة، إنها تستريح فقط.';

  @override
  String get planSummaryTitle => 'ملخص التقدم';

  @override
  String planSummaryRange(num days) {
    return 'آخر $days يوماً';
  }

  @override
  String get planReadingDays => 'أيام القراءة';

  @override
  String get planCompletedDays => 'الأهداف المكتملة';

  @override
  String get planPartialDays => 'الأيام الجزئية';

  @override
  String get planCalendarTitle => 'تقويم التقدم';

  @override
  String get planCalendarHint =>
      'اختر يوماً لرؤية الهدف والقراءة وعلامات ما بعد الصلاة.';

  @override
  String get planCalendarEmpty => 'لا توجد بيانات لهذه الفترة.';

  @override
  String get planSelectedDay => 'اليوم المحدد';

  @override
  String get planRelatedTools => 'أقسام مرتبطة';

  @override
  String get planHistoryEmpty => 'لا توجد سجلات قراءة لهذه الفترة.';

  @override
  String planPrayerCount(num count) {
    return 'علامات ما بعد الصلاة: $count';
  }

  @override
  String planAutomaticSessions(num count) {
    return 'جلسات تلقائية: $count';
  }

  @override
  String get planManualRecord => 'أضيفت يدوياً';

  @override
  String get planEditEntry => 'تعديل السجل';

  @override
  String get planDeleteEntry => 'حذف السجل';

  @override
  String get planDeleteEntryTitle => 'حذف السجل؟';

  @override
  String get planDeleteEntryConfirm =>
      'سيُحذف هذا السجل اليدوي ويُعاد حساب التقدم.';

  @override
  String get planReadingAmount => 'الكمية';

  @override
  String get planReadingDate => 'تاريخ القراءة';

  @override
  String get planStateNoGoal => 'بلا هدف';

  @override
  String get planStatePending => 'اليوم';

  @override
  String get planStateMissed => 'فائت';

  @override
  String get planStatePartial => 'جزئي';

  @override
  String get planStateCompleted => 'مكتمل';

  @override
  String planDays(num count) {
    return '$count أيام';
  }

  @override
  String get salahTitle => 'تعلّم الصلاة';

  @override
  String get salahHint => 'خطوة بخطوة: الوضوء والصلوات الخمس';

  @override
  String salahLessonsProgress(int done, int total) {
    return '$done من $total دروس';
  }

  @override
  String get salahContinue => 'متابعة';

  @override
  String get salahStart => 'ابدأ';

  @override
  String salahStepOf(int current, int total) {
    return 'الخطوة $current من $total';
  }

  @override
  String salahRakatOf(int current, int total) {
    return 'الركعة $current من $total';
  }

  @override
  String get salahBack => 'السابق';

  @override
  String get salahNext => 'التالي';

  @override
  String get salahFinish => 'إنهاء';

  @override
  String get salahNextStep => 'الخطوة التالية';

  @override
  String get salahPreviousStep => 'الخطوة السابقة';

  @override
  String get salahModeLearn => 'تعلّم';

  @override
  String get salahModePractice => 'تدريب';

  @override
  String get salahDisplayOptions => 'ما يُعرض';

  @override
  String get salahShowArabic => 'النص العربي';

  @override
  String get salahShowTransliteration => 'النطق';

  @override
  String get salahShowTranslation => 'المعنى';

  @override
  String salahMinutes(int count) {
    return '$count د';
  }

  @override
  String get salahLessonCompleted => 'اكتمل الدرس';

  @override
  String get salahStatusCompleted => 'مكتمل';

  @override
  String get salahStatusInProgress => 'بدأته';

  @override
  String get salahUnavailable => 'الدورة غير متاحة بعد';

  @override
  String get salahLessonNotFound => 'هذا الدرس غير موجود في الدورة';

  @override
  String get salahRulingShart => 'شرط';

  @override
  String get salahRulingRukn => 'ركن';

  @override
  String get salahRulingWajib => 'واجب';

  @override
  String get salahRulingSunnah => 'سنة';

  @override
  String get salah3dSchematic => 'رسم توضيحي تخطيطي ثلاثي الأبعاد';

  @override
  String get salah3dPlay => 'تشغيل الحركة';

  @override
  String get salah3dPause => 'إيقاف الحركة مؤقتًا';

  @override
  String salah3dSpeed(String speed) {
    return 'سرعة الحركة: $speed';
  }

  @override
  String get salah3dReplay => 'إعادة الحركة';

  @override
  String get salahOfflineTitle => 'الصور دون إنترنت';

  @override
  String get salahOfflineImages => 'رسوم الدورة التوضيحية';

  @override
  String get salahOfflineSaved => 'محفوظة على هذا الجهاز';

  @override
  String get salahOfflineUpdateAvailable => 'يتوفر إصدار جديد';

  @override
  String get salahOfflineUpdate => 'تحديث';

  @override
  String get accountSignOutEverywhere => 'تسجيل الخروج من جميع الأجهزة';

  @override
  String get accountSignOutEverywhereTitle => 'إنهاء جميع الجلسات؟';

  @override
  String get accountSignOutEverywhereDescription =>
      'ستُلغى الجلسة الحالية وتسجيلات الدخول على الأجهزة الأخرى. ستحتاج إلى رمز بريد جديد للمتابعة.';

  @override
  String get accountSignOutEverywhereConfirm => 'تأكيد الخروج من الجميع';

  @override
  String get accountSignOutEverywhereError =>
      'تعذر إنهاء جميع الجلسات. حاول مجددًا.';

  @override
  String get accountDangerZone => 'منطقة خطرة';

  @override
  String get accountDeletionTitle => 'حذف الحساب';

  @override
  String get accountDeletionDescription =>
      'بعد إعادة تأكيد البريد تبدأ مهلة إلغاء مدتها 7 أيام. لا يحدث الحذف النهائي قبل انتهائها.';

  @override
  String get accountDelete => 'حذف الحساب';

  @override
  String get accountDeletionRequestTitle => 'جدولة حذف الحساب؟';

  @override
  String get accountDeletionRequestDescription =>
      'يُحظر الوصول العادي فورًا. بعد 7 أيام تُحذف البيانات المتزامنة ويُجهّل الحساب.';

  @override
  String get accountDeletionCancelTitle => 'إلغاء الحذف؟';

  @override
  String get accountDeletionCancelDescription =>
      'لاستعادة الحساب، أثبت ملكية البريد برمز جديد لمرة واحدة.';

  @override
  String accountSendCodeTo(String email) {
    return 'إرسال الرمز إلى $email';
  }

  @override
  String get accountConfirmDeletion => 'تأكيد الحذف';

  @override
  String get accountRestore => 'استعادة الحساب';

  @override
  String get accountNewCode => 'طلب رمز جديد';

  @override
  String get accountPendingDeletionTitle => 'تمت جدولة حذف الحساب';

  @override
  String accountPendingDeletionDescription(String date) {
    return 'سيُحذف الحساب والبيانات المتزامنة بعد $date. وحتى ذلك الوقت يمكن إلغاء الحذف بعد تأكيد البريد.';
  }

  @override
  String get accountCancelDeletion => 'إلغاء الحذف';

  @override
  String get accountDeletionScheduledNotice =>
      'تمت جدولة حذف الحساب. يمكنك إلغاؤه قبل التاريخ المحدد.';

  @override
  String get accountDeletionCancelledNotice => 'تم إلغاء حذف الحساب.';

  @override
  String get accountCodeSendError => 'تعذر إرسال الرمز. حاول مجددًا.';

  @override
  String get accountCodeVerifyError => 'تعذر تأكيد الرمز.';

  @override
  String get accountCodeExpired => 'انتهت صلاحية التأكيد. اطلب رمزًا جديدًا.';

  @override
  String get accountActionError => 'تعذر إكمال إجراء الحساب.';

  @override
  String downloadOfflineSurahsConfirmation(int count, String size) {
    return 'عدد السور: $count، نحو $size. هل تريد بدء التنزيل؟';
  }

  @override
  String audioOfflineSurahs(int count) {
    return 'السور على هذا الجهاز: $count';
  }

  @override
  String audioOfflineNewSurahs(int count) {
    return 'سور جديدة: $count';
  }

  @override
  String get apiErrorEmailInvalid =>
      'الرمز غير صحيح أو تغيرت الجلسة. اطلب رمزًا جديدًا.';

  @override
  String get apiErrorEmailExpired => 'انتهت صلاحية الرمز. اطلب رمزًا جديدًا.';

  @override
  String get apiErrorEmailDelivery => 'تعذر إرسال الرمز. حاول لاحقًا.';

  @override
  String get apiErrorRateLimited => 'محاولات كثيرة جدًا. حاول لاحقًا.';

  @override
  String get apiErrorInstallationMissing =>
      'فُقدت جلسة الجهاز. اطلب رمزًا جديدًا.';

  @override
  String get apiErrorLinkUnavailable =>
      'لا يمكن إكمال هذا الدخول في الجلسة الحالية.';

  @override
  String get apiErrorIdentityLinked => 'هذا البريد مرتبط بحساب آخر.';

  @override
  String get apiErrorReauthRequired => 'يلزم رمز بريد جديد لهذا الإجراء.';

  @override
  String get apiErrorLifecycleUnavailable =>
      'إجراء الحساب هذا غير متاح حاليًا.';

  @override
  String get apiErrorCurrentDevice =>
      'استخدم تسجيل الخروج العادي للجهاز الحالي.';

  @override
  String get apiErrorDeviceNotFound => 'الجهاز مفصول بالفعل أو غير متاح.';

  @override
  String get apiErrorCursorExpired =>
      'انتهت صلاحية سجل المزامنة. تجري مزامنة كاملة.';

  @override
  String get apiErrorUnknown => 'حاول مرة أخرى لاحقًا.';
}

// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Turkish (`tr`).
class AppLocalizationsTr extends AppLocalizations {
  AppLocalizationsTr([String locale = 'tr']) : super(locale);

  @override
  String homePrayerIn(String time) {
    return '$time sonra';
  }

  @override
  String get homeSavedHint => 'Kaydedilen ayetler ve dualar';

  @override
  String get homeDownloads => 'İndirilenler';

  @override
  String get bookmarks => 'Yer işaretleri';

  @override
  String get emptyBookmarks =>
      'Henüz yer işareti yok. Mushaftaki yer işareti simgesine dokunarak bir ayeti kaydedin.';

  @override
  String get bookmarksLoadError => 'Yer işaretleri yüklenemedi';

  @override
  String get mushafFitWidth => 'Genişliğe sığdır';

  @override
  String get mushafFitPage => 'Tam sayfa';

  @override
  String get checkMushafUpdates => 'Güncellemeleri denetle';

  @override
  String get mushafUpToDate => 'İndirilen Mushaf güncel';

  @override
  String get updateMushaf => 'Mushafı güncelle';

  @override
  String updateMushafConfirmation(String size) {
    return 'Güncellenen sayfaları indir ($size). Yeni paket indirilip doğrulanana kadar mevcut Mushaf kullanılabilir kalır.';
  }

  @override
  String get hijriCalendar => 'Hicri takvim';

  @override
  String get hijriMethod => 'Ümmü\'l-Kurâ · çevrimdışı';

  @override
  String get hijriDisclaimer =>
      'Hesaplanan tarihler yerel hilal gözleminden farklı olabilir. Ramazan ve bayram başlangıçlarını yerel yetkili mercilerden doğrulayın. Hicri gün, önceki miladi günün gün batımında başlar.';

  @override
  String get hijriAdjustment => 'Tarih düzeltmesi';

  @override
  String get hijriAdjustmentHint =>
      'Yerel takviminize göre ayarlayın. Düzeltme tüm takvime uygulanır.';

  @override
  String get hijriSources => 'Dayanaklar ve kaynaklar';

  @override
  String get hijriNoEvents => 'Bu gün için özel bir işaret yok.';

  @override
  String get hijriUnavailable =>
      'Tarih desteklenen takvim aralığının dışında (1937–2077).';

  @override
  String get hijriToday => 'Bugünün hicri tarihi';

  @override
  String get hijriCivilDate => 'Miladi tarih';

  @override
  String get hijriSunsetDate => 'Yerel akşam vaktine göre tarih';

  @override
  String get hijriCivilHint =>
      'Bugünün akşam vakti yoksa miladi günün karşılığı gösterilir.';

  @override
  String get hijriYearSuffix => 'H';

  @override
  String get hijriEventHint =>
      'Bunlar kaynak işaretleridir, kişisel fetva değildir. Bayramlar nafile oruç günü olarak işaretlenmez; hacılar için Arefe gününün hükümleri farklıdır.';

  @override
  String get appLicenses => 'Bileşen lisansları';

  @override
  String hijriMonthName(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'Muharrem',
      'm2': 'Safer',
      'm3': 'Rebiülevvel',
      'm4': 'Rebiülahir',
      'm5': 'Cemaziyelevvel',
      'm6': 'Cemaziyelahir',
      'm7': 'Recep',
      'm8': 'Şaban',
      'm9': 'Ramazan',
      'm10': 'Şevval',
      'm11': 'Zilkade',
      'm12': 'Zilhicce',
      'other': 'Hicri',
    });
    return '$_temp0';
  }

  @override
  String hijriEventName(String event) {
    String _temp0 = intl.Intl.selectLogic(event, {
      'ramadan': 'Ramazan',
      'eidFitr': 'Ramazan Bayramı',
      'arafah': 'Arefe günü',
      'eidAdha': 'Kurban Bayramı',
      'tashriq': 'Teşrik günleri',
      'ashura': 'Aşure günü',
      'whiteDays': 'Eyyâm-ı bîd · 13–15',
      'lastTenNights': 'Ramazan\'ın son on gecesi',
      'other': 'Önemli gün',
    });
    return '$_temp0';
  }

  @override
  String get appName => 'IQRO';

  @override
  String get navHome => 'Ana sayfa';

  @override
  String get navQuran => 'Kur\'an';

  @override
  String get navPlan => 'Plan';

  @override
  String get navAudio => 'Ses';

  @override
  String get navMore => 'Daha';

  @override
  String get back => 'Geri';

  @override
  String get open => 'Aç';

  @override
  String get save => 'Kaydet';

  @override
  String get cancel => 'İptal';

  @override
  String get close => 'Kapat';

  @override
  String get retry => 'Tekrar dene';

  @override
  String get continueLabel => 'Devam';

  @override
  String get done => 'Bitti';

  @override
  String get soon => 'Yakında';

  @override
  String get search => 'Ara';

  @override
  String get settings => 'Ayarlar';

  @override
  String get welcomeTitle => 'Huzurlu bir günlük pratik';

  @override
  String get welcomeBody =>
      'Tek, özel ve odaklı uygulamada okuyun, dinleyin ve ritminizi koruyun.';

  @override
  String get chooseLanguage => 'Dil seçin';

  @override
  String get chooseGoal => 'Neye odaklanmak istersiniz?';

  @override
  String get goalReading => 'Günlük okuma';

  @override
  String get goalMemorization => 'Ezber';

  @override
  String get goalPrayer => 'Namaz desteği';

  @override
  String get goalDua => 'Dua';

  @override
  String get dailyNorm => 'Rahat bir günlük hedef seçin';

  @override
  String get minutes => 'dakika';

  @override
  String get pages => 'sayfa';

  @override
  String get ayahs => 'ayet';

  @override
  String get startAsGuest => 'Özel olarak başla';

  @override
  String get guestNote =>
      'İlerlemeniz bu cihazda kaydedilir. Daha sonra hesap bağlayabilirsiniz.';

  @override
  String get greeting => 'Selamün aleyküm';

  @override
  String get continueReading => 'Okumaya devam et';

  @override
  String get read => 'Oku';

  @override
  String get savedAutomatically => 'Konum otomatik kaydedildi';

  @override
  String get nextPrayer => 'Sonraki namaz';

  @override
  String get yourRhythm => 'Ritminiz';

  @override
  String get today => 'Bugün';

  @override
  String get openPlan => 'Planı aç';

  @override
  String get calmPace => 'Sakin bir tempo';

  @override
  String get afterPrayer => 'Namaz sonrası';

  @override
  String get memorization => 'Ezber';

  @override
  String get recentReciter => 'Son kâri';

  @override
  String get duaOfDay => 'Günün duası';

  @override
  String get readingAsGuest => 'Misafir olarak okuyorsunuz';

  @override
  String get guestSyncHint => 'Başka cihazda devam etmek için giriş yapın';

  @override
  String get quranSubtitle => 'Medine Mushafı · Hafs';

  @override
  String get alFatiha => 'Fâtiha';

  @override
  String get textMode => 'Metin';

  @override
  String get mushafMode => 'Mushaf';

  @override
  String get selectedMushaf => 'Seçili Mushaf';

  @override
  String get chooseMushaf => 'Mushaf seçin';

  @override
  String get mushafCatalogEmpty => 'Mushaflar henüz yüklenmedi';

  @override
  String get mushafPreviewDescription => 'Hafs · IQRO düzeni · ön izleme';

  @override
  String get mushafPublishedDescription =>
      'Hafs · çevrimiçi ve çevrimdışı okuma';

  @override
  String get mushafTextDescription => 'Ekrana uyarlanmış net metin';

  @override
  String get mushafWebOnly =>
      'Bu yazı tipi şimdilik yalnızca web sürümünde kullanılabilir';

  @override
  String get mushafUnavailable => 'Kaynakta geçici olarak kullanılamıyor';

  @override
  String get mushafCachedDescription =>
      'İlk açılışta indirilir · ardından çevrimdışı kullanılabilir';

  @override
  String get mushafLoading => 'Sayfa ve resmî yazı tipi yükleniyor…';

  @override
  String get mushafFontError =>
      'Resmî yazı tipi açılamadı. İnternete bağlıyken yeniden deneyin.';

  @override
  String get mushafOfflineMissing =>
      'Bu sayfa henüz cihaza kaydedilmedi. İnternete bağlanıp yeniden deneyin.';

  @override
  String get continueSaved => 'Kayıtlı yerden devam et';

  @override
  String get surahs => 'Sureler';

  @override
  String get juz => 'Cüz';

  @override
  String get hizb => 'Hizb';

  @override
  String get rubElHizb => 'Rub el-hizb';

  @override
  String get page => 'Sayfa';

  @override
  String get surah => 'Sure';

  @override
  String get ayah => 'Ayet';

  @override
  String get quickJump => 'Hızlı geçiş';

  @override
  String get navigation => 'Gezinme';

  @override
  String get meccan => 'Mekkî';

  @override
  String get medinan => 'Medenî';

  @override
  String get noQuranData => 'Kur\'an kataloğu kullanılamıyor';

  @override
  String get offlineUsingCache => 'Çevrimdışı — kayıtlı içerik gösteriliyor';

  @override
  String get readerSettings => 'Okuma ayarları';

  @override
  String get textAppearance => 'Metin görünümü';

  @override
  String get arabicTextSize => 'Arapça metin boyutu';

  @override
  String get lineSpacing => 'Satır aralığı';

  @override
  String get ayahSpacing => 'Ayetler arası boşluk';

  @override
  String get focusMode => 'Odak modu';

  @override
  String get focusModeDescription => 'Üst çubuğu ve yardımcı ipuçlarını gizle';

  @override
  String get exitFocusMode => 'Odak modundan çık';

  @override
  String get translation => 'Meal';

  @override
  String get tafsir => 'Tefsir';

  @override
  String get loadOnDemand => 'İstek üzerine yükle';

  @override
  String get translationUnavailable =>
      'Bu dil için onaylı bir meal henüz bağlı değil.';

  @override
  String get tafsirUnavailable =>
      'Tefsir, onaylı bir kaynak seçildikten sonra kullanılabilir.';

  @override
  String get bookmarkAdded => 'Favorilere eklendi';

  @override
  String get bookmarkRemoved => 'Yer imi kaldırıldı';

  @override
  String get listen => 'Dinle';

  @override
  String get tapForControls => 'Oynatıcı ve menü için dokunun';

  @override
  String get zoom => 'Yakınlaştırma';

  @override
  String get listenPage => 'Bu sayfayı dinle';

  @override
  String get tapAyahForDetails => 'Meal ve tefsir için ayete basılı tutun';

  @override
  String get audioTitle => 'Kur\'an\'ı dinleyin';

  @override
  String get chooseReciter => 'Kâri seçin';

  @override
  String get allReciters => 'Tüm kâriler';

  @override
  String get recitationStyle => 'Okuyuş stili';

  @override
  String get chooseRecitationStyle => 'Okuyuş stilini seçin';

  @override
  String get styleMurattal => 'Mürattel';

  @override
  String get styleMujawwad => 'Mücevved';

  @override
  String get styleMuallim => 'Muallim';

  @override
  String get refreshReciters => 'Kâri kataloğunu yenile';

  @override
  String get recitersUpdated => 'Kâri kataloğu güncellendi';

  @override
  String get recitersRefreshFailed =>
      'Katalog yenilenemedi. Kayıtlı veriler gösteriliyor.';

  @override
  String get noAudio => 'Oynatılabilir ses yok';

  @override
  String get nowPlaying => 'Şimdi çalıyor';

  @override
  String get play => 'Oynat';

  @override
  String get pause => 'Duraklat';

  @override
  String get previousSurah => 'Önceki sure';

  @override
  String get nextSurah => 'Sonraki sure';

  @override
  String get chooseSurah => 'Sure seç';

  @override
  String get speed => 'Hız';

  @override
  String get audioQuality => 'Ses kalitesi';

  @override
  String get qualityAutomatic => 'Otomatik';

  @override
  String get qualityEconomy => 'Veri tasarrufu';

  @override
  String get qualityStandard => 'Standart';

  @override
  String get qualityHigh => 'Yüksek';

  @override
  String audioBitrate(int bitrate) {
    return '$bitrate kb/sn';
  }

  @override
  String get range => 'Aralık';

  @override
  String get sleepTimer => 'Uyku zamanlayıcısı';

  @override
  String get repeat => 'Tekrar';

  @override
  String get repeatOff => 'Tekrar kapalı';

  @override
  String get repeatOn => 'Tekrar açık';

  @override
  String get off => 'Kapalı';

  @override
  String get backgroundPlayback => 'Arka plan ve kilit ekranı kontrolleri';

  @override
  String get dailyPlan => 'Günlük plan';

  @override
  String get dailyGoal => 'Günlük hedef';

  @override
  String get completed => 'Tamamlandı';

  @override
  String get remaining => 'Kalan';

  @override
  String get history => 'Geçmiş';

  @override
  String get manualEntry => 'Okuma ekle';

  @override
  String get addPages => 'Sayfa ekle';

  @override
  String get afterPrayerPlan => 'Namaz sonrası plan';

  @override
  String get prayer => 'Namaz vakitleri';

  @override
  String get calculationMethod => 'Hesaplama yöntemi';

  @override
  String get prayerCalculationSettings => 'Namaz hesaplama ayarları';

  @override
  String get prayerSettingsDefault => 'Standart ikindi · elle düzeltme yok';

  @override
  String get prayerAdjustedTimes => 'vakit düzeltildi';

  @override
  String get savedOnDevice => 'Bu cihaza kaydedildi';

  @override
  String get prayerSettingsSyncPending =>
      'Ayarlar çevrimdışı çalışır ve ağ geri geldiğinde hesabınızla eşitlenir.';

  @override
  String get asrCalculation => 'İkindi hesabı';

  @override
  String get asrStandard => 'Standart';

  @override
  String get asrHanafi => 'Hanefi';

  @override
  String get asrStandardHint =>
      'Şafii, Maliki ve Hanbeli mezheplerinde kullanılan gölge katsayısı 1.';

  @override
  String get asrHanafiHint => 'Hanefi mezhebinde kullanılan gölge katsayısı 2.';

  @override
  String get manualPrayerAdjustments => 'Elle vakit düzeltmeleri';

  @override
  String get manualPrayerAdjustmentsHint =>
      'Yalnızca güvendiğiniz yerel takvimle eşleştirmek için dakika ekleyin veya çıkarın.';

  @override
  String get advancedCalculationRules => 'Gelişmiş kurallar';

  @override
  String get highLatitudeRule => 'Yüksek enlem kuralı';

  @override
  String get polarResolution => 'Kutup dairesi işleme';

  @override
  String get middleOfNight => 'Gecenin ortası';

  @override
  String get seventhOfNight => 'Gecenin yedide biri';

  @override
  String get twilightAngle => 'Alacakaranlık açısı';

  @override
  String get noPolarSubstitution => 'Değiştirme yok';

  @override
  String get nearestLatitude => 'En yakın enlem';

  @override
  String get nearestDay => 'En yakın gün';

  @override
  String get sunrise => 'Güneş';

  @override
  String get decrease => 'Azalt';

  @override
  String get increase => 'Artır';

  @override
  String get currentLocation => 'Geçerli konum';

  @override
  String get locationNotSelected => 'Konum seçilmedi';

  @override
  String get cityFallbackHint => 'Cihaz konumunu kullanın veya şehir seçin';

  @override
  String get chooseCity => 'Şehir seç';

  @override
  String get chooseCityInstead => 'Bunun yerine şehir seç';

  @override
  String get cityFallbackDescription =>
      'Şehir, kesin konum kullanılamadığında cihazda saklanan özel bir yedek seçenektir.';

  @override
  String get searchCity => 'Şehir ara';

  @override
  String get cityNotFound => 'Eşleşen şehir yok';

  @override
  String get qibla => 'Kıble';

  @override
  String get qiblaDirection => 'Kıble yönü';

  @override
  String get fromGeographicNorth => 'coğrafi kuzeyden';

  @override
  String get qiblaNorthHint =>
      'Bu canlı pusula değil, coğrafi bir açıdır. Oku izlemeden önce telefonun üstünü kuzeye hizalayın.';

  @override
  String get prayerCalendar => 'Aylık namaz takvimi';

  @override
  String get prayerCalendarHint =>
      'Seçilen ayın tüm vakitleri çevrimdışı kullanılabilir';

  @override
  String get prayerCalendarUnavailable => 'Bu ay hesaplanamadı';

  @override
  String get prayerCalendarNeedsLocation =>
      'Önce namaz ekranında bir konum seçin';

  @override
  String get previousMonth => 'Önceki ay';

  @override
  String get nextMonth => 'Sonraki ay';

  @override
  String get prayerWidget => 'Namaz vakitleri widget\'ı';

  @override
  String get prayerWidgetHint =>
      'Sıradaki namaz ve beş vakit ana ekranınızda, internet olmadan da görünür';

  @override
  String get addPrayerWidget => 'Widget ekle';

  @override
  String get homeWidgetAlreadyAdded =>
      'Widget zaten eklenmiş. Verileri güncellendi.';

  @override
  String get prayerWidgetPinRequested =>
      'IQRO widget\'ı için ana ekranınızda bir yer seçin';

  @override
  String get prayerWidgetManualAndroid =>
      'Ana ekranda boş bir alana dokunup basılı tutun, Widget\'ları açın ve IQRO\'yu seçin.';

  @override
  String get prayerWidgetManualIos =>
      'Ana ekrana dokunup basılı tutun, + düğmesine dokunun, IQRO\'yu bulun ve widget\'ı ekleyin.';

  @override
  String get prayerWidgetNeedsLocation =>
      'Önce bir konum seçip namaz vakitlerini hesaplayın';

  @override
  String get prayerLocationPrivacy =>
      'Koordinatlarınız bu cihazda kalır ve analitiğe eklenmez.';

  @override
  String get useMyLocation => 'Konumumu kullan';

  @override
  String get locationDenied =>
      'Konum erişimi kapalı. Cihaz ayarlarından açabilirsiniz.';

  @override
  String get locationServicesDisabled => 'Telefonda konum kapalı';

  @override
  String get locationServicesDisabledBody =>
      'Konum hizmetlerini açıp IQRO\'ya dönün; namaz vakitleri otomatik olarak hesaplanacaktır.';

  @override
  String get locationPermissionRequired => 'Konum erişimi gerekli';

  @override
  String get locationPermissionRequiredBody =>
      'Namaz vakitlerini hesaplamak için bir kez izin verin. Koordinatlar bu cihazda kalır.';

  @override
  String get locationUnavailable => 'Konum belirlenemedi';

  @override
  String get prayerCalculationFailed =>
      'Namaz vakitleri hesaplanamadı. Hesaplama yöntemini kontrol edip tekrar deneyin.';

  @override
  String get prayerUnavailable => 'Namaz vakitleri henüz hesaplanmadı';

  @override
  String get fajr => 'İmsak';

  @override
  String get dhuhr => 'Öğle';

  @override
  String get asr => 'İkindi';

  @override
  String get maghrib => 'Akşam';

  @override
  String get isha => 'Yatsı';

  @override
  String get memorizationTitle => 'Ezber çalışması';

  @override
  String get memorizationCreatePlan => 'Ezber planı oluştur';

  @override
  String get memorizationEditPlan => 'Planı düzenle';

  @override
  String get memorizationPlanDescription =>
      'Sureyi, ayet aralığını, günlük hedefi, bekleme süresini ve okuyuşu seçin. Plan hesabınızla eşitlenir.';

  @override
  String get memorizationDailyRepetitions => 'Günlük tekrar';

  @override
  String get memorizationPauseSeconds => 'Tekrarlar arası bekleme, sn.';

  @override
  String get memorizationReciter => 'Çalışma kârisi';

  @override
  String get memorizationWithoutAudio => 'Ses olmadan';

  @override
  String get memorizationSavePlan => 'Planı kaydet';

  @override
  String get memorizationPlanSaved => 'Ezber planı kaydedildi';

  @override
  String get memorizationRangeInvalid =>
      'Ayet aralığının başlangıç ve bitişini kontrol edin';

  @override
  String get memorizationTodayCompleted => 'Bugünün hedefi tamamlandı';

  @override
  String get memorizationRemaining => 'Kalan tekrar';

  @override
  String get repetitionTarget => 'Tekrar';

  @override
  String get again => 'Tekrar';

  @override
  String get hard => 'Zor';

  @override
  String get good => 'İyi';

  @override
  String get resetToday => 'Bugünü sıfırla';

  @override
  String get resetConfirm => 'Yalnızca bugünkü tekrar sonucu silinsin mi?';

  @override
  String get dua => 'Dua';

  @override
  String get duaSubtitle => 'Kaynağı izlenebilir dua ve zikirler';

  @override
  String duaCount(int count) {
    return '$count dua';
  }

  @override
  String get noDuaCategories => 'Henüz dua kategorisi yok';

  @override
  String get noDuaFound => 'Eşleşen dua bulunamadı';

  @override
  String get duaSearchMinCharacters => 'Aramak için en az 2 karakter girin';

  @override
  String get duaUnavailable => 'Bu dua kullanılamıyor';

  @override
  String get cachedDuaWarning =>
      'Kaydedilmiş bir kopya gösteriliyor. Güncel sürüm doğrulandıktan sonra ses kullanılabilir.';

  @override
  String get duaAudio => 'Dua sesi';

  @override
  String get duaAudioStreaming => 'Dinlemek için internet bağlantısı gerekir';

  @override
  String get duaAudioFailed => 'Ses oynatılamadı';

  @override
  String get duaPractice => 'Tekrar pratiği';

  @override
  String get duaPracticeHint =>
      'Her okumadan sonra dokunun. Bu sayaç yalnızca bu ekranda tutulur.';

  @override
  String get reset => 'Sıfırla';

  @override
  String get sourceAndVerification => 'Kaynak ve doğrulama';

  @override
  String get sourceDeclared => 'Kaynak belirtildi';

  @override
  String get sourceUnavailable => 'Kaynak bilgileri kullanılamıyor';

  @override
  String get editoriallyVerified => 'Editöryal olarak doğrulandı';

  @override
  String get copyText => 'Metni kopyala';

  @override
  String get textCopied => 'Metin kopyalandı';

  @override
  String get shareDua => 'Duayı paylaş';

  @override
  String get duaReader => 'Okuyucu';

  @override
  String get practiceStage => 'Aşama';

  @override
  String get markRepetition => 'Tekrarı say';

  @override
  String get author => 'Yazar';

  @override
  String get translator => 'Çevirmen';

  @override
  String get reviewer => 'Editör';

  @override
  String get sourceVersion => 'Kaynak sürümü';

  @override
  String get sourceReference => 'Referans';

  @override
  String get grade => 'Derece';

  @override
  String get rights => 'Kullanım koşulları';

  @override
  String get favorites => 'Favoriler';

  @override
  String get all => 'Tümü';

  @override
  String get emptyFavorites => 'Bir ayet veya duayı kaydedin; burada görünsün.';

  @override
  String get account => 'Hesap';

  @override
  String get personalProfile => 'Kişisel profil';

  @override
  String get signIn => 'Giriş yap';

  @override
  String get email => 'E-posta';

  @override
  String get verificationCode => 'Doğrulama kodu';

  @override
  String get sendCode => 'Kodu gönder';

  @override
  String get verify => 'Doğrula';

  @override
  String get signOut => 'Çıkış yap';

  @override
  String get devices => 'Cihazlar';

  @override
  String get syncNow => 'Şimdi eşitle';

  @override
  String get syncHint =>
      'Yerel değişiklikleri gönderin ve diğer cihazlardan güncellemeleri alın.';

  @override
  String get language => 'Dil';

  @override
  String get theme => 'Tema';

  @override
  String get systemTheme => 'Sistem';

  @override
  String get lightTheme => 'Açık';

  @override
  String get darkTheme => 'Koyu';

  @override
  String get shareApp => 'IQRO\'yu paylaş';

  @override
  String get shareTitle => 'Sevdiklerinizi IQRO\'ya davet edin';

  @override
  String get shareBody =>
      'Kur\'an\'ı okumak ve dinlemek için huzurlu bir yolu paylaşın.';

  @override
  String get shareButton => 'Uygulamayı paylaş';

  @override
  String get copyLink => 'Bağlantıyı kopyala';

  @override
  String get linkCopied => 'Bağlantı kopyalandı';

  @override
  String get referralSummary => 'Davetleriniz';

  @override
  String get invited => 'Davet edilen';

  @override
  String get qualified => 'Onaylanan';

  @override
  String get rewardBalance => 'Ödül bakiyesi';

  @override
  String get referralRequiresAccount =>
      'Kişisel davet bağlantısı e-posta doğrulamasından sonra açılır.';

  @override
  String get remoteCopy => 'Kampanya metni IQRO tarafından yönetiliyor';

  @override
  String get bundledCopy => 'Yerleşik paylaşım metni kullanılıyor';

  @override
  String get networkError => 'IQRO\'ya ulaşılamadı';

  @override
  String get sessionExpired =>
      'Oturumunuz sona erdi. Çevrimdışı çalışmalarınız güvende.';

  @override
  String get syncConflict => 'Diğer cihazınızda daha yeni ilerleme var.';

  @override
  String get loading => 'Yükleniyor…';

  @override
  String get offline => 'Çevrimdışı';

  @override
  String get offlineMushaf => 'Çevrimdışı Mushaf';

  @override
  String get offlineMushafDescription =>
      'Tüm sayfaları ve ayet haritasını indirin. Dosyalar etkinleştirilmeden önce doğrulanır.';

  @override
  String get downloadForOffline => 'İndir';

  @override
  String get mushafDownloading => 'Mushaf indiriliyor';

  @override
  String get mushafAvailableOffline => 'Çevrimdışı kullanılabilir';

  @override
  String get mushafDownloadFailed =>
      'İndirme durdu. Kaydedilen yerden devam edebilirsiniz.';

  @override
  String get resumeDownload => 'Devam et';

  @override
  String get offlineAudio => 'Çevrimdışı ses';

  @override
  String get offlineAudioDescription =>
      'Bu kıraatin 114 sûresinin tamamını indirin. Her dosya etkinleştirilmeden önce doğrulanır.';

  @override
  String get audioDownloading => 'Ses indiriliyor';

  @override
  String get audioAvailableOffline => 'Ses çevrimdışı kullanılabilir';

  @override
  String get audioDownloadFailed =>
      'Ses indirme durdu. Kaydedilen yerden devam edebilirsiniz.';

  @override
  String get audioOfflineUnavailable =>
      'Bu kayıt çevrimdışı indirme için lisanslı değil.';

  @override
  String get offlineStorage => 'Çevrimdışı depolama';

  @override
  String get offlineStorageSettingsSubtitle =>
      'İndirilen Mushaf sayfaları ve sesler';

  @override
  String offlineStorageUsed(String size) {
    return 'Çevrimdışı kullanılan: $size';
  }

  @override
  String get offlineStorageDescription =>
      'Burada yalnızca uygulamanın indirdiği dosyalar gösterilir. Hiçbir şey otomatik olarak silinmez.';

  @override
  String offlineStorageQuota(String size) {
    return 'Uygulama sınırı: $size';
  }

  @override
  String get offlineStorageQuotaExceeded =>
      'Bu paket çevrimdışı depolama sınırına sığmıyor. Önce gereksiz bir paketi silin.';

  @override
  String downloadOfflineConfirmation(String size) {
    return 'Tam paket yaklaşık $size kullanacak. İndirme başlatılsın mı?';
  }

  @override
  String get downloadedContent => 'İndirilen içerik';

  @override
  String get noOfflinePackages => 'Henüz çevrimdışı paket indirilmedi.';

  @override
  String get storageReadFailed => 'Çevrimdışı depolama okunamadı';

  @override
  String get tryAgain => 'Lütfen tekrar deneyin.';

  @override
  String get refresh => 'Yenile';

  @override
  String get deleteOfflinePackage => 'Çevrimdışı paketi sil';

  @override
  String deleteOfflinePackageConfirmation(String name, String size) {
    return '“$name” ($size) bu cihazdan silinsin mi? Çevrimdışı kullanım için tekrar indirmeniz gerekir.';
  }

  @override
  String deletePlayingAudioConfirmation(String name, String size) {
    return '“$name” şu anda çalıyor. Oynatıcı durdurulup çevrimdışı paket ($size) bu cihazdan silinsin mi?';
  }

  @override
  String get offlinePackageDeleted => 'Çevrimdışı paket silindi';

  @override
  String get offlinePackageDeleteFailed => 'Çevrimdışı paket silinemedi';

  @override
  String packageTotalSize(String size) {
    return 'tam boyut $size';
  }

  @override
  String get completeMushafPages => 'Eksiksiz Mushaf sayfaları';

  @override
  String get completeRecitation => 'Eksiksiz Kur\'an tilaveti';

  @override
  String get downloadInProgress => 'İndirme sürüyor';

  @override
  String get downloadFailed => 'İndirme kesildi';

  @override
  String get notReady => 'Hazır değil';

  @override
  String get availableOffline => 'Çevrimdışı kullanılabilir';

  @override
  String get moreTools => 'Pratik ve araçlar';

  @override
  String get books => 'Kitaplar';

  @override
  String get quizzes => 'Testler';

  @override
  String get support => 'Destek';

  @override
  String get privacy => 'Gizlilik';

  @override
  String get reminders => 'Hatırlatıcılar';

  @override
  String get remindersSubtitle => 'Namaz ve Kur’an tekrarı';

  @override
  String get notificationAccess => 'Bildirimlere izin verin';

  @override
  String get notificationAccessBody =>
      'IQRO, uygulama kapalıyken bile seçtiğiniz saatte hatırlatır.';

  @override
  String get allowNotifications => 'Bildirimlere izin ver';

  @override
  String get notificationDenied => 'Bildirimler cihaz ayarlarında kapalı.';

  @override
  String get approximateDelivery =>
      'Pil tasarrufu için sistem bildirimleri kısa bir gecikmeyle iletebilir.';

  @override
  String get prayerReminders => 'Namaz hatırlatıcıları';

  @override
  String get prayerReminderSetup =>
      'Önce Namaz vakitleri bölümünde hesaplama yöntemini ve konumu ayarlayın.';

  @override
  String get quranReviewReminders => 'Kur’an tekrarı';

  @override
  String get addReminder => 'Hatırlatıcı ekle';

  @override
  String get noReminders => 'Henüz tekrar hatırlatıcısı yok.';

  @override
  String get reviewReminder => 'Ayet tekrarı';

  @override
  String get reminderTime => 'Saat';

  @override
  String get reminderDays => 'Günler';

  @override
  String get everyDay => 'Her gün';

  @override
  String get signal => 'Uyarı';

  @override
  String get sound => 'Sesli';

  @override
  String get vibration => 'Titreşim';

  @override
  String get silent => 'Sessiz';

  @override
  String get timezone => 'Saat dilimi';

  @override
  String get deviceTimezone => 'Cihaz saat dilimi';

  @override
  String get fixedTimezone => 'Sabit';

  @override
  String get timezoneName => 'IANA saat dilimi';

  @override
  String get startAyah => 'İlk ayet';

  @override
  String get endAyah => 'Son ayet';

  @override
  String get delete => 'Sil';

  @override
  String get deleteReminderConfirm => 'Bu hatırlatıcı silinsin mi?';

  @override
  String get reminderSaved => 'Hatırlatıcı kaydedildi';

  @override
  String get mondayShort => 'Pzt';

  @override
  String get tuesdayShort => 'Sal';

  @override
  String get wednesdayShort => 'Çar';

  @override
  String get thursdayShort => 'Per';

  @override
  String get fridayShort => 'Cum';

  @override
  String get saturdayShort => 'Cmt';

  @override
  String get sundayShort => 'Paz';

  @override
  String get readerHaptics => 'Sayfa çevirme titreşimi';

  @override
  String get readerHapticsHint =>
      'Mushaf sayfası değiştiğinde kısa titreşim. Android dokunma titreşimi de açık olmalıdır.';

  @override
  String get mushafPageCaching =>
      'Sayfalar okudukça yüklenir. Açılan sayfalar ve yazı tipleri cihazda saklanır ve çevrimdışı kullanılabilir.';

  @override
  String get planCreditedToday => 'Bugün kaydedilen';

  @override
  String get planGoalLabel => 'Günlük hedef';

  @override
  String get planEditGoal => 'Hedefi değiştir';

  @override
  String get planGoalReached => 'Günlük hedefe ulaşıldı';

  @override
  String planRemainingAmount(String amount) {
    return 'Hedefe kalan: $amount';
  }

  @override
  String planGoalAmount(String amount) {
    return 'Hedef: $amount';
  }

  @override
  String planCreditedAmount(String amount) {
    return 'Kaydedilen: $amount';
  }

  @override
  String get planManualEntry => 'Okumayı elle ekle';

  @override
  String get planManualHelp =>
      'Henüz sayılmamış okumayı ekleyin. Bu, günlük hedefinizi değil bugünkü ilerlemenizi artırır.';

  @override
  String get planHowCounted => 'İlerleme nasıl hesaplanır';

  @override
  String get planPagesHelp =>
      'Okuyucuda sonraki sayfaya geçmek otomatik olarak bir sayfa ekler. Elle girilen kayıtlar da sayılır. Sayfa çevirmek, sayfayı okuduğunuzu doğrulamaz.';

  @override
  String get planMinutesHelp =>
      'Okuyucuda etkin geçirilen süre otomatik sayılır. Elle eklenen dakikalar da ilerlemeye dahildir.';

  @override
  String get planAyahsHelp =>
      'Okuyucuda ayetler arasında sırayla ilerlemek otomatik sayılır. Elle eklenen ayetler de ilerlemeye dahildir.';

  @override
  String get planDailyHelp =>
      'İlerleme her gün ayrı hesaplanır. Hedefi değiştirmek ilerlemeyi sıfırlamaz; önceki günler geçmişte kalır.';

  @override
  String get planResetHelp =>
      'Namaz sonrası kayıtları − düğmesiyle azaltabilirsiniz. Bu ekranda bugünkü tüm ilerleme sıfırlanamaz.';

  @override
  String get planPrayerTitle => 'Namaz sonrası okuma';

  @override
  String get planPrayerSummary =>
      'Bugün işaretlediğiniz sayfalar. Bunlar hedef değil, tamamlanan okuma kayıtlarıdır.';

  @override
  String get planEditPrayer => 'Bugünkü kayıtları düzenle';

  @override
  String get planPrayerInstructions =>
      'Her namazdan sonra okuduğunuz sayfaları işaretleyin. + bir sayfa ekler, − bir sayfa çıkarır. Sıfır, kayıt olmadığını gösterir.';

  @override
  String planRemovePage(String prayer) {
    return 'Bir sayfa çıkar: $prayer';
  }

  @override
  String planAddPage(String prayer) {
    return 'Bir sayfa ekle: $prayer';
  }

  @override
  String get planUnavailable =>
      'Plan güncellenemedi. Kayıtlı ilerleme gösteriliyor; başarılı güncellemeden sonra değişiklik yapabilirsiniz.';

  @override
  String get planGoalHint =>
      'Günlük hedefinizi dakika, sayfa veya ayet olarak seçin. Bu, hedef belirler; tamamlanan okumayı kaydetmez.';

  @override
  String planBestStreak(String streak) {
    return 'En uzun seri: $streak';
  }

  @override
  String planActiveTime(String amount) {
    return 'Etkin okuma: $amount';
  }

  @override
  String planPages(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString sayfa';
  }

  @override
  String planMinutes(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString dakika';
  }

  @override
  String planAyahs(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return '$countString ayet';
  }

  @override
  String planStreak(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    return 'Üst üste $countString gün';
  }
}

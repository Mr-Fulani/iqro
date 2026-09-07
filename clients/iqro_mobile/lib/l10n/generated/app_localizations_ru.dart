// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String get hijriCalendar => 'Календарь Хиджры';

  @override
  String get hijriMethod => 'Умм аль-Кура · офлайн';

  @override
  String get hijriDisclaimer =>
      'Расчётные даты могут отличаться от местного наблюдения луны. Начало Рамадана и праздников уточняйте в своей общине. Исламский день начинается с заходом солнца предыдущего гражданского дня.';

  @override
  String get hijriAdjustment => 'Поправка даты';

  @override
  String get hijriAdjustmentHint =>
      'Настройте дату по календарю вашей общины. Поправка применяется ко всему календарю.';

  @override
  String get hijriSources => 'Основания и источники';

  @override
  String get hijriNoEvents => 'Для этого дня нет специальных отметок.';

  @override
  String get hijriUnavailable =>
      'Дата вне поддерживаемого календаря (1937–2077).';

  @override
  String get hijriToday => 'Сегодня по Хиджре';

  @override
  String get hijriCivilDate => 'Гражданская дата';

  @override
  String get hijriSunsetDate => 'Дата с учётом местного магриба';

  @override
  String get hijriCivilHint =>
      'Без текущего времени магриба показана дата гражданского дня.';

  @override
  String get hijriYearSuffix => 'г. х.';

  @override
  String get hijriEventHint =>
      'Это справочные отметки, а не отдельная фетва. Пост в праздничные дни не отмечается как желательный; день Арафа указан с учётом того, что для паломников действуют отдельные положения.';

  @override
  String get appLicenses => 'Лицензии компонентов';

  @override
  String hijriMonthName(String month) {
    String _temp0 = intl.Intl.selectLogic(month, {
      'm1': 'Мухаррам',
      'm2': 'Сафар',
      'm3': 'Раби аль-авваль',
      'm4': 'Раби ас-сани',
      'm5': 'Джумада аль-уля',
      'm6': 'Джумада ас-сания',
      'm7': 'Раджаб',
      'm8': 'Шаабан',
      'm9': 'Рамадан',
      'm10': 'Шавваль',
      'm11': 'Зуль-каада',
      'm12': 'Зуль-хиджа',
      'other': 'Хиджра',
    });
    return '$_temp0';
  }

  @override
  String hijriEventName(String event) {
    String _temp0 = intl.Intl.selectLogic(event, {
      'ramadan': 'Рамадан',
      'eidFitr': 'Ид аль-Фитр · Ураза-байрам',
      'arafah': 'День Арафа',
      'eidAdha': 'Ид аль-Адха · Курбан-байрам',
      'tashriq': 'Дни ташрика',
      'ashura': 'Ашура',
      'whiteDays': 'Белые дни · 13–15',
      'lastTenNights': 'Последние десять ночей Рамадана',
      'other': 'Памятная дата',
    });
    return '$_temp0';
  }

  @override
  String get appName => 'IQRO';

  @override
  String get navHome => 'Главная';

  @override
  String get navQuran => 'Коран';

  @override
  String get navPlan => 'План';

  @override
  String get navAudio => 'Аудио';

  @override
  String get navMore => 'Ещё';

  @override
  String get back => 'Назад';

  @override
  String get open => 'Открыть';

  @override
  String get save => 'Сохранить';

  @override
  String get cancel => 'Отмена';

  @override
  String get close => 'Закрыть';

  @override
  String get retry => 'Повторить';

  @override
  String get continueLabel => 'Продолжить';

  @override
  String get done => 'Готово';

  @override
  String get soon => 'Скоро';

  @override
  String get search => 'Поиск';

  @override
  String get settings => 'Настройки';

  @override
  String get welcomeTitle => 'Спокойная ежедневная практика';

  @override
  String get welcomeBody =>
      'Читайте, слушайте и сохраняйте свой ритм в одном приватном приложении.';

  @override
  String get chooseLanguage => 'Выберите язык';

  @override
  String get chooseGoal => 'На чём хотите сосредоточиться?';

  @override
  String get goalReading => 'Ежедневное чтение';

  @override
  String get goalMemorization => 'Заучивание';

  @override
  String get goalPrayer => 'Поддержка намаза';

  @override
  String get goalDua => 'Ду’а';

  @override
  String get dailyNorm => 'Выберите комфортную дневную норму';

  @override
  String get minutes => 'минут';

  @override
  String get pages => 'страниц';

  @override
  String get ayahs => 'аятов';

  @override
  String get startAsGuest => 'Начать приватно';

  @override
  String get guestNote =>
      'Прогресс начнёт сохраняться на этом устройстве. Аккаунт можно подключить позже.';

  @override
  String get greeting => 'Ас-саляму алейкум';

  @override
  String get continueReading => 'Продолжить чтение';

  @override
  String get read => 'Читать';

  @override
  String get savedAutomatically => 'Место сохранено автоматически';

  @override
  String get nextPrayer => 'Следующая молитва';

  @override
  String get yourRhythm => 'Ваш ритм';

  @override
  String get today => 'Сегодня';

  @override
  String get openPlan => 'Открыть план';

  @override
  String get calmPace => 'Спокойный темп';

  @override
  String get afterPrayer => 'После намаза';

  @override
  String get memorization => 'Заучивание';

  @override
  String get recentReciter => 'Недавний чтец';

  @override
  String get duaOfDay => 'Ду’а дня';

  @override
  String get readingAsGuest => 'Читаете как гость';

  @override
  String get guestSyncHint => 'Войдите, чтобы продолжить на другом устройстве';

  @override
  String get quranSubtitle => 'Мадинский Мусхаф · Хафс';

  @override
  String get alFatiha => 'Аль-Фатиха';

  @override
  String get textMode => 'Текст';

  @override
  String get mushafMode => 'Мусхаф';

  @override
  String get selectedMushaf => 'Выбранный Мусхаф';

  @override
  String get chooseMushaf => 'Выберите Мусхаф';

  @override
  String get mushafScanName => 'Мадинский Мусхаф';

  @override
  String get mushafScanDescription => 'Оригинальные страницы · Хафс';

  @override
  String get mushafTextDescription => 'Чёткий текст, адаптированный для экрана';

  @override
  String get mushafWebOnly => 'Этот шрифт пока доступен только в веб-версии';

  @override
  String get mushafUnavailable => 'Вариант временно недоступен у источника';

  @override
  String get mushafCachedDescription =>
      'Загружается при первом открытии · далее доступен без сети';

  @override
  String get mushafLoading => 'Загружаем страницу и официальный шрифт…';

  @override
  String get mushafFontError =>
      'Официальный шрифт не удалось открыть. Повторите при подключении к интернету.';

  @override
  String get mushafOfflineMissing =>
      'Эта страница ещё не сохранена на устройстве. Подключитесь к интернету и повторите.';

  @override
  String get continueSaved => 'Продолжить с сохранённого места';

  @override
  String get surahs => 'Суры';

  @override
  String get juz => 'Джуз';

  @override
  String get hizb => 'Хизб';

  @override
  String get rubElHizb => 'Руб аль-хизб';

  @override
  String get page => 'Страница';

  @override
  String get surah => 'Сура';

  @override
  String get ayah => 'Аят';

  @override
  String get quickJump => 'Быстрый переход';

  @override
  String get navigation => 'Навигация';

  @override
  String get meccan => 'Мекканская';

  @override
  String get medinan => 'Мединская';

  @override
  String get noQuranData => 'Каталог Корана недоступен';

  @override
  String get offlineUsingCache => 'Нет сети — показываем сохранённые данные';

  @override
  String get readerSettings => 'Настройки чтения';

  @override
  String get textAppearance => 'Оформление текста';

  @override
  String get arabicTextSize => 'Размер арабского текста';

  @override
  String get lineSpacing => 'Межстрочный интервал';

  @override
  String get ayahSpacing => 'Интервал между аятами';

  @override
  String get focusMode => 'Режим без отвлечений';

  @override
  String get focusModeDescription =>
      'Скрыть верхнюю панель и служебные подсказки';

  @override
  String get exitFocusMode => 'Выйти из режима без отвлечений';

  @override
  String get translation => 'Перевод';

  @override
  String get tafsir => 'Тафсир';

  @override
  String get loadOnDemand => 'Загружать по запросу';

  @override
  String get translationUnavailable =>
      'Для этого языка пока не подключён одобренный перевод.';

  @override
  String get tafsirUnavailable =>
      'Тафсир появится после выбора одобренной редакции.';

  @override
  String get bookmarkAdded => 'Добавлено в избранное';

  @override
  String get bookmarkRemoved => 'Закладка удалена';

  @override
  String get listen => 'Слушать';

  @override
  String get tapForControls => 'Касание — плеер и меню';

  @override
  String get zoom => 'Масштаб';

  @override
  String get listenPage => 'Прослушать текущую страницу';

  @override
  String get tapAyahForDetails => 'Удерживайте аят для перевода и тафсира';

  @override
  String get audioTitle => 'Слушайте Коран';

  @override
  String get chooseReciter => 'Выберите чтеца';

  @override
  String get allReciters => 'Все чтецы';

  @override
  String get recitationStyle => 'Стиль чтения';

  @override
  String get chooseRecitationStyle => 'Выберите стиль чтения';

  @override
  String get styleMurattal => 'Мурратталь';

  @override
  String get styleMujawwad => 'Муджаввад';

  @override
  String get styleMuallim => 'Муаллим';

  @override
  String get refreshReciters => 'Обновить каталог чтецов';

  @override
  String get recitersUpdated => 'Каталог чтецов обновлён';

  @override
  String get recitersRefreshFailed =>
      'Не удалось обновить каталог. Показаны сохранённые данные.';

  @override
  String get noAudio => 'Нет доступной аудиозаписи';

  @override
  String get nowPlaying => 'Сейчас играет';

  @override
  String get play => 'Воспроизвести';

  @override
  String get pause => 'Пауза';

  @override
  String get previousSurah => 'Предыдущая сура';

  @override
  String get nextSurah => 'Следующая сура';

  @override
  String get chooseSurah => 'Выбрать суру';

  @override
  String get speed => 'Скорость';

  @override
  String get audioQuality => 'Качество аудио';

  @override
  String get qualityAutomatic => 'Автоматически';

  @override
  String get qualityEconomy => 'Экономия трафика';

  @override
  String get qualityStandard => 'Стандартное';

  @override
  String get qualityHigh => 'Высокое';

  @override
  String audioBitrate(int bitrate) {
    return '$bitrate кбит/с';
  }

  @override
  String get range => 'Диапазон';

  @override
  String get sleepTimer => 'Таймер сна';

  @override
  String get repeat => 'Повтор';

  @override
  String get repeatOff => 'Повтор выключен';

  @override
  String get repeatOn => 'Повтор включён';

  @override
  String get off => 'Выключено';

  @override
  String get backgroundPlayback => 'Фоновое воспроизведение и экран блокировки';

  @override
  String get dailyPlan => 'План на день';

  @override
  String get dailyGoal => 'Дневная цель';

  @override
  String get completed => 'Выполнено';

  @override
  String get remaining => 'Осталось';

  @override
  String get history => 'История';

  @override
  String get manualEntry => 'Добавить чтение';

  @override
  String get addPages => 'Добавить страницы';

  @override
  String get afterPrayerPlan => 'План после намаза';

  @override
  String get prayer => 'Время намаза';

  @override
  String get calculationMethod => 'Метод расчёта';

  @override
  String get prayerCalculationSettings => 'Настройки расчёта намаза';

  @override
  String get prayerSettingsDefault => 'Стандартный Аср · без ручных поправок';

  @override
  String get prayerAdjustedTimes => 'времён с поправкой';

  @override
  String get savedOnDevice => 'Сохранено на устройстве';

  @override
  String get prayerSettingsSyncPending =>
      'Настройки уже работают без сети и синхронизируются с аккаунтом после подключения.';

  @override
  String get asrCalculation => 'Расчёт Асра';

  @override
  String get asrStandard => 'Стандартный';

  @override
  String get asrHanafi => 'Ханафитский';

  @override
  String get asrStandardHint =>
      'Коэффициент тени 1 — используется в шафиитском, маликитском и ханбалитском мазхабах.';

  @override
  String get asrHanafiHint =>
      'Коэффициент тени 2 — используется в ханафитском мазхабе.';

  @override
  String get manualPrayerAdjustments => 'Ручные поправки времени';

  @override
  String get manualPrayerAdjustmentsHint =>
      'Добавляйте или вычитайте минуты только для соответствия доверенному местному расписанию.';

  @override
  String get advancedCalculationRules => 'Расширенные правила';

  @override
  String get highLatitudeRule => 'Правило высоких широт';

  @override
  String get polarResolution => 'Расчёт за полярным кругом';

  @override
  String get middleOfNight => 'Середина ночи';

  @override
  String get seventhOfNight => 'Седьмая часть ночи';

  @override
  String get twilightAngle => 'Угол сумерек';

  @override
  String get noPolarSubstitution => 'Без замещения';

  @override
  String get nearestLatitude => 'Ближайшая широта';

  @override
  String get nearestDay => 'Ближайший день';

  @override
  String get sunrise => 'Восход';

  @override
  String get decrease => 'Уменьшить';

  @override
  String get increase => 'Увеличить';

  @override
  String get currentLocation => 'Текущее местоположение';

  @override
  String get locationNotSelected => 'Местоположение не выбрано';

  @override
  String get cityFallbackHint => 'Используйте геолокацию или выберите город';

  @override
  String get chooseCity => 'Выбрать город';

  @override
  String get chooseCityInstead => 'Выбрать город вместо геолокации';

  @override
  String get cityFallbackDescription =>
      'Город — приватный запасной вариант на устройстве, когда точная геолокация недоступна.';

  @override
  String get searchCity => 'Поиск города';

  @override
  String get cityNotFound => 'Подходящий город не найден';

  @override
  String get qibla => 'Кибла';

  @override
  String get qiblaDirection => 'Направление Киблы';

  @override
  String get fromGeographicNorth => 'от географического севера';

  @override
  String get qiblaNorthHint =>
      'Это географическое направление, а не живой компас. Сначала совместите верх телефона с севером, затем следуйте стрелке.';

  @override
  String get prayerCalendar => 'Календарь намаза на месяц';

  @override
  String get prayerCalendarHint =>
      'Все времена на выбранный месяц, доступны без интернета';

  @override
  String get prayerCalendarUnavailable =>
      'Не удалось рассчитать выбранный месяц';

  @override
  String get prayerCalendarNeedsLocation =>
      'Сначала выберите местоположение на экране намаза';

  @override
  String get previousMonth => 'Предыдущий месяц';

  @override
  String get nextMonth => 'Следующий месяц';

  @override
  String get prayerWidget => 'Виджет времени намаза';

  @override
  String get prayerWidgetHint =>
      'Ближайшая молитва и пять времён на главном экране, даже без интернета';

  @override
  String get addPrayerWidget => 'Добавить виджет';

  @override
  String get prayerWidgetPinRequested =>
      'Выберите место для виджета IQRO на главном экране';

  @override
  String get prayerWidgetManualAndroid =>
      'Нажмите и удерживайте свободное место на главном экране, откройте «Виджеты» и выберите IQRO.';

  @override
  String get prayerWidgetManualIos =>
      'Нажмите и удерживайте главный экран, нажмите «+», найдите IQRO и добавьте виджет.';

  @override
  String get prayerWidgetNeedsLocation =>
      'Сначала выберите местоположение и рассчитайте время намаза';

  @override
  String get prayerLocationPrivacy =>
      'Координаты остаются на устройстве и никогда не попадают в аналитику.';

  @override
  String get useMyLocation => 'Использовать моё местоположение';

  @override
  String get locationDenied =>
      'Доступ к геолокации выключен. Его можно включить в настройках устройства.';

  @override
  String get locationServicesDisabled => 'Геолокация на телефоне выключена';

  @override
  String get locationServicesDisabledBody =>
      'Включите геолокацию и вернитесь в IQRO — расчёт продолжится автоматически.';

  @override
  String get locationPermissionRequired => 'Нужен доступ к местоположению';

  @override
  String get locationPermissionRequiredBody =>
      'Разрешите доступ для расчёта времени намаза. Координаты останутся на этом устройстве.';

  @override
  String get locationUnavailable => 'Не удалось определить местоположение';

  @override
  String get prayerCalculationFailed =>
      'Не удалось рассчитать время намаза. Проверьте метод расчёта и повторите.';

  @override
  String get prayerUnavailable => 'Время намаза ещё не рассчитано';

  @override
  String get fajr => 'Фаджр';

  @override
  String get dhuhr => 'Зухр';

  @override
  String get asr => 'Аср';

  @override
  String get maghrib => 'Магриб';

  @override
  String get isha => 'Иша';

  @override
  String get memorizationTitle => 'Практика заучивания';

  @override
  String get memorizationCreatePlan => 'Создать план заучивания';

  @override
  String get memorizationEditPlan => 'Изменить план';

  @override
  String get memorizationPlanDescription =>
      'Выберите суру, диапазон аятов, дневную цель, паузу и чтение. План синхронизируется с вашим аккаунтом.';

  @override
  String get memorizationDailyRepetitions => 'Повторений в день';

  @override
  String get memorizationPauseSeconds => 'Пауза между повторами, сек.';

  @override
  String get memorizationReciter => 'Чтец для повторения';

  @override
  String get memorizationWithoutAudio => 'Без аудио';

  @override
  String get memorizationSavePlan => 'Сохранить план';

  @override
  String get memorizationPlanSaved => 'План заучивания сохранён';

  @override
  String get memorizationRangeInvalid =>
      'Проверьте начало и конец диапазона аятов';

  @override
  String get memorizationTodayCompleted => 'Цель на сегодня выполнена';

  @override
  String get memorizationRemaining => 'Осталось повторений';

  @override
  String get repetitionTarget => 'Повторений';

  @override
  String get again => 'Ещё раз';

  @override
  String get hard => 'Сложно';

  @override
  String get good => 'Хорошо';

  @override
  String get resetToday => 'Сбросить сегодня';

  @override
  String get resetConfirm => 'Очистить только результат повторений за сегодня?';

  @override
  String get dua => 'Ду’а';

  @override
  String get duaSubtitle => 'Ду’а и азкары из проверяемых источников';

  @override
  String duaCount(int count) {
    return 'Ду’а: $count';
  }

  @override
  String get noDuaCategories => 'Категории ду’а пока недоступны';

  @override
  String get noDuaFound => 'Подходящие ду’а не найдены';

  @override
  String get duaSearchMinCharacters => 'Введите минимум 2 символа для поиска';

  @override
  String get duaUnavailable => 'Это ду’а недоступно';

  @override
  String get cachedDuaWarning =>
      'Показана сохранённая копия. Аудио станет доступно после проверки актуальной версии.';

  @override
  String get duaAudio => 'Аудио ду’а';

  @override
  String get duaAudioStreaming =>
      'Для прослушивания нужно подключение к интернету';

  @override
  String get duaAudioFailed => 'Не удалось воспроизвести аудио';

  @override
  String get duaPractice => 'Практика повторения';

  @override
  String get duaPracticeHint =>
      'Нажимайте после каждого прочтения. Счётчик хранится только на этом экране.';

  @override
  String get reset => 'Сбросить';

  @override
  String get sourceAndVerification => 'Источник и проверка';

  @override
  String get sourceDeclared => 'Источник указан';

  @override
  String get sourceUnavailable => 'Сведения об источнике недоступны';

  @override
  String get editoriallyVerified => 'Проверено редакцией';

  @override
  String get copyText => 'Копировать текст';

  @override
  String get textCopied => 'Текст скопирован';

  @override
  String get shareDua => 'Поделиться ду’а';

  @override
  String get duaReader => 'Чтец';

  @override
  String get practiceStage => 'Этап';

  @override
  String get markRepetition => 'Засчитать повтор';

  @override
  String get author => 'Автор';

  @override
  String get translator => 'Переводчик';

  @override
  String get reviewer => 'Редактор';

  @override
  String get sourceVersion => 'Версия источника';

  @override
  String get sourceReference => 'Ссылка на источник';

  @override
  String get grade => 'Оценка';

  @override
  String get rights => 'Условия использования';

  @override
  String get favorites => 'Избранное';

  @override
  String get all => 'Все';

  @override
  String get emptyFavorites => 'Сохраните аят или ду’а, и они появятся здесь.';

  @override
  String get account => 'Аккаунт';

  @override
  String get personalProfile => 'Личный кабинет';

  @override
  String get signIn => 'Войти';

  @override
  String get email => 'Электронная почта';

  @override
  String get verificationCode => 'Код подтверждения';

  @override
  String get sendCode => 'Отправить код';

  @override
  String get verify => 'Подтвердить';

  @override
  String get signOut => 'Выйти';

  @override
  String get devices => 'Устройства';

  @override
  String get syncNow => 'Синхронизировать';

  @override
  String get syncHint =>
      'Отправить локальные изменения и получить обновления с других устройств.';

  @override
  String get language => 'Язык';

  @override
  String get theme => 'Тема';

  @override
  String get systemTheme => 'Системная';

  @override
  String get lightTheme => 'Светлая';

  @override
  String get darkTheme => 'Тёмная';

  @override
  String get shareApp => 'Поделиться IQRO';

  @override
  String get shareTitle => 'Пригласите близких в IQRO';

  @override
  String get shareBody =>
      'Поделитесь спокойным способом читать и слушать Коран.';

  @override
  String get shareButton => 'Поделиться приложением';

  @override
  String get copyLink => 'Копировать ссылку';

  @override
  String get linkCopied => 'Ссылка скопирована';

  @override
  String get referralSummary => 'Ваши приглашения';

  @override
  String get invited => 'Приглашено';

  @override
  String get qualified => 'Подтверждено';

  @override
  String get rewardBalance => 'Баланс бонусов';

  @override
  String get referralRequiresAccount =>
      'Персональная ссылка станет доступна после подтверждения электронной почты.';

  @override
  String get remoteCopy => 'Текст кампании управляется IQRO';

  @override
  String get bundledCopy => 'Используется встроенный текст приложения';

  @override
  String get networkError => 'Не удалось связаться с IQRO';

  @override
  String get sessionExpired => 'Сессия истекла. Офлайн-изменения сохранены.';

  @override
  String get syncConflict => 'На другом устройстве есть более новый прогресс.';

  @override
  String get loading => 'Загрузка…';

  @override
  String get offline => 'Нет сети';

  @override
  String get offlineMushaf => 'Мусхаф без интернета';

  @override
  String get offlineMushafDescription =>
      'Скачайте все страницы и карту аятов. Файлы проверяются перед включением.';

  @override
  String get downloadForOffline => 'Скачать';

  @override
  String get mushafDownloading => 'Скачиваем Мусхаф';

  @override
  String get mushafAvailableOffline => 'Доступен без интернета';

  @override
  String get mushafDownloadFailed =>
      'Загрузка прервана. Можно продолжить с сохранённого места.';

  @override
  String get resumeDownload => 'Продолжить';

  @override
  String get offlineAudio => 'Аудио без интернета';

  @override
  String get offlineAudioDescription =>
      'Скачайте все 114 сур выбранного чтения. Каждый файл проверяется перед включением.';

  @override
  String get audioDownloading => 'Скачиваем аудио';

  @override
  String get audioAvailableOffline => 'Аудио доступно без интернета';

  @override
  String get audioDownloadFailed =>
      'Загрузка аудио прервана. Можно продолжить с сохранённого места.';

  @override
  String get audioOfflineUnavailable =>
      'Для этой записи право на офлайн-загрузку не предоставлено.';

  @override
  String get offlineStorage => 'Офлайн-хранилище';

  @override
  String get offlineStorageSettingsSubtitle =>
      'Скачанные страницы Мусхафа и аудио';

  @override
  String offlineStorageUsed(String size) {
    return 'Занято офлайн: $size';
  }

  @override
  String get offlineStorageDescription =>
      'Здесь показаны только файлы, скачанные самим приложением. Ничего не удаляется автоматически.';

  @override
  String offlineStorageQuota(String size) {
    return 'Лимит приложения: $size';
  }

  @override
  String get offlineStorageQuotaExceeded =>
      'Для этого пакета недостаточно места в лимите офлайн-хранилища. Сначала удалите ненужный пакет.';

  @override
  String downloadOfflineConfirmation(String size) {
    return 'Полный пакет займёт примерно $size. Начать загрузку?';
  }

  @override
  String get downloadedContent => 'Скачанный контент';

  @override
  String get noOfflinePackages => 'Офлайн-пакеты ещё не скачаны.';

  @override
  String get storageReadFailed => 'Не удалось прочитать офлайн-хранилище';

  @override
  String get tryAgain => 'Повторите попытку.';

  @override
  String get refresh => 'Обновить';

  @override
  String get deleteOfflinePackage => 'Удалить офлайн-пакет';

  @override
  String deleteOfflinePackageConfirmation(String name, String size) {
    return 'Удалить «$name» ($size) с этого устройства? Для использования без интернета пакет потребуется скачать снова.';
  }

  @override
  String deletePlayingAudioConfirmation(String name, String size) {
    return 'Сейчас воспроизводится «$name». Остановить плеер и удалить офлайн-пакет ($size) с этого устройства?';
  }

  @override
  String get offlinePackageDeleted => 'Офлайн-пакет удалён';

  @override
  String get offlinePackageDeleteFailed => 'Не удалось удалить офлайн-пакет';

  @override
  String packageTotalSize(String size) {
    return 'полный размер $size';
  }

  @override
  String get completeMushafPages => 'Полные страницы Мусхафа';

  @override
  String get completeRecitation => 'Полная запись Корана';

  @override
  String get downloadInProgress => 'Загрузка выполняется';

  @override
  String get downloadFailed => 'Загрузка прервана';

  @override
  String get notReady => 'Не готово';

  @override
  String get availableOffline => 'Доступно без интернета';

  @override
  String get moreTools => 'Практика и инструменты';

  @override
  String get books => 'Книги';

  @override
  String get quizzes => 'Квизы';

  @override
  String get support => 'Поддержка';

  @override
  String get privacy => 'Конфиденциальность';

  @override
  String get reminders => 'Напоминания';

  @override
  String get remindersSubtitle => 'Намаз и повторение Корана';

  @override
  String get notificationAccess => 'Разрешите уведомления';

  @override
  String get notificationAccessBody =>
      'IQRO напомнит в выбранное время, даже когда приложение закрыто.';

  @override
  String get allowNotifications => 'Разрешить уведомления';

  @override
  String get notificationDenied =>
      'Уведомления выключены в настройках устройства.';

  @override
  String get approximateDelivery =>
      'Система может доставлять уведомления с небольшой задержкой для экономии батареи.';

  @override
  String get prayerReminders => 'Напоминания о намазе';

  @override
  String get prayerReminderSetup =>
      'Сначала выберите метод расчёта и определите местоположение в разделе «Время намаза».';

  @override
  String get quranReviewReminders => 'Повторение Корана';

  @override
  String get addReminder => 'Добавить напоминание';

  @override
  String get noReminders => 'Напоминаний о повторении пока нет.';

  @override
  String get reviewReminder => 'Повторение аятов';

  @override
  String get reminderTime => 'Время';

  @override
  String get reminderDays => 'Дни недели';

  @override
  String get everyDay => 'Каждый день';

  @override
  String get signal => 'Сигнал';

  @override
  String get sound => 'Звук';

  @override
  String get vibration => 'Вибрация';

  @override
  String get silent => 'Без звука';

  @override
  String get timezone => 'Часовой пояс';

  @override
  String get deviceTimezone => 'Как на устройстве';

  @override
  String get fixedTimezone => 'Фиксированный';

  @override
  String get timezoneName => 'Часовой пояс IANA';

  @override
  String get startAyah => 'Первый аят';

  @override
  String get endAyah => 'Последний аят';

  @override
  String get delete => 'Удалить';

  @override
  String get deleteReminderConfirm => 'Удалить это напоминание?';

  @override
  String get reminderSaved => 'Напоминание сохранено';

  @override
  String get mondayShort => 'Пн';

  @override
  String get tuesdayShort => 'Вт';

  @override
  String get wednesdayShort => 'Ср';

  @override
  String get thursdayShort => 'Чт';

  @override
  String get fridayShort => 'Пт';

  @override
  String get saturdayShort => 'Сб';

  @override
  String get sundayShort => 'Вс';

  @override
  String get readerHaptics => 'Вибрация при перелистывании';

  @override
  String get readerHapticsHint =>
      'Короткий отклик при смене страницы Мусхафа. В Android также должна быть включена вибрация касаний.';
}

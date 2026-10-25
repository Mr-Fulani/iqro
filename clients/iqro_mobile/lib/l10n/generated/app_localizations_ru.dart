// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Russian (`ru`).
class AppLocalizationsRu extends AppLocalizations {
  AppLocalizationsRu([String locale = 'ru']) : super(locale);

  @override
  String homePrayerIn(String time) {
    return 'Через $time';
  }

  @override
  String get homeSavedHint => 'Сохранённые аяты и ду’а';

  @override
  String get homeDownloads => 'Загрузки';

  @override
  String get bookmarks => 'Закладки';

  @override
  String get emptyBookmarks =>
      'Пока нет закладок. Сохраните аят с помощью значка закладки в Мусхафе.';

  @override
  String get bookmarksLoadError => 'Не удалось загрузить закладки';

  @override
  String get notes => 'Заметки';

  @override
  String get emptyNotes =>
      'Пока нет заметок. Добавьте заметку к аяту в Мусхафе.';

  @override
  String get addNote => 'Добавить заметку';

  @override
  String get editNote => 'Изменить заметку';

  @override
  String get noteHint => 'Напишите заметку к этому аяту';

  @override
  String get noteLabel => 'ВАША ЗАМЕТКА';

  @override
  String noteWordCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count слова',
      many: '$count слов',
      few: '$count слова',
      one: '$count слово',
    );
    return '$_temp0';
  }

  @override
  String get removeNote => 'Удалить заметку';

  @override
  String get noteSaved => 'Заметка сохранена';

  @override
  String get noteRemoved => 'Заметка удалена';

  @override
  String get highlightAyah => 'Выделить';

  @override
  String get chooseHighlightColor => 'Выбрать цвет выделения';

  @override
  String get highlightColorEmerald => 'Изумрудный';

  @override
  String get highlightColorYellow => 'Жёлтый';

  @override
  String get highlightColorPink => 'Розовый';

  @override
  String get highlightColorLime => 'Лаймовый';

  @override
  String get highlightColorBlue => 'Голубой';

  @override
  String get highlightColorLavender => 'Лавандовый';

  @override
  String get removeHighlight => 'Убрать выделение';

  @override
  String get removeHighlightWithNote =>
      'Заметка к этому аяту тоже будет удалена.';

  @override
  String get highlightRemoved => 'Выделение убрано';

  @override
  String get repeatSelectedAyah => 'Повторять выбранный аят';

  @override
  String get copyAyah => 'Копировать аят';

  @override
  String get shareAyah => 'Поделиться аятом';

  @override
  String get copied => 'Аят скопирован';

  @override
  String get copyAyahFailed => 'Не удалось скопировать аят';

  @override
  String get mushafFitWidth => 'По ширине';

  @override
  String get mushafFitPage => 'Вся страница';

  @override
  String get checkMushafUpdates => 'Проверить обновления';

  @override
  String get mushafUpToDate => 'Скачанный Мусхаф уже обновлён';

  @override
  String get updateMushaf => 'Обновить Мусхаф';

  @override
  String updateMushafConfirmation(String size) {
    return 'Скачать обновлённые страницы ($size). Текущий Мусхаф останется доступен до завершения загрузки и проверки нового пакета.';
  }

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
  String get newsTitle => 'Что нового';

  @override
  String get newsDescription =>
      'Новые чтецы, функции и материалы на сайте и в приложении.';

  @override
  String get newsEmpty => 'Пока новостей нет.';

  @override
  String get newsLoadMore => 'Показать ещё';

  @override
  String get newsLoadError => 'Не удалось загрузить новости. Попробуйте позже.';

  @override
  String get newsAll => 'Все';

  @override
  String get newsFilterLabel => 'Тип новости';

  @override
  String get newsFilterReciter => 'Чтецы';

  @override
  String get newsFilterFeature => 'Функции';

  @override
  String get newsFilterContent => 'Содержание';

  @override
  String get newsFilterAppRelease => 'Приложение';

  @override
  String get newsFilterGeneral => 'Общее';

  @override
  String get newsKindReciter => 'Новый чтец';

  @override
  String get newsKindFeature => 'Что нового';

  @override
  String get newsKindAppRelease => 'Новая версия';

  @override
  String get newsKindContent => 'Новое содержание';

  @override
  String get newsKindGeneral => 'Объявление';

  @override
  String get newsUnread => 'Не прочитано';

  @override
  String get newsHowTo => 'Как пользоваться';

  @override
  String get newsMore => 'Подробнее';

  @override
  String get newsPrevious => 'Предыдущее';

  @override
  String get newsNext => 'Следующее';

  @override
  String newsCounter(int current, int total) {
    return '$current из $total';
  }

  @override
  String newsBubble(int count) {
    return 'Новое: $count. Открыть';
  }

  @override
  String get continueLabel => 'Продолжить';

  @override
  String get done => 'Готово';

  @override
  String get namesOfAllah => 'Имена Аллаха';

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
  String get mushafCatalogEmpty => 'Мусхафы ещё не загружены';

  @override
  String get mushafPreviewDescription =>
      'Хафс · оформление IQRO · тестовая версия';

  @override
  String get mushafPublishedDescription =>
      'Хафс · чтение онлайн и без интернета';

  @override
  String get mushafPickerHint => 'Нажмите на страницу, чтобы рассмотреть её';

  @override
  String get mushafMakePrimary => 'Сделать основным';

  @override
  String get mushafIsPrimary => 'Основной Мусхаф';

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
  String get styleKidsRepeat => 'Детское с повтором';

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
  String get speed => 'Скорость';

  @override
  String get audioQuality => 'Качество аудио';

  @override
  String get playerBackground => 'Фон плеера';

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
  String get qiblaNorth => 'С';

  @override
  String get qiblaLiveHint =>
      'Компас устройства включён: держите телефон горизонтально — стрелка показывает Киблу относительно его верха.';

  @override
  String get qiblaFacing => 'Вы смотрите на Киблу';

  @override
  String get qiblaCalibrationNeeded => 'Компас нужно откалибровать';

  @override
  String get qiblaCalibrationHint =>
      'Поводите телефоном в воздухе восьмёркой несколько раз, подальше от металла и магнитов, в том числе магнитных чехлов.';

  @override
  String get qiblaCompassUnavailable => 'Компас на этом устройстве недоступен.';

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
  String get homeWidgetAlreadyAdded => 'Виджет уже добавлен. Данные обновлены.';

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
  String get duaFavoritesSubtitle => 'Сохранённые ду’а';

  @override
  String duaChapterNumber(int number) {
    return 'Глава $number';
  }

  @override
  String duaCounterRemaining(int count) {
    return 'Осталось: $count';
  }

  @override
  String get duaAudioFailed => 'Не удалось воспроизвести аудио';

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
  String get shareReadInIqro => 'Читать в IQRO';

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
  String get invalidEmail => 'Проверьте формат email.';

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
  String get currentDevice => 'Это устройство';

  @override
  String get noDevices => 'Устройства не найдены.';

  @override
  String get feedbackTitle => 'Обратная связь и религиозный аудит';

  @override
  String get feedbackAccountHint =>
      'Сообщите о неточности в тексте, аудио, времени намаза или приложении.';

  @override
  String get feedbackSignInRequired => 'Войдите, чтобы отправить обращение';

  @override
  String get feedbackDescription =>
      'Сообщите религиозной редакции о неточности в тексте, таймкодах или расчётах молитв.';

  @override
  String get feedbackCreate => 'Создать обращение';

  @override
  String get feedbackCategory => 'Категория обращения';

  @override
  String get feedbackSubject => 'Тема';

  @override
  String get feedbackSubjectPlaceholder => 'Краткое описание';

  @override
  String get feedbackMessage => 'Сообщение';

  @override
  String get feedbackMessagePlaceholder =>
      'Подробное описание вопроса или замечания…';

  @override
  String get feedbackSend => 'Отправить обращение';

  @override
  String get feedbackNone => 'Активных обращений нет.';

  @override
  String feedbackTicket(String id) {
    return 'Обращение $id';
  }

  @override
  String feedbackTeam(String team) {
    return 'Команда: $team';
  }

  @override
  String get feedbackNoMessages => 'Сообщений пока нет.';

  @override
  String get feedbackAddMessage => 'Добавить сообщение';

  @override
  String get feedbackReplyPlaceholder => 'Ваш ответ редакции или поддержке';

  @override
  String get feedbackSendMessage => 'Отправить сообщение';

  @override
  String get feedbackReopen => 'Открыть повторно';

  @override
  String get feedbackCloseTicket => 'Закрыть обращение';

  @override
  String get feedbackCloseConfirmation =>
      'Закрыть обращение? Позже его можно будет открыть снова.';

  @override
  String get feedbackNoFurtherActions =>
      'Для этого обращения больше нельзя отправлять сообщения.';

  @override
  String get feedbackRequiredFields => 'Заполните тему и сообщение.';

  @override
  String get feedbackRateLimited => 'Слишком много обращений. Повторите позже.';

  @override
  String get feedbackActionError =>
      'Не удалось выполнить действие с обращением. Повторите позже.';

  @override
  String get feedbackCategoryReligious => 'Религиозный контент';

  @override
  String get feedbackCategoryLayout => 'Страница или разметка Мусхафа';

  @override
  String get feedbackCategoryAudio => 'Аудио, таймкоды или чтец';

  @override
  String get feedbackCategoryAdvertisement => 'Реклама';

  @override
  String get feedbackCategoryTechnical => 'Техническая проблема';

  @override
  String get feedbackCategoryAccount => 'Аккаунт или синхронизация';

  @override
  String get feedbackCategoryDonation => 'Пожертвование или внешняя ссылка';

  @override
  String get feedbackCategoryAccessibility => 'Доступность или локализация';

  @override
  String get feedbackCategoryGeneral => 'Общее предложение';

  @override
  String get feedbackCategoryOther => 'Другое';

  @override
  String get feedbackStatusNew => 'Новое';

  @override
  String get feedbackStatusTriaged => 'Рассматривается';

  @override
  String get feedbackStatusProgress => 'В работе';

  @override
  String get feedbackStatusWaiting => 'Ждём ответа';

  @override
  String get feedbackStatusResolved => 'Решено';

  @override
  String get feedbackStatusRejected => 'Отклонено';

  @override
  String get feedbackStatusDuplicate => 'Дубликат';

  @override
  String get feedbackStatusClosed => 'Закрыто';

  @override
  String get feedbackSupport => 'Поддержка';

  @override
  String get feedbackYou => 'Вы';

  @override
  String get feedbackSystem => 'Система';

  @override
  String get signOutConfirmation => 'Выйти из аккаунта на этом устройстве?';

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
      'Скачанные страницы Мусхафа, аудио и картинки курса намаза';

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
  String get analyticsTitle => 'Статистика использования';

  @override
  String get analyticsCardText =>
      'С вашего согласия мы считаем использование приложения через Google Analytics, чтобы понимать, какие разделы полезны. Без согласия приложение работает так же.';

  @override
  String get analyticsPolicy => 'Политика конфиденциальности';

  @override
  String get analyticsAccept => 'Принять';

  @override
  String get analyticsDecline => 'Отклонить';

  @override
  String get analyticsStateGranted =>
      'Вы разрешили статистику: Google Analytics включён на этом устройстве.';

  @override
  String get analyticsStateDenied =>
      'Вы отказались от статистики: Google Analytics на этом устройстве выключен.';

  @override
  String get analyticsStateUnset =>
      'Вы ещё не выбрали. Пока выбора нет, Google Analytics выключен.';

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

  @override
  String get mushafPageCaching =>
      'Страницы загружаются по мере чтения. Открытые страницы и их шрифты сохраняются на устройстве и доступны без интернета.';

  @override
  String get planCreditedToday => 'Сегодня засчитано';

  @override
  String get planGoalLabel => 'Цель на день';

  @override
  String get planEditGoal => 'Изменить цель';

  @override
  String get planGoalReached => 'Дневная цель достигнута';

  @override
  String planRemainingAmount(String amount) {
    return 'До цели осталось: $amount';
  }

  @override
  String planGoalAmount(String amount) {
    return 'Цель: $amount';
  }

  @override
  String planCreditedAmount(String amount) {
    return 'Засчитано: $amount';
  }

  @override
  String get planManualEntry => 'Добавить прочитанное вручную';

  @override
  String get planManualHelp =>
      'Добавьте чтение, которое ещё не было учтено. Это увеличит сегодняшний прогресс, а не дневную цель.';

  @override
  String get planHowCounted => 'Как считается прогресс';

  @override
  String get planPagesHelp =>
      'При переходе на следующую страницу в читалке страница засчитывается автоматически. Ручные записи тоже учитываются. Перелистывание не подтверждает, что страница прочитана.';

  @override
  String get planMinutesHelp =>
      'Активное время в читалке учитывается автоматически. Минуты, добавленные вручную, тоже входят в прогресс.';

  @override
  String get planAyahsHelp =>
      'Последовательное продвижение по аятам в читалке учитывается автоматически. Аяты, добавленные вручную, тоже входят в прогресс.';

  @override
  String get planDailyHelp =>
      'Прогресс считается отдельно за каждый день. Смена цели его не обнуляет; предыдущие дни остаются в истории.';

  @override
  String get planResetHelp =>
      'Отметки после намаза можно уменьшить кнопкой «−». Обнуление всего прогресса за сегодня на этом экране пока недоступно.';

  @override
  String get planPrayerTitle => 'Чтение после намаза';

  @override
  String get planPrayerSummary =>
      'Страницы, отмеченные вами за сегодня. Это выполненное чтение, а не цель.';

  @override
  String get planEditPrayer => 'Изменить отметки за сегодня';

  @override
  String get planPrayerInstructions =>
      'Отмечайте страницы, прочитанные после каждого намаза. «+» добавляет одну страницу, «−» убирает одну. Ноль означает, что страницы не отмечены.';

  @override
  String planRemovePage(String prayer) {
    return 'Убрать одну страницу: $prayer';
  }

  @override
  String planAddPage(String prayer) {
    return 'Добавить одну страницу: $prayer';
  }

  @override
  String get planUnavailable =>
      'Не удалось обновить план. Показан сохранённый прогресс; изменения станут доступны после успешного обновления.';

  @override
  String get planGoalHint =>
      'Выберите дневную цель в минутах, страницах или аятах. Это настройка цели, а не запись прочитанного.';

  @override
  String planBestStreak(String streak) {
    return 'Лучшая серия: $streak';
  }

  @override
  String planActiveTime(String amount) {
    return 'Активное чтение: $amount';
  }

  @override
  String planPages(num count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString страницы',
      many: '$countString страниц',
      few: '$countString страницы',
      one: '$countString страница',
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
      other: '$countString минуты',
      many: '$countString минут',
      few: '$countString минуты',
      one: '$countString минута',
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
      other: '$countString аята',
      many: '$countString аятов',
      few: '$countString аята',
      one: '$countString аят',
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
      other: '$countString дня подряд',
      many: '$countString дней подряд',
      few: '$countString дня подряд',
      one: '$countString день подряд',
    );
    return '$_temp0';
  }

  @override
  String get palmTitle => 'Ваша финиковая пальма';

  @override
  String get palmStageSeed => 'Косточка финика';

  @override
  String get palmStageSprout => 'Росток';

  @override
  String get palmStageSeedling => 'Саженец';

  @override
  String get palmStageYoungPalm => 'Молодая пальма';

  @override
  String get palmStagePalm => 'Пальма';

  @override
  String get palmStageFruitingPalm => 'Пальма с финиками';

  @override
  String get palmMoodPlanting =>
      'Посадите косточку: прочитайте первую страницу';

  @override
  String get palmMoodFlourishing =>
      'Цель на сегодня выполнена — пальма тянется к солнцу';

  @override
  String get palmMoodGrowing => 'Сегодняшнее чтение уже питает пальму';

  @override
  String get palmMoodWaiting => 'Пальма ждёт сегодняшнего чтения';

  @override
  String get palmMoodResting =>
      'Пальма отдыхает в тени и ждёт вас. Даже одна страница её порадует';

  @override
  String palmNextStage(String stage) {
    return 'Дальше: $stage';
  }

  @override
  String get palmFullyGrown => 'Пальма выросла — пусть приносит плоды';

  @override
  String get palmHowItGrows =>
      'День чтения — +1, выполненная цель — +2. Пропуски не вредят пальме — она просто отдыхает.';

  @override
  String get planSummaryTitle => 'Сводка прогресса';

  @override
  String planSummaryRange(num days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days дня',
      many: '$days дней',
      few: '$days дня',
      one: '$days день',
    );
    return 'За последние $_temp0';
  }

  @override
  String get planReadingDays => 'дней с чтением';

  @override
  String get planCompletedDays => 'норм выполнено';

  @override
  String get planPartialDays => 'частичных дней';

  @override
  String get planCalendarTitle => 'Календарь прогресса';

  @override
  String get planCalendarHint =>
      'Выберите день, чтобы увидеть норму, чтение и отметки после намаза.';

  @override
  String get planCalendarEmpty => 'За этот период нет данных.';

  @override
  String get planSelectedDay => 'Выбранный день';

  @override
  String get planRelatedTools => 'Связанные разделы';

  @override
  String get planHistoryEmpty => 'Записей чтения за этот период нет.';

  @override
  String planPrayerCount(num count) {
    return 'Отметок после намаза: $count';
  }

  @override
  String planAutomaticSessions(num count) {
    return 'Автоматических сессий: $count';
  }

  @override
  String get planManualRecord => 'Добавлено вручную';

  @override
  String get planEditEntry => 'Изменить запись';

  @override
  String get planDeleteEntry => 'Удалить запись';

  @override
  String get planDeleteEntryTitle => 'Удалить запись?';

  @override
  String get planDeleteEntryConfirm =>
      'Эта ручная запись будет удалена, а прогресс пересчитан.';

  @override
  String get planReadingAmount => 'Количество';

  @override
  String get planReadingDate => 'Дата чтения';

  @override
  String get planStateNoGoal => 'Без нормы';

  @override
  String get planStatePending => 'Сегодня';

  @override
  String get planStateMissed => 'Пропущено';

  @override
  String get planStatePartial => 'Частично';

  @override
  String get planStateCompleted => 'Выполнено';

  @override
  String planDays(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count дн.',
      many: '$count дн.',
      few: '$count дн.',
      one: '$count дн.',
    );
    return '$_temp0';
  }

  @override
  String get salahTitle => 'Обучение намазу';

  @override
  String get salahHint => 'Пошагово: вуду и пять молитв';

  @override
  String salahLessonsProgress(int done, int total) {
    return '$done из $total уроков';
  }

  @override
  String get salahContinue => 'Продолжить';

  @override
  String get salahStart => 'Начать';

  @override
  String salahStepOf(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String salahRakatOf(int current, int total) {
    return 'Ракаат $current из $total';
  }

  @override
  String get salahBack => 'Назад';

  @override
  String get salahNext => 'Далее';

  @override
  String get salahFinish => 'Завершить';

  @override
  String get salahNextStep => 'Следующий шаг';

  @override
  String get salahPreviousStep => 'Предыдущий шаг';

  @override
  String get salahModeLearn => 'Обучение';

  @override
  String get salahModePractice => 'Практика';

  @override
  String get salahDisplayOptions => 'Что показывать';

  @override
  String get salahShowArabic => 'Арабский текст';

  @override
  String get salahShowTransliteration => 'Транслитерация';

  @override
  String get salahShowTranslation => 'Перевод';

  @override
  String get salahStepAudio => 'Озвучка шага';

  @override
  String get salahNotes => 'Заметки к шагу';

  @override
  String get salahNoteHelp => 'Справка';

  @override
  String get salahNoteWarning => 'Важно';

  @override
  String get salahNoteClose => 'Закрыть заметку';

  @override
  String salahMinutes(int count) {
    return '$count мин';
  }

  @override
  String get salahLessonCompleted => 'Урок пройден';

  @override
  String get salahStatusCompleted => 'Пройден';

  @override
  String get salahStatusInProgress => 'Начат';

  @override
  String get salahUnavailable => 'Курс пока недоступен';

  @override
  String get salahLessonNotFound => 'Такого урока нет в курсе';

  @override
  String get salahRulingShart => 'Условие (шарт)';

  @override
  String get salahRulingRukn => 'Столп (рукн)';

  @override
  String get salahRulingWajib => 'Обязательно (ваджиб)';

  @override
  String get salahRulingSunnah => 'Сунна';

  @override
  String get salah3dSchematic => 'Схематичная 3D-иллюстрация';

  @override
  String get salah3dPlay => 'Воспроизвести движение';

  @override
  String get salah3dPause => 'Остановить движение';

  @override
  String salah3dSpeed(String speed) {
    return 'Скорость движения: $speed';
  }

  @override
  String get salah3dReplay => 'Повторить';

  @override
  String get salahOfflineTitle => 'Картинки без интернета';

  @override
  String get salahOfflineImages => 'Иллюстрации курса';

  @override
  String get salahOfflineSaved => 'Сохранены на устройстве';

  @override
  String get salahOfflineUpdateAvailable => 'Есть новая версия';

  @override
  String get salahOfflineUpdate => 'Обновить';

  @override
  String get accountSignOutEverywhere => 'Выйти на всех устройствах';

  @override
  String get accountSignOutEverywhereTitle => 'Завершить все сессии?';

  @override
  String get accountSignOutEverywhereDescription =>
      'Будут отозваны текущая сессия и входы на остальных устройствах. Для продолжения потребуется снова получить код по email.';

  @override
  String get accountSignOutEverywhereConfirm => 'Подтвердить выход везде';

  @override
  String get accountSignOutEverywhereError =>
      'Не удалось завершить все сессии. Повторите попытку.';

  @override
  String get accountDangerZone => 'Опасная зона';

  @override
  String get accountDeletionTitle => 'Удаление аккаунта';

  @override
  String get accountDeletionDescription =>
      'После повторной проверки email начнётся 7-дневный период отмены. До его окончания безвозвратное удаление не выполняется.';

  @override
  String get accountDelete => 'Удалить аккаунт';

  @override
  String get accountDeletionRequestTitle => 'Запланировать удаление аккаунта?';

  @override
  String get accountDeletionRequestDescription =>
      'Обычный доступ будет заблокирован сразу. Через 7 дней синхронизируемые данные будут удалены, а аккаунт — анонимизирован.';

  @override
  String get accountDeletionCancelTitle => 'Отменить удаление?';

  @override
  String get accountDeletionCancelDescription =>
      'Для восстановления аккаунта подтвердите владение email новым одноразовым кодом.';

  @override
  String accountSendCodeTo(String email) {
    return 'Получить код на $email';
  }

  @override
  String get accountConfirmDeletion => 'Подтвердить удаление';

  @override
  String get accountRestore => 'Восстановить аккаунт';

  @override
  String get accountNewCode => 'Запросить новый код';

  @override
  String get accountPendingDeletionTitle => 'Удаление аккаунта запланировано';

  @override
  String accountPendingDeletionDescription(String date) {
    return 'Аккаунт и синхронизируемые данные будут удалены после $date. До этого момента удаление можно отменить после повторной проверки email.';
  }

  @override
  String get accountCancelDeletion => 'Отменить удаление';

  @override
  String get accountDeletionScheduledNotice =>
      'Удаление аккаунта запланировано. До указанной даты его можно отменить.';

  @override
  String get accountDeletionCancelledNotice => 'Удаление аккаунта отменено.';

  @override
  String get accountCodeSendError =>
      'Не удалось отправить код. Повторите попытку.';

  @override
  String get accountCodeVerifyError => 'Не удалось подтвердить код.';

  @override
  String get accountCodeExpired =>
      'Подтверждение устарело. Запросите новый код.';

  @override
  String get accountActionError => 'Не удалось завершить действие с аккаунтом.';

  @override
  String downloadOfflineSurahsConfirmation(int count, String size) {
    return 'Сур: $count, примерно $size. Начать загрузку?';
  }

  @override
  String audioOfflineSurahs(int count) {
    return 'Сур на устройстве: $count';
  }

  @override
  String audioOfflineNewSurahs(int count) {
    return 'Новые суры: $count';
  }

  @override
  String get apiErrorEmailInvalid =>
      'Код неверен или сессия изменилась. Запросите новый код.';

  @override
  String get apiErrorEmailExpired =>
      'Срок действия кода истёк. Запросите новый код.';

  @override
  String get apiErrorEmailDelivery =>
      'Не удалось отправить код. Попробуйте ещё раз позже.';

  @override
  String get apiErrorRateLimited => 'Слишком много попыток. Повторите позже.';

  @override
  String get apiErrorInstallationMissing =>
      'Сессия устройства потеряна. Запросите новый код.';

  @override
  String get apiErrorLinkUnavailable =>
      'Этот вход нельзя завершить в текущей сессии.';

  @override
  String get apiErrorIdentityLinked =>
      'Этот email уже привязан к другому аккаунту.';

  @override
  String get apiErrorReauthRequired =>
      'Для этого действия нужен новый код из email.';

  @override
  String get apiErrorLifecycleUnavailable =>
      'Это действие с аккаунтом сейчас недоступно.';

  @override
  String get apiErrorCurrentDevice =>
      'Для текущего устройства используйте обычный выход.';

  @override
  String get apiErrorDeviceNotFound =>
      'Устройство уже отключено или недоступно.';

  @override
  String get apiErrorCursorExpired =>
      'История синхронизации устарела. Выполняется полная сверка данных.';

  @override
  String get apiErrorUnknown => 'Повторите попытку позже.';

  @override
  String get tajweedLegendPage => 'Правила таджвида на странице';

  @override
  String get tajweedLegendAyah => 'Правила таджвида в аяте';

  @override
  String get tajweedWordTitle => 'Таджвид в слове';

  @override
  String get tajweedRuleTitle => 'Правило таджвида';

  @override
  String get tajweedWhyHere => 'Почему здесь';

  @override
  String get tajweedWhenApplies => 'Когда действует';

  @override
  String get tajweedHowToRead => 'Как читать';

  @override
  String get tajweedOccurrencesPage => 'Где на этой странице';

  @override
  String get tajweedOccurrencesAyah => 'Где в этом аяте';

  @override
  String get tajweedListen => 'Послушать фрагмент';

  @override
  String get tajweedStop => 'Остановить';

  @override
  String get tajweedSlow => '0,75×';

  @override
  String get tajweedSlowLabel => 'Медленнее, 0,75×';

  @override
  String get tajweedClose => 'Закрыть';

  @override
  String get tajweedReviewNote =>
      'Пояснения проходят проверку у преподавателя таджвида.';

  @override
  String get tajweedAudioError => 'Не удалось воспроизвести фрагмент.';

  @override
  String get tajweedBreakdown => 'Разбор таджвида';

  @override
  String get tajweedPlayAyah => 'Прослушать весь аят';

  @override
  String tajweedStepOf(int current, int total) {
    return '$current из $total';
  }

  @override
  String tajweedStepNumber(int number) {
    return 'Шаг $number';
  }

  @override
  String get tajweedPrevious => 'Назад';

  @override
  String get tajweedNext => 'Далее';

  @override
  String get tajweedToSummary => 'Итог';

  @override
  String get tajweedDone => 'Готово';

  @override
  String get tajweedSummary => 'Итог';

  @override
  String get tajweedSummaryTitle => 'Правила, которые встретились в аяте';

  @override
  String get tajweedRestart => 'Начать сначала';

  @override
  String get tajweedBackToSummary => 'К итогу';

  @override
  String get tajweedNextStep => 'Следующий шаг';

  @override
  String get tajweedPreviousStep => 'Предыдущий шаг';

  @override
  String get tajweedCourseTitle => 'Таджвид';

  @override
  String get tajweedCourseHint => 'Правила чтения по шагам';

  @override
  String tajweedCourseProgress(int completed, int total) {
    return '$completed из $total уроков';
  }

  @override
  String get tajweedCourseStart => 'Начать курс';

  @override
  String get tajweedCourseContinue => 'Продолжить';

  @override
  String get tajweedCourseAllCompleted => 'Все уроки пройдены';

  @override
  String get tajweedCourseStatusCompleted => 'Пройден';

  @override
  String get tajweedCourseStatusInProgress => 'Начат';

  @override
  String tajweedCourseStepOf(int current, int total) {
    return 'Шаг $current из $total';
  }

  @override
  String get tajweedCourseRule => 'Правило';

  @override
  String get tajweedCourseLetters => 'Буквы правила';

  @override
  String tajweedCourseExampleOf(int current, int total) {
    return 'Пример $current из $total';
  }

  @override
  String tajweedCourseAyahReference(int surah, int ayah) {
    return 'Сура $surah, аят $ayah';
  }

  @override
  String get tajweedCourseMoreExamples => 'Ещё примеры';

  @override
  String get tajweedCourseExamplesLoading => 'Подбираем примеры из Корана…';

  @override
  String get tajweedCourseExamplesError => 'Не удалось загрузить примеры.';

  @override
  String get tajweedCourseRetry => 'Повторить';

  @override
  String get tajweedCourseFindTitle => 'Найдите правило в аяте';

  @override
  String tajweedCourseFindPrompt(String rule) {
    return 'Нажмите на слово, в котором есть «$rule».';
  }

  @override
  String tajweedCourseFindCorrect(String rule) {
    return 'Верно! Здесь «$rule».';
  }

  @override
  String get tajweedCourseFindWrong =>
      'Здесь этого правила нет — попробуйте другое слово.';

  @override
  String get tajweedCourseShowAnswer => 'Показать ответ';

  @override
  String tajweedCourseAnswerShown(String rule) {
    return 'Вот где здесь «$rule».';
  }

  @override
  String get tajweedCourseAnotherAyah => 'Другой аят';

  @override
  String get tajweedCourseFinish => 'Завершить урок';

  @override
  String get tajweedCourseLessonCompleted => 'Урок пройден';

  @override
  String tajweedCourseNextLesson(String title) {
    return 'Следующий урок: $title';
  }

  @override
  String get tajweedCourseAllLessons => 'Все уроки';

  @override
  String get tajweedCourseUnavailable => 'Курс пока недоступен.';

  @override
  String get tajweedPracticeTitle => 'Практика таджвида';

  @override
  String get tajweedPracticeShort => 'Практика';

  @override
  String get tajweedPracticeDescription =>
      'Задания по пройденным урокам: найдите правило в аяте, назовите его, узнайте на слух.';

  @override
  String get tajweedPracticeCta =>
      'Закрепите пройденные правила на аятах всего Корана.';

  @override
  String get tajweedPracticeOpen => 'Открыть практику';

  @override
  String get tajweedPracticeStart => 'Начать практику';

  @override
  String get tajweedPracticeNoLessons =>
      'Пройдите хотя бы один урок курса: практика строится по пройденным правилам.';

  @override
  String get tajweedPracticeToCourse => 'К курсу';

  @override
  String get tajweedPracticeScore => 'Счёт';

  @override
  String get tajweedPracticeStreak => 'Серия';

  @override
  String tajweedPracticeStreakDays(int count) {
    return '$count дн. подряд';
  }

  @override
  String tajweedPracticeReviewCount(int count) {
    return 'На повторение: $count';
  }

  @override
  String get tajweedPracticeLearned => 'Пройденные правила';

  @override
  String tajweedPracticeTaskOf(int current, int total) {
    return 'Задание $current из $total';
  }

  @override
  String get tajweedPracticeReviewBadge => 'Повторение';

  @override
  String tajweedPracticeFindPrompt(String rule) {
    return 'Найдите в аяте: «$rule»';
  }

  @override
  String get tajweedPracticeIdentifyPrompt =>
      'Какое правило в выделенном месте?';

  @override
  String get tajweedPracticeListenPrompt => 'Послушайте и определите правило';

  @override
  String get tajweedPracticeOptions => 'Варианты ответа';

  @override
  String get tajweedPracticeCorrect => 'Верно!';

  @override
  String tajweedPracticeWrong(String rule) {
    return 'Неверно. Здесь «$rule».';
  }

  @override
  String get tajweedPracticeLoading => 'Собираем задания…';

  @override
  String get tajweedPracticeError => 'Не удалось собрать задания.';

  @override
  String get tajweedPracticeNext => 'Далее';

  @override
  String get tajweedPracticePrevious => 'Назад';

  @override
  String get tajweedPracticeFinish => 'Завершить';

  @override
  String tajweedPracticeSummary(int correct, int total) {
    return 'Верно $correct из $total';
  }

  @override
  String get tajweedPracticeAgain => 'Ещё раз';

  @override
  String get coursesTitle => 'Курсы';

  @override
  String get coursesSubtitle => 'Темы с конспектами';

  @override
  String get coursesOfflineBanner =>
      'Нет интернета — показаны сохранённые курсы';

  @override
  String get coursesEmpty => 'Новые курсы появятся здесь.';

  @override
  String get coursesOfflineEmpty =>
      'Сохранённых курсов пока нет. Откройте курс с интернетом — он останется на телефоне.';

  @override
  String get coursesLoadFailed => 'Не удалось загрузить курсы';

  @override
  String get coursesContinue => 'Продолжить';

  @override
  String get coursesStart => 'Начать';

  @override
  String coursesLessonCount(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count темы',
      many: '$count тем',
      few: '$count темы',
      one: '$count тема',
    );
    return '$_temp0';
  }

  @override
  String coursesHours(int hours) {
    return '$hours ч';
  }

  @override
  String coursesHoursMinutes(int hours, int minutes) {
    return '$hours ч $minutes мин';
  }

  @override
  String coursesStatusStarted(int done, int total) {
    return 'Начат · $done/$total';
  }

  @override
  String get coursesStatusCompleted => 'Пройден';

  @override
  String coursesProgress(int done, int total) {
    return 'Пройдено тем: $done из $total';
  }

  @override
  String coursesLessonOf(String course, int number, int total) {
    return '$course · тема $number из $total';
  }

  @override
  String get coursesSource => 'Автор и источники';

  @override
  String get coursesLessons => 'Темы';

  @override
  String get coursesNotes => 'Конспект';

  @override
  String get coursesSources => 'Источники';

  @override
  String get coursesImportant => 'Важно';

  @override
  String get coursesMarkWarning => 'Внимание';

  @override
  String get coursesMarkHelp => 'Пояснение';

  @override
  String get coursesMarkClose => 'Закрыть';

  @override
  String get coursesLinkOpensBrowser => 'откроется в браузере';

  @override
  String get coursesMarkDone => 'Тема изучена';

  @override
  String get coursesLessonDone => 'Тема пройдена';

  @override
  String get coursesUnmark => 'Снять отметку';

  @override
  String get coursesPrevious => 'Назад';

  @override
  String get coursesNext => 'Дальше';

  @override
  String coursesPreviousTopic(String title) {
    return 'Назад: $title';
  }

  @override
  String coursesNextTopic(String title) {
    return 'Дальше: $title';
  }

  @override
  String get coursesAllLessons => 'Все темы';

  @override
  String get coursesCompleted => 'Курс пройден';

  @override
  String get coursesUpdateApp => 'Обновите приложение';

  @override
  String get coursesUpdateAppMessage =>
      'Этот курс сделан для новой версии IQRO.';

  @override
  String get coursesUnavailable => 'Курс сейчас недоступен';

  @override
  String get coursesLessonNotFound => 'Такой темы нет в курсе';

  @override
  String coursesVideoMeta(String duration, int size) {
    return '$duration · $size МБ';
  }

  @override
  String coursesVideoWatch(String title, String meta) {
    return 'Смотреть видео «$title», $meta';
  }

  @override
  String coursesVideoResumeFrom(String time) {
    return 'Продолжить с $time';
  }

  @override
  String coursesVideoFrom(String time) {
    return 'Видео с $time';
  }

  @override
  String coursesVideoLanguage(String language) {
    String _temp0 = intl.Intl.selectLogic(language, {
      'ru': 'Видео на русском языке',
      'en': 'Видео на английском языке',
      'ar': 'Видео на арабском языке',
      'tr': 'Видео на турецком языке',
      'other': 'Видео на другом языке',
    });
    return '$_temp0';
  }

  @override
  String get coursesVideoFailed => 'Видео не загрузилось';

  @override
  String get coursesVideoBack10 => 'Назад на 10 секунд';

  @override
  String get coursesVideoForward10 => 'Вперёд на 10 секунд';

  @override
  String get coursesVideoPosition => 'Позиция видео';

  @override
  String get coursesVideoFullscreen => 'Во весь экран';

  @override
  String get coursesVideoExitFullscreen => 'Выйти из полноэкранного режима';

  @override
  String get lessonMediaSlides => 'Слайды';

  @override
  String lessonMediaSlideOf(int current, int total) {
    return 'Слайд $current из $total';
  }

  @override
  String lessonMediaSlideCounter(int current, int total) {
    return '$current / $total';
  }

  @override
  String get lessonMediaPreviousSlide => 'Предыдущий слайд';

  @override
  String get lessonMediaNextSlide => 'Следующий слайд';

  @override
  String get coursesShare => 'Поделиться';

  @override
  String get coursesVoteQuestion => 'Тема была полезной?';

  @override
  String get coursesVoteHelpful => 'Полезно';

  @override
  String get coursesVoteNotHelpful => 'Не очень';

  @override
  String get coursesVoteThanks => 'Спасибо за отзыв';

  @override
  String get coursesRatingQuestion => 'Насколько курс был полезен?';

  @override
  String coursesRatingStars(int stars) {
    return '$stars из 5';
  }

  @override
  String get coursesRatingComment => 'Комментарий (необязательно)';

  @override
  String get coursesSend => 'Отправить';

  @override
  String coursesRatingThanks(int stars) {
    return 'Спасибо! Ваша оценка: $stars из 5';
  }

  @override
  String get coursesRatingChange => 'Изменить';

  @override
  String get coursesSendFailed => 'Не удалось отправить. Попробуйте ещё раз.';

  @override
  String get coursesSendTooOften => 'Слишком часто. Попробуйте позже.';

  @override
  String get coursesReportError => 'Сообщить об ошибке';

  @override
  String get coursesReportType => 'Тип замечания';

  @override
  String get coursesReportReligious => 'Ошибка в религиозном содержании';

  @override
  String get coursesReportTypo => 'Опечатка или перевод';

  @override
  String get coursesReportTechnical => 'Не работает видео или страница';

  @override
  String get coursesReportOther => 'Другое';

  @override
  String get coursesReportMessage => 'Текст замечания';

  @override
  String get coursesReportMessageRequired => 'Опишите замечание';

  @override
  String get coursesReportEmail => 'Email для ответа (необязательно)';

  @override
  String coursesReportThanks(String id) {
    return 'Спасибо! Номер обращения $id';
  }

  @override
  String get coursesReportOpen => 'Открыть обращение';

  @override
  String get queueAfterSurah => 'После суры';

  @override
  String get queueModeStop => 'Стоп';

  @override
  String get queueModeNext => 'Дальше';

  @override
  String get queueModeLoop => 'По кругу';

  @override
  String get queueTitle => 'Очередь';

  @override
  String get queueUpNext => 'Далее';

  @override
  String get queueWholeQuranFromStart => 'Весь Коран с начала';

  @override
  String get listenWholeQuran => 'Слушать весь Коран';

  @override
  String get recitationVariant => 'Вид чтения';

  @override
  String get chooseRecitationVariant => 'Что слушать';

  @override
  String queueHeldSurahs(int count) {
    return 'есть $count из 114 сур';
  }

  @override
  String queueMissingSurahs(int from, int to) {
    return 'суры $from–$to не загружены';
  }

  @override
  String queueMissingSurah(int number) {
    return 'сура $number не загружена';
  }

  @override
  String get recitationAllSurahs => 'все 114 сур';

  @override
  String recitationSomeSurahs(int count) {
    return '$count из 114 сур';
  }
}

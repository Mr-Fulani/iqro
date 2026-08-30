from __future__ import annotations

# ruff: noqa: PLR0913, RUF001 -- Curated multilingual profile data is intentionally explicit.
from datetime import date
from typing import Any

SOURCE_CHECKED_ON = date(2026, 8, 30)


def _profile(
    *,
    name_ar: str,
    name_en: str,
    name_ru: str,
    name_tr: str,
    biography_ar: str,
    biography_en: str,
    biography_ru: str,
    biography_tr: str,
    country_code: str,
    profile_source_url: str,
) -> dict[str, Any]:
    return {
        "name_ar": name_ar,
        "name_en": name_en,
        "name_ru": name_ru,
        "name_tr": name_tr,
        "biography_ar": biography_ar,
        "biography_en": biography_en,
        "biography_ru": biography_ru,
        "biography_tr": biography_tr,
        "country_code": country_code,
        "profile_source_url": profile_source_url,
        "profile_source_checked_on": SOURCE_CHECKED_ON,
    }


ABDUL_BASET = _profile(
    name_ar="عبد الباسط عبد الصمد",
    name_en="Abdul Basit Abdus Samad",
    name_ru="Абдуль-Басит Абдус-Самад",
    name_tr="Abdülbasit Abdüssamed",
    biography_ar=(
        "قارئ قرآن مصري وُلد عام 1927 في قرية المراعزة. حفظ القرآن في صغره، وانضم إلى "
        "الإذاعة المصرية عام 1951، واشتهر بتلاوتيه المرتلة والمجوّدة."
    ),
    biography_en=(
        "An Egyptian Quran reciter born in 1927 in al-Mara'za. He memorized the Quran "
        "at an early age, joined Egyptian Radio in 1951, and became renowned for both "
        "his murattal and mujawwad recitations."
    ),
    biography_ru=(
        "Египетский чтец Корана, родившийся в 1927 году в деревне Аль-Марааза. Он выучил "
        "Коран в раннем возрасте, в 1951 году начал выступать на Египетском радио и стал "
        "известен чтением в стилях муратталь и муджаввад."
    ),
    biography_tr=(
        "1927'de Mısır'ın el-Mara'za köyünde doğan Kur'an kârisi. Kur'an'ı küçük yaşta "
        "ezberledi, 1951'de Mısır Radyosu'na katıldı ve hem murattal hem de mücevved "
        "tilavetiyle tanındı."
    ),
    country_code="EG",
    profile_source_url="https://quran.com/en/reciters/2",
)

ALI_JABER = _profile(
    name_ar="علي عبد الله جابر",
    name_en="Ali Abdullah Jaber",
    name_ru="Али Абдуллах Джабир",
    name_tr="Ali Abdullah Cabir",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في جدة عام 1954. حفظ القرآن في مكة، ودرس الشريعة والقضاء، "
        "وعُرف بإمامته في المسجد الحرام."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Jeddah in 1954. He memorized the Quran in "
        "Makkah, studied Sharia and judicial studies, and became known for leading "
        "prayers at the Grand Mosque."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Джидде в 1954 году. Он выучил Коран в Мекке, "
        "изучал шариат и судебное право и получил известность как имам Заповедной мечети."
    ),
    biography_tr=(
        "1954'te Cidde'de doğan Suudi kâri ve imam. Kur'an'ı Mekke'de ezberledi, şeriat "
        "ve yargı alanlarında eğitim gördü; Mescid-i Haram'daki imamlığıyla tanındı."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/158",
)

ABDULLAH_ABU_SHARIDA = _profile(
    name_ar="عبد الله حمد أبو شريدة",
    name_en="Abdullah Hamad Abu Sharida",
    name_ru="Абдуллах Хамад Абу Шарида",
    name_tr="Abdullah Hamad Ebu Şeride",
    biography_ar=(
        "حافظ وقارئ قرآن قطري كفيف، تعلّم التلاوة منذ صغره بالاستماع إلى تسجيلات القراء. "
        "مثّل قطر في مسابقات دولية للقرآن وحصل على جوائز في الحفظ والتلاوة."
    ),
    biography_en=(
        "A blind Qatari Quran memorizer and reciter who learned from recordings of other "
        "reciters from an early age. He has represented Qatar in international Quran "
        "competitions and received awards for memorization and recitation."
    ),
    biography_ru=(
        "Незрячий катарский хафиз и чтец Корана, с детства учившийся по записям других "
        "чтецов. Он представлял Катар на международных конкурсах Корана и получал награды "
        "за запоминание и чтение."
    ),
    biography_tr=(
        "Küçük yaşta diğer kârilerin kayıtlarını dinleyerek öğrenen görme engelli Katarlı "
        "Kur'an hafızı ve kâri. Katar'ı uluslararası Kur'an yarışmalarında temsil etmiş, "
        "hafızlık ve tilavet alanlarında ödüller almıştır."
    ),
    country_code="QA",
    profile_source_url=(
        "https://al-sharq.com/article/06/02/2020/"
        "%D8%A7%D9%84%D9%82%D8%B7%D8%B1%D9%8A%D8%A9-%D9%84%D8%AA%D8%A3%D9%87%D9%8A%D9%84-"
        "%D8%B0%D9%88%D9%8A-%D8%A7%D9%84%D8%A7%D8%AD%D8%AA%D9%8A%D8%A7%D8%AC%D8%A7%D8%AA-"
        "%D8%AA%D9%83%D8%B1%D9%85-%D8%A7%D9%84%D9%82%D8%A7%D8%B1%D8%A6-"
        "%D8%B9%D8%A8%D8%AF-%D8%A7%D9%84%D9%84%D9%87-%D8%A3%D8%A8%D9%88-"
        "%D8%B4%D8%B1%D9%8A%D8%AF%D8%A9"
    ),
)

ABDUR_RAHMAN_AS_SUDAIS = _profile(
    name_ar="عبد الرحمن السديس",
    name_en="Abdur-Rahman as-Sudais",
    name_ru="Абдуррахман ас-Судейс",
    name_tr="Abdurrahman es-Sudeys",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في الرياض عام 1962، وأتم حفظ القرآن في الثانية عشرة. درس "
        "الشريعة، وعُرف بإمامته وخطابته في المسجد الحرام بمكة."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Riyadh in 1962 who completed memorizing the "
        "Quran at the age of twelve. He studied Sharia and is known for serving as an "
        "imam and preacher at the Grand Mosque in Makkah."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Эр-Рияде в 1962 году и завершивший "
        "заучивание Корана в двенадцать лет. Он изучал шариат и известен служением имамом "
        "и проповедником Заповедной мечети в Мекке."
    ),
    biography_tr=(
        "1962'de Riyad'da doğan ve Kur'an ezberini on iki yaşında tamamlayan Suudi kâri "
        "ve imam. Şeriat eğitimi aldı; Mekke'deki Mescid-i Haram'da imam ve hatip olarak "
        "görev yapmasıyla tanındı."
    ),
    country_code="SA",
    profile_source_url="https://saudipedia.com/en/abdulrahman-al-sudais",
)

ABU_BAKR_AL_SHATRI = _profile(
    name_ar="أبو بكر الشاطري",
    name_en="Abu Bakr al-Shatri",
    name_ru="Абу Бакр аш-Шатри",
    name_tr="Ebu Bekir eş-Şatri",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في جدة عام 1970. تلقى دراسات قرآنية على يد الشيخ أيمن سويد، "
        "وحصل على إجازة عام 1996، كما يحمل درجة الماجستير في المحاسبة."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Jeddah in 1970. He studied the Quran under "
        "Shaykh Ayman Suwayd and received an ijazah in 1996; he also holds a master's "
        "degree in accounting."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Джидде в 1970 году. Он изучал Коран у шейха "
        "Аймана Сувейда и получил иджазу в 1996 году; также имеет степень магистра по "
        "бухгалтерскому учёту."
    ),
    biography_tr=(
        "1970'te Cidde'de doğan Suudi kâri ve imam. Şeyh Eymen Süveyd'den Kur'an eğitimi "
        "aldı ve 1996'da icazet aldı; ayrıca muhasebe alanında yüksek lisans derecesine "
        "sahiptir."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/4",
)

AHMED_TAHOUN = _profile(
    name_ar="أحمد عبد الحميد طاحون",
    name_en="Ahmed Abdelhamid Tahoun",
    name_ru="Ахмад Абдульхамид Тахун",
    name_tr="Ahmed Abdülhamid Tahun",
    biography_ar=(
        "قارئ مصري متخصص في علوم القرآن والتلاوة والمقامات. يحمل إجازات في القراءات العشر، "
        "وحصل على درجة البكالوريوس من جامعة الأزهر."
    ),
    biography_en=(
        "An Egyptian reciter specializing in Quranic sciences, recitation, and maqamat. "
        "He holds ijazahs in all ten qira'at and earned a bachelor's degree from Al-Azhar "
        "University."
    ),
    biography_ru=(
        "Египетский чтец, специализирующийся на коранических науках, чтении и макамате. "
        "Он имеет иджазы по всем десяти кираатам и степень бакалавра Университета Аль-Азхар."
    ),
    biography_tr=(
        "Kur'an ilimleri, tilavet ve makamlar konusunda uzmanlaşmış Mısırlı kâri. On "
        "kıraatin tamamında icazet sahibi olup El-Ezher Üniversitesi'nden lisans derecesi "
        "almıştır."
    ),
    country_code="EG",
    profile_source_url="https://quran.com/ar/reciters/176",
)

AHMED_AL_AJMY = _profile(
    name_ar="أحمد بن علي العجمي",
    name_en="Ahmed ibn Ali al-Ajmy",
    name_ru="Ахмад ибн Али аль-Аджми",
    name_tr="Ahmed bin Ali el-Acmi",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في الخبر عام 1968. تخرّج في كلية الشريعة بجامعة الإمام محمد "
        "بن سعود الإسلامية، وعمل إمامًا في عدد من المساجد."
    ),
    biography_en=(
        "A Saudi reciter and imam born in al-Khobar in 1968. He graduated from the College "
        "of Sharia at Imam Muhammad ibn Saud Islamic University and has served as an imam "
        "at several mosques."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Эль-Хубаре в 1968 году. Он окончил факультет "
        "шариата Исламского университета имама Мухаммада ибн Сауда и служил имамом в "
        "нескольких мечетях."
    ),
    biography_tr=(
        "1968'de el-Huber'de doğan Suudi kâri ve imam. İmam Muhammed bin Suud İslam "
        "Üniversitesi Şeriat Fakültesinden mezun olmuş ve çeşitli camilerde imamlık "
        "yapmıştır."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/19",
)

BANDAR_BALEELA = _profile(
    name_ar="بندر بليلة",
    name_en="Bandar Baleela",
    name_ru="Бандар Балиля",
    name_tr="Bender Belile",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في مكة عام 1975. درس في جامعتي أم القرى والمدينة الإسلامية، "
        "وحصل على الدكتوراه في الفقه، وعُرف بإمامته في المسجد الحرام."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Makkah in 1975. He studied at Umm al-Qura and "
        "the Islamic University of Madinah, earned a doctorate in Islamic jurisprudence, "
        "and is known for leading prayers at the Grand Mosque."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Мекке в 1975 году. Он учился в Университете "
        "Умм аль-Кура и Исламском университете Медины, получил докторскую степень по фикху "
        "и известен служением имамом Заповедной мечети."
    ),
    biography_tr=(
        "1975'te Mekke'de doğan Suudi kâri ve imam. Ümmü'l-Kurâ ve Medine İslam "
        "üniversitelerinde eğitim gördü, İslam hukuku alanında doktora yaptı ve Mescid-i "
        "Haram'daki imamlığıyla tanındı."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/160",
)

HANI_AR_RIFAI = _profile(
    name_ar="هاني الرفاعي",
    name_en="Hani ar-Rifai",
    name_ru="Хани ар-Рифаи",
    name_tr="Hani er-Rifai",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في جدة عام 1974. عُرف بتلاوته المؤثرة، وعمل إمامًا وخطيبًا "
        "في مسجد العناني بمدينة جدة."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Jeddah in 1974. Known for his expressive "
        "recitation, he has served as imam and preacher at Anani Mosque in Jeddah."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Джидде в 1974 году. Он известен выразительным "
        "чтением и служением имамом и проповедником мечети Анани в Джидде."
    ),
    biography_tr=(
        "1974'te Cidde'de doğan Suudi kâri ve imam. Etkileyici tilavetiyle tanınır; "
        "Cidde'deki Anani Camii'nde imam ve hatip olarak görev yapmıştır."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/5",
)

MAHER_AL_MUAIQLY = _profile(
    name_ar="ماهر المعيقلي",
    name_en="Maher al-Muaiqly",
    name_ru="Махер аль-Муайкли",
    name_tr="Mahir el-Muaykıli",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في المدينة المنورة عام 1969. بدأ مسيرته مدرسًا للرياضيات، "
        "ثم واصل دراسته الشرعية، وعُرف بإمامته في المسجد الحرام."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Madinah in 1969. He began his career as a "
        "mathematics teacher, later pursued Islamic studies, and became known for leading "
        "prayers at the Grand Mosque."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Медине в 1969 году. Он начинал как учитель "
        "математики, затем продолжил исламское образование и получил известность как имам "
        "Заповедной мечети."
    ),
    biography_tr=(
        "1969'da Medine'de doğan Suudi kâri ve imam. Meslek hayatına matematik öğretmeni "
        "olarak başladı, daha sonra İslami ilimler eğitimi aldı ve Mescid-i Haram'daki "
        "imamlığıyla tanındı."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/159",
)

MAHMOUD_AL_HUSARY = _profile(
    name_ar="محمود خليل الحصري",
    name_en="Mahmoud Khalil al-Husary",
    name_ru="Махмуд Халиль аль-Хусари",
    name_tr="Mahmud Halil el-Husari",
    biography_ar=(
        "قارئ قرآن مصري من قرية شبرا النملة قرب طنطا. حفظ القرآن في صغره، ودرس القراءات "
        "العشر، وكان من أبرز قراء الإذاعة المصرية، واشتهر بدقة أحكام التجويد."
    ),
    biography_en=(
        "An Egyptian Quran reciter from Shubra al-Namlah near Tanta. He memorized the "
        "Quran at an early age, studied the ten qira'at, became a leading Egyptian Radio "
        "reciter, and was renowned for precise tajwid."
    ),
    biography_ru=(
        "Египетский чтец Корана из деревни Шубра ан-Намла близ Танты. Он рано выучил Коран, "
        "изучал десять кираатов, стал одним из ведущих чтецов Египетского радио и прославился "
        "точным соблюдением таджвида."
    ),
    biography_tr=(
        "Tanta yakınlarındaki Şubra en-Nemle köyünden Mısırlı Kur'an kârisi. Kur'an'ı küçük "
        "yaşta ezberledi, on kıraati öğrendi, Mısır Radyosu'nun önde gelen kârilerinden biri "
        "oldu ve titiz tecvidiyle tanındı."
    ),
    country_code="EG",
    profile_source_url="https://quran.com/en/reciters/6",
)

MISHARI_AL_AFASY = _profile(
    name_ar="مشاري راشد العفاسي",
    name_en="Mishari Rashid al-Afasy",
    name_ru="Мишари Рашид аль-Афаси",
    name_tr="Mişari Raşid el-Afasi",
    biography_ar=(
        "قارئ وإمام كويتي وُلد عام 1976. درس القراءات العشر والتفسير في الجامعة الإسلامية "
        "بالمدينة المنورة، واشتهرت تسجيلاته القرآنية في أنحاء العالم."
    ),
    biography_en=(
        "A Kuwaiti reciter and imam born in 1976. He studied the ten qira'at and tafsir at "
        "the Islamic University of Madinah, and his Quran recordings are widely known "
        "around the world."
    ),
    biography_ru=(
        "Кувейтский чтец и имам, родившийся в 1976 году. Он изучал десять кираатов и тафсир "
        "в Исламском университете Медины, а его записи Корана получили широкую известность "
        "во всём мире."
    ),
    biography_tr=(
        "1976 doğumlu Kuveytli kâri ve imam. Medine İslam Üniversitesinde on kıraat ve "
        "tefsir eğitimi aldı; Kur'an kayıtları dünya çapında geniş bir dinleyici kitlesine "
        "ulaştı."
    ),
    country_code="KW",
    profile_source_url="https://quran.com/en/reciters/7",
)

MUHAMMAD_AL_MINSHAWI = _profile(
    name_ar="محمد صديق المنشاوي",
    name_en="Muhammad Siddiq al-Minshawi",
    name_ru="Мухаммад Сиддик аль-Миншави",
    name_tr="Muhammed Sıddık el-Minşavi",
    biography_ar=(
        "قارئ قرآن مصري من صعيد مصر، نشأ في أسرة عُرفت بالتلاوة وتعلّم على يد والده الشيخ "
        "صديق المنشاوي. يُعد من أشهر قراء القرن العشرين، وسُجلت له تلاوات مرتلة ومجوّدة."
    ),
    biography_en=(
        "An Egyptian Quran reciter from Upper Egypt who grew up in a family known for "
        "recitation and studied under his father, Shaykh Siddiq al-Minshawi. He became one "
        "of the best-known reciters of the twentieth century."
    ),
    biography_ru=(
        "Египетский чтец Корана из Верхнего Египта, выросший в семье чтецов и учившийся у "
        "своего отца, шейха Сиддика аль-Миншави. Он стал одним из самых известных чтецов "
        "XX века."
    ),
    biography_tr=(
        "Yukarı Mısır'da, tilavetle tanınan bir ailede yetişen Mısırlı Kur'an kârisi. "
        "Babası Şeyh Sıddık el-Minşavi'den eğitim aldı ve yirminci yüzyılın en tanınmış "
        "kârilerinden biri oldu."
    ),
    country_code="EG",
    profile_source_url="https://quran.com/en/reciters/9",
)

SAUD_ASH_SHURAYM = _profile(
    name_ar="سعود الشريم",
    name_en="Saud ash-Shuraym",
    name_ru="Сауд аш-Шурайм",
    name_tr="Suud eş-Şureym",
    biography_ar=(
        "قارئ وفقيه وإمام سعودي وُلد في الرياض عام 1966. حصل على الدكتوراه في الشريعة من "
        "جامعة أم القرى، وخدم سنوات طويلة إمامًا وخطيبًا في المسجد الحرام."
    ),
    biography_en=(
        "A Saudi reciter, jurist, and imam born in Riyadh in 1966. He earned a doctorate "
        "in Sharia from Umm al-Qura University and served for many years as an imam and "
        "preacher at the Grand Mosque."
    ),
    biography_ru=(
        "Саудовский чтец, правовед и имам, родившийся в Эр-Рияде в 1966 году. Он получил "
        "докторскую степень по шариату в Университете Умм аль-Кура и много лет служил "
        "имамом и проповедником Заповедной мечети."
    ),
    biography_tr=(
        "1966'da Riyad'da doğan Suudi kâri, fakih ve imam. Ümmü'l-Kurâ Üniversitesinden "
        "şeriat doktorası aldı ve uzun yıllar Mescid-i Haram'da imam ve hatip olarak görev "
        "yaptı."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/10",
)

SAAD_AL_GHAMDI = _profile(
    name_ar="سعد الغامدي",
    name_en="Saad al-Ghamdi",
    name_ru="Саад аль-Гамди",
    name_tr="Saad el-Gamidi",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في الدمام عام 1967. أتم حفظ القرآن عام 1990، وعمل إمامًا "
        "في عدد من المساجد، وانتشرت تسجيلاته في بلدان كثيرة."
    ),
    biography_en=(
        "A Saudi reciter and imam born in Dammam in 1967. He completed memorizing the "
        "Quran in 1990, has led prayers in a number of mosques, and his recordings have "
        "reached listeners in many countries."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Даммаме в 1967 году. Он завершил заучивание "
        "Корана в 1990 году, служил имамом в нескольких мечетях, а его записи получили "
        "распространение во многих странах."
    ),
    biography_tr=(
        "1967'de Dammam'da doğan Suudi kâri ve imam. Kur'an ezberini 1990'da tamamladı, "
        "çeşitli camilerde imamlık yaptı ve kayıtları birçok ülkedeki dinleyicilere ulaştı."
    ),
    country_code="SA",
    profile_source_url="https://quran.com/en/reciters/13",
)

YASSER_AD_DUSSARY = _profile(
    name_ar="ياسر الدوسري",
    name_en="Yasser ad-Dosari",
    name_ru="Ясир ад-Дусари",
    name_tr="Yasir ed-Dusari",
    biography_ar=(
        "قارئ وإمام سعودي وُلد في الخرج عام 1980. درس الشريعة، وحصل على الماجستير والدكتوراه "
        "في الفقه المقارن، وهو من أئمة وخطباء المسجد الحرام."
    ),
    biography_en=(
        "A Saudi reciter and imam born in al-Kharj in 1980. He studied Sharia, earned "
        "master's and doctoral degrees in comparative jurisprudence, and is an imam and "
        "preacher at the Grand Mosque in Makkah."
    ),
    biography_ru=(
        "Саудовский чтец и имам, родившийся в Эль-Хардже в 1980 году. Он изучал шариат, "
        "получил степени магистра и доктора по сравнительному фикху и является имамом и "
        "проповедником Заповедной мечети в Мекке."
    ),
    biography_tr=(
        "1980'de el-Harc'da doğan Suudi kâri ve imam. Şeriat eğitimi aldı, mukayeseli "
        "fıkıh alanında yüksek lisans ve doktora yaptı; Mekke'deki Mescid-i Haram'da imam "
        "ve hatip olarak görev yapmaktadır."
    ),
    country_code="SA",
    profile_source_url=(
        "https://saudipedia.com/%D9%8A%D8%A7%D8%B3%D8%B1-%D8%A7%D9%84%D8%AF%D9%88%D8%B3%D8%B1%D9%8A"
    ),
)


RECITER_PROFILES = {
    "qf-2-abdul-baset-abdul-samad": ABDUL_BASET,
    "qf-1-abdulbaset-abdulsamad-mujawwad": ABDUL_BASET,
    "qf-158-abdullah-ali-jabir": ALI_JABER,
    "qf-175-abdullah-hamad-abu-sharida": ABDULLAH_ABU_SHARIDA,
    "qf-3-abdur-rahman-as-sudais": ABDUR_RAHMAN_AS_SUDAIS,
    "qf-4-abu-bakr-al-shatri": ABU_BAKR_AL_SHATRI,
    "qf-176-ahmed-tahoun": AHMED_TAHOUN,
    "qf-19-ahmed-ibn-ali-al-ajmy": AHMED_AL_AJMY,
    "qf-160-bandar-baleela": BANDAR_BALEELA,
    "qf-5-hani-ar-rifai": HANI_AR_RIFAI,
    "qf-159-maher-al-muaiqly": MAHER_AL_MUAIQLY,
    "qf-12-mahmoud-khaleel-al-husary": MAHMOUD_AL_HUSARY,
    "qf-6-mahmoud-khaleel-al-husary": MAHMOUD_AL_HUSARY,
    "qf-7-mishari-rashid-al-afasy": MISHARI_AL_AFASY,
    "qf-9-muhammad-siddiq-al-minshawi": MUHAMMAD_AL_MINSHAWI,
    "qf-10-saud-ash-shuraym": SAUD_ASH_SHURAYM,
    "qf-13-saad-al-ghamdi": SAAD_AL_GHAMDI,
    "qf-174-yasser-ad-dussary": YASSER_AD_DUSSARY,
}

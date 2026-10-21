# ruff: noqa: RUF001
"""Tajweed rule reference shown by the web site and the app.

Codes are the exact `<tajweed class=...>` values of the Quran.Foundation
`quran/verses/uthmani_tajweed` response (all 17 seen on 6236 verses). Colours
come from CPAL palette 0 of the QCF V4 tajweed page fonts (QF Mushaf 19), so
chips match the coloured Mushaf. Texts await a tajweed teacher's review:
docs/tajweed/rules-review.md.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

REFERENCE_VERSION = "2026-10-21"
REVIEW_STATUS = "pending_teacher_review"
LANGUAGES = ("ru", "en", "ar", "tr")


@dataclass(frozen=True, slots=True)
class TajweedVariant:
    code: str
    name: dict[str, str]
    why: dict[str, str]
    how: dict[str, str]


@dataclass(frozen=True, slots=True)
class TajweedRule:
    code: str
    arabic_name: str
    color: str
    name: dict[str, str]
    why: dict[str, str]
    how: dict[str, str]
    variants: tuple[TajweedVariant, ...] = field(default_factory=tuple)

    def as_dict(self) -> dict[str, Any]:
        return {
            "code": self.code,
            "arabic_name": self.arabic_name,
            "color": self.color,
            "name": self.name,
            "why": self.why,
            "how": self.how,
            "variants": [
                {"code": item.code, "name": item.name, "why": item.why, "how": item.how}
                for item in self.variants
            ],
        }


_GREEN = "#09B000"
_GREY = "#A3A5A5"

_SKIP_FIRST_HOW = {
    "ru": "Первую букву не произносите: читайте вторую с удвоением.",
    "en": "Do not pronounce the first letter: read the second one doubled.",
    "ar": "يُدغم الأول في الثاني فيُنطق الثاني مشدّدًا.",
    "tr": "İlk harfi okumayın; ikinciyi şeddeli okuyun.",
}

# Legend order: noon and tanween, meem, ghunnah, qalqalah, madd, silent letters.
TAJWEED_RULES: tuple[TajweedRule, ...] = (
    TajweedRule(
        code="ikhafa",
        arabic_name="الإخفاء",
        color=_GREEN,
        name={"ru": "Ихфа", "en": "Ikhfa", "ar": "الإخفاء", "tr": "İhfâ"},
        why={
            "ru": "Нун с сукуном или танвин перед одной из 15 букв ихфа "
            "(ت ث ج د ذ ز س ش ص ض ط ظ ف ق ك).",
            "en": "A noon with sukun or a tanween before one of the 15 ikhfa letters "
            "(ت ث ج د ذ ز س ش ص ض ط ظ ف ق ك).",
            "ar": "نون ساكنة أو تنوين قبل أحد حروف الإخفاء الخمسة عشر "
            "(ت ث ج د ذ ز س ش ص ض ط ظ ف ق ك).",
            "tr": "Sakin nûn veya tenvin, 15 ihfâ harfinden birinden önce "
            "(ت ث ج د ذ ز س ش ص ض ط ظ ف ق ك).",
        },
        how={
            "ru": "Не выговаривайте нун полностью: язык не касается нёба, звук идёт "
            "через нос 2 хараката и готовится к следующей букве.",
            "en": "Do not fully pronounce the noon: keep the tongue off the palate and "
            "carry the sound through the nose for 2 counts, ready for the next letter.",
            "ar": "أخفِ النون دون أن يعتمد اللسان على مخرجها، مع غنة بمقدار حركتين "
            "تتهيأ فيها للحرف التالي.",
            "tr": "Nûnu tam söylemeyin: dil damağa değmeden ses 2 hareke genizden gelsin "
            "ve sonraki harfe hazırlanın.",
        },
    ),
    TajweedRule(
        code="idgham_ghunnah",
        arabic_name="الإدغام بغنة",
        color=_GREEN,
        name={
            "ru": "Идгам с гунной",
            "en": "Idgham with ghunnah",
            "ar": "الإدغام بغنة",
            "tr": "Gunneli idğâm",
        },
        why={
            "ru": "Нун с сукуном или танвин в конце слова перед одной из букв ي ن م و.",
            "en": "A noon with sukun or a tanween at the end of a word before ي ن م و.",
            "ar": "نون ساكنة أو تنوين في آخر الكلمة قبل أحد حروف «ينمو».",
            "tr": "Kelime sonundaki sakin nûn veya tenvin, ي ن م و harflerinden önce.",
        },
        how={
            "ru": "Слейте нун со следующей буквой и удерживайте носовой звук 2 хараката.",
            "en": "Merge the noon into the next letter and hold the nasal sound for 2 counts.",
            "ar": "أدغم النون في الحرف التالي مع غنة بمقدار حركتين.",
            "tr": "Nûnu sonraki harfe katın ve genizden gelen sesi 2 hareke tutun.",
        },
    ),
    TajweedRule(
        code="idgham_wo_ghunnah",
        arabic_name="الإدغام بغير غنة",
        color=_GREY,
        name={
            "ru": "Идгам без гунны",
            "en": "Idgham without ghunnah",
            "ar": "الإدغام بغير غنة",
            "tr": "Gunnesiz idğâm",
        },
        why={
            "ru": "Нун с сукуном или танвин в конце слова перед ل или ر.",
            "en": "A noon with sukun or a tanween at the end of a word before ل or ر.",
            "ar": "نون ساكنة أو تنوين في آخر الكلمة قبل اللام أو الراء.",
            "tr": "Kelime sonundaki sakin nûn veya tenvin, ل veya ر harfinden önce.",
        },
        how={
            "ru": "Нун не произносится: сразу читайте удвоенную ل или ر, без носового звука.",
            "en": "The noon is not pronounced: go straight to a doubled ل or ر, "
            "with no nasal sound.",
            "ar": "تُدغم النون إدغامًا كاملًا في اللام أو الراء بلا غنة.",
            "tr": "Nûn okunmaz; genizden ses vermeden doğrudan şeddeli ل veya ر okuyun.",
        },
    ),
    TajweedRule(
        code="iqlab",
        arabic_name="الإقلاب",
        color=_GREEN,
        name={"ru": "Икляб", "en": "Iqlab", "ar": "الإقلاب", "tr": "İklâb"},
        why={
            "ru": "Нун с сукуном или танвин перед ب; в мусхафе над ним малая буква мим ۢ.",
            "en": "A noon with sukun or a tanween before ب; the Mushaf marks it "
            "with a small meem ۢ.",
            "ar": "نون ساكنة أو تنوين قبل الباء، وتُرسم فوقها ميم صغيرة ۢ.",
            "tr": "Sakin nûn veya tenvin, ب harfinden önce; Mushaf'ta üzerinde küçük mîm ۢ bulunur.",
        },
        how={
            "ru": "Замените нун скрытым мимом: губы смыкаются мягко, носовой звук "
            "2 хараката, затем ب.",
            "en": "Turn the noon into a hidden meem: close the lips lightly, hold the nasal "
            "sound for 2 counts, then say ب.",
            "ar": "اقلب النون ميمًا مخفاة بغنة بمقدار حركتين ثم انطق الباء.",
            "tr": "Nûnu gizli bir mîme çevirin: dudaklar hafifçe kapanır, 2 hareke genizden "
            "ses verilir, sonra ب okunur.",
        },
    ),
    TajweedRule(
        code="ikhafa_shafawi",
        arabic_name="الإخفاء الشفوي",
        color=_GREEN,
        name={
            "ru": "Ихфа шафави",
            "en": "Labial ikhfa",
            "ar": "الإخفاء الشفوي",
            "tr": "İhfâ-i şefevî",
        },
        why={
            "ru": "Мим с сукуном перед буквой ب.",
            "en": "A meem with sukun before the letter ب.",
            "ar": "ميم ساكنة قبل الباء.",
            "tr": "Sakin mîm, ب harfinden önce.",
        },
        how={
            "ru": "Сомкните губы мягко, без нажима, удерживайте носовой звук 2 хараката "
            "и переходите к ب.",
            "en": "Close the lips lightly, hold the nasal sound for 2 counts, then say ب.",
            "ar": "أطبق الشفتين برفق مع غنة بمقدار حركتين ثم انطق الباء.",
            "tr": "Dudakları hafifçe kapatın, genizden gelen sesi 2 hareke tutun, sonra ب okuyun.",
        },
    ),
    TajweedRule(
        code="idgham_shafawi",
        arabic_name="الإدغام الشفوي",
        color=_GREEN,
        name={
            "ru": "Идгам шафави",
            "en": "Labial idgham",
            "ar": "الإدغام الشفوي",
            "tr": "İdğâm-ı şefevî",
        },
        why={
            "ru": "Мим с сукуном перед другой буквой م.",
            "en": "A meem with sukun before another م.",
            "ar": "ميم ساكنة قبل ميم متحركة.",
            "tr": "Sakin mîm, başka bir م harfinden önce.",
        },
        how={
            "ru": "Слейте два мима в один с удвоением и удерживайте гунну 2 хараката.",
            "en": "Merge the two meems into one doubled meem and hold the ghunnah for 2 counts.",
            "ar": "أدغم الميمين ميمًا واحدة مشدّدة مع غنة بمقدار حركتين.",
            "tr": "İki mîmi tek şeddeli mîm olarak okuyun ve gunneyi 2 hareke tutun.",
        },
    ),
    TajweedRule(
        code="ghunnah",
        arabic_name="الغنة",
        color=_GREEN,
        name={"ru": "Гунна", "en": "Ghunnah", "ar": "الغنة", "tr": "Gunne"},
        why={
            "ru": "Нун или мим с шаддой (نّ مّ).",
            "en": "A noon or meem with a shadda (نّ مّ).",
            "ar": "نون أو ميم مشدّدة (نّ مّ).",
            "tr": "Şeddeli nûn veya mîm (نّ مّ).",
        },
        how={
            "ru": "Удерживайте носовой звук 2 хараката.",
            "en": "Hold the nasal sound for 2 counts.",
            "ar": "أظهر الغنة بمقدار حركتين.",
            "tr": "Genizden gelen sesi 2 hareke tutun.",
        },
    ),
    TajweedRule(
        code="qalaqah",
        arabic_name="القلقلة",
        color="#2FADFF",
        name={"ru": "Калькаля", "en": "Qalqalah", "ar": "القلقلة", "tr": "Kalkale"},
        why={
            "ru": "Буква калькали (ق ط ب ج د) с сукуном.",
            "en": "A qalqalah letter (ق ط ب ج د) with a sukun.",
            "ar": "أحد حروف «قطب جد» ساكنًا.",
            "tr": "Kalkale harflerinden biri (ق ط ب ج د) sükûnlu.",
        },
        how={
            "ru": "Произнесите букву с лёгким отскоком — коротким эхом, не добавляя гласного.",
            "en": "Pronounce the letter with a light bounce — a short echo without adding a vowel.",
            "ar": "انطق الحرف بنبرة قلقلة خفيفة دون أن تضيف إليه حركة.",
            "tr": "Harfi ünlü eklemeden hafif bir yankıyla okuyun.",
        },
        variants=(
            TajweedVariant(
                code="stop",
                name={
                    "ru": "при остановке",
                    "en": "when stopping",
                    "ar": "عند الوقف",
                    "tr": "vakıfta",
                },
                why={
                    "ru": "Буква калькали в конце слова: при остановке огласовка уходит "
                    "и буква становится сакин.",
                    "en": "A qalqalah letter ends the word: when you stop, its vowel drops "
                    "and the letter becomes still.",
                    "ar": "حرف القلقلة في آخر الكلمة يُسكَّن عند الوقف.",
                    "tr": "Kalkale harfi kelimenin sonundadır; durunca harekesi düşer ve "
                    "harf sakin olur.",
                },
                how={
                    "ru": "Останавливаясь здесь, сделайте отскок отчётливее; при слитном "
                    "чтении читайте огласовку как обычно.",
                    "en": "When you stop here, make the bounce clearer; when reading on, "
                    "pronounce the vowel as usual.",
                    "ar": "عند الوقف تكون القلقلة أوضح، وفي الوصل تُقرأ الحركة كما هي.",
                    "tr": "Burada dururken yankıyı daha belirgin yapın; bağlayarak okurken "
                    "harekeyi normal okuyun.",
                },
            ),
        ),
    ),
    TajweedRule(
        code="madda_necessary",
        arabic_name="المد اللازم",
        color="#B50000",
        name={
            "ru": "Мадд лязим",
            "en": "Necessary madd",
            "ar": "المد اللازم",
            "tr": "Medd-i lâzım",
        },
        why={
            "ru": "После буквы мадда — постоянный сукун или шадда; так же в отдельных "
            "буквах в начале сур (الٓمٓ).",
            "en": "A madd letter is followed by a permanent sukun or shadda; also in the "
            "opening letters of some surahs (الٓمٓ).",
            "ar": "جاء بعد حرف المد سكون أصلي أو شدّة، ومنه الحروف المقطّعة في أوائل السور (الٓمٓ).",
            "tr": "Medd harfinden sonra aslî sükûn veya şedde gelir; bazı surelerin "
            "başındaki harflerde de (الٓمٓ).",
        },
        how={
            "ru": "Всегда тяните на 6 харакатов.",
            "en": "Always lengthen for 6 counts.",
            "ar": "يُمدّ ستّ حركات لزومًا.",
            "tr": "Her zaman 6 hareke uzatın.",
        },
    ),
    TajweedRule(
        code="madda_obligatory",
        arabic_name="المد الواجب",
        color="#F40000",
        name={
            "ru": "Мадд ваджиб",
            "en": "Obligatory madd",
            "ar": "المد الواجب",
            "tr": "Medd-i vâcib",
        },
        why={
            "ru": "За буквой мадда следует хамза — в том же слове (муттасыль) или "
            "в начале следующего (мунфасыль).",
            "en": "A madd letter is followed by a hamza — in the same word (muttasil) "
            "or at the start of the next one (munfasil).",
            "ar": "جاء بعد حرف المد همز في الكلمة نفسها (متصل) أو في أول الكلمة التالية (منفصل).",
            "tr": "Medd harfinden sonra hemze gelir: aynı kelimede (muttasıl) veya "
            "sonraki kelimenin başında (munfasıl).",
        },
        how={
            "ru": "Тяните на 4–5 харакатов, одинаково во всём чтении.",
            "en": "Lengthen for 4–5 counts, the same way throughout your recitation.",
            "ar": "يُمدّ أربع حركات أو خمسًا مع التسوية في التلاوة كلها.",
            "tr": "4–5 hareke uzatın ve okuma boyunca aynı uzunlukta tutun.",
        },
        variants=(
            TajweedVariant(
                code="silah_kubra",
                name={
                    "ru": "Мадд силя кубра",
                    "en": "Major silah",
                    "ar": "الصلة الكبرى",
                    "tr": "Sıla-i kübrâ",
                },
                why={
                    "ru": "Хаъ местоимения стоит между огласованными буквами, а после неё — хамза.",
                    "en": "The pronoun ha stands between voweled letters and is followed "
                    "by a hamza.",
                    "ar": "هاء الضمير بين متحركين وبعدها همز.",
                    "tr": "Zamir hâsı iki harekeli harf arasındadır ve ardından hemze gelir.",
                },
                how={
                    "ru": "При слитном чтении тяните на 4–5 харакатов; при остановке на "
                    "этом слове удлинение не читается.",
                    "en": "Lengthen for 4–5 counts when reading on; if you stop on this "
                    "word, drop it.",
                    "ar": "تُمدّ أربع حركات أو خمسًا وصلًا، وتسقط عند الوقف.",
                    "tr": "Bağlayarak okurken 4–5 hareke uzatın; bu kelimede durursanız "
                    "uzatma okunmaz.",
                },
            ),
        ),
    ),
    TajweedRule(
        code="madda_permissible",
        arabic_name="المد الجائز",
        color="#FF7B00",
        name={
            "ru": "Мадд джаиз",
            "en": "Permissible madd",
            "ar": "المد الجائز",
            "tr": "Medd-i câiz",
        },
        why={
            "ru": "Буква мадда или лин перед последней буквой слова, на которой делается "
            "остановка.",
            "en": "A madd or leen letter before the final letter where you stop.",
            "ar": "حرف مد أو لين قبل حرف يُسكَّن للوقف.",
            "tr": "Durulan son harften önce gelen medd veya lîn harfi.",
        },
        how={
            "ru": "При остановке тяните на 2, 4 или 6 харакатов, выбрав одну длину для "
            "всего чтения. Без остановки это удлинение не действует.",
            "en": "When stopping, lengthen for 2, 4 or 6 counts, keeping one length "
            "throughout. Without a stop this lengthening does not apply.",
            "ar": "عند الوقف يجوز المدّ حركتين أو أربعًا أو ستًّا مع التزام وجه واحد، "
            "ولا يثبت هذا المدّ في الوصل.",
            "tr": "Dururken 2, 4 veya 6 hareke uzatın ve okuma boyunca aynı uzunluğu "
            "koruyun. Durmadan okurken bu uzatma uygulanmaz.",
        },
    ),
    TajweedRule(
        code="madda_normal",
        arabic_name="المد الطبيعي",
        color="#CE9E00",
        name={
            "ru": "Мадд табии",
            "en": "Natural madd",
            "ar": "المد الطبيعي",
            "tr": "Medd-i tabîî",
        },
        why={
            "ru": "Буква мадда (ا و ي или малые ـٰ ۥ ۦ), после которой нет ни хамзы, ни сукуна.",
            "en": "A madd letter (ا و ي or the small ـٰ ۥ ۦ) with no hamza or sukun after it.",
            "ar": "حرف مد (ا و ي أو الصغيرة ـٰ ۥ ۦ) لم يأتِ بعده همز ولا سكون.",
            "tr": "Medd harfi (ا و ي ya da küçük ـٰ ۥ ۦ); ardından hemze veya sükûn gelmez.",
        },
        how={
            "ru": "Тяните звук ровно на 2 хараката.",
            "en": "Lengthen the sound for exactly 2 counts.",
            "ar": "يُمدّ بمقدار حركتين.",
            "tr": "Sesi tam 2 hareke uzatın.",
        },
        variants=(
            TajweedVariant(
                code="silah_sughra",
                name={
                    "ru": "Мадд силя сугра",
                    "en": "Minor silah",
                    "ar": "الصلة الصغرى",
                    "tr": "Sıla-i suğrâ",
                },
                why={
                    "ru": "Хаъ местоимения (ـهُۥ / ـهِۦ) стоит между огласованными буквами, "
                    "и после неё нет хамзы.",
                    "en": "The pronoun ha (ـهُۥ / ـهِۦ) stands between voweled letters "
                    "with no hamza after it.",
                    "ar": "هاء الضمير (ـهُۥ / ـهِۦ) بين متحركين وليس بعدها همز.",
                    "tr": "Zamir hâsı (ـهُۥ / ـهِۦ) iki harekeli harf arasındadır ve ardından "
                    "hemze gelmez.",
                },
                how={
                    "ru": "При слитном чтении тяните на 2 хараката; при остановке на этом "
                    "слове удлинение не читается.",
                    "en": "Lengthen for 2 counts when reading on; if you stop on this word, "
                    "drop it.",
                    "ar": "تُمدّ حركتين وصلًا، وتسقط عند الوقف.",
                    "tr": "Bağlayarak okurken 2 hareke uzatın; bu kelimede durursanız "
                    "uzatma okunmaz.",
                },
            ),
        ),
    ),
    TajweedRule(
        code="idgham_mutajanisayn",
        arabic_name="إدغام المتجانسين",
        color=_GREY,
        name={
            "ru": "Идгам мутаджанисайн",
            "en": "Idgham of kindred letters",
            "ar": "إدغام المتجانسين",
            "tr": "Mütecâniseyn idğâmı",
        },
        why={
            "ru": "Первая из двух букв с одним местом выхода стоит с сукуном "
            "(например, د перед ت: قَد تَّبَيَّنَ).",
            "en": "The first of two letters sharing one point of articulation has a sukun "
            "(e.g. د before ت: قَد تَّبَيَّنَ).",
            "ar": "التقى حرفان اتّحدا مخرجًا واختلفا صفةً، والأول ساكن "
            "(مثل الدال قبل التاء: قَد تَّبَيَّنَ).",
            "tr": "Mahreci aynı iki harften ilki sakindir (ör. ت'den önce د: قَد تَّبَيَّنَ).",
        },
        how=_SKIP_FIRST_HOW,
    ),
    TajweedRule(
        code="idgham_mutaqaribayn",
        arabic_name="إدغام المتقاربين",
        color=_GREY,
        name={
            "ru": "Идгам мутакарибайн",
            "en": "Idgham of close letters",
            "ar": "إدغام المتقاربين",
            "tr": "Mütekâribeyn idğâmı",
        },
        why={
            "ru": "Первая из двух близких по выходу букв стоит с сукуном: ل перед ر "
            "(قُل رَّبِّ) или ق перед ك (نَخْلُقكُّم).",
            "en": "The first of two letters with close points of articulation has a sukun: "
            "ل before ر (قُل رَّبِّ) or ق before ك (نَخْلُقكُّم).",
            "ar": "التقى حرفان تقاربا مخرجًا والأول ساكن: اللام قبل الراء (قُل رَّبِّ) "
            "أو القاف قبل الكاف (نَخْلُقكُّم).",
            "tr": "Mahrecleri yakın iki harften ilki sakindir: ر'dan önce ل (قُل رَّبِّ) "
            "veya ك'dan önce ق (نَخْلُقكُّم).",
        },
        how=_SKIP_FIRST_HOW,
    ),
    TajweedRule(
        code="ham_wasl",
        arabic_name="همزة الوصل",
        color="#9FA5A5",
        name={
            "ru": "Хамзату-ль-васль",
            "en": "Hamzat al-wasl",
            "ar": "همزة الوصل",
            "tr": "Vasl hemzesi",
        },
        why={
            "ru": "Соединительная хамза ٱ в начале слова: в связном чтении она не звучит.",
            "en": "A connecting hamza ٱ at the start of a word: it is silent when you read on.",
            "ar": "همزة في أول الكلمة تثبت في الابتداء وتسقط في الوصل.",
            "tr": "Kelime başındaki vasl hemzesi ٱ: önceki kelimeye bağlanınca okunmaz.",
        },
        how={
            "ru": "Соединяя слово с предыдущим, не произносите её. Начиная чтение с этого "
            "слова, произнесите хамзу: перед ال — с фатхой, в остальных словах — с кясрой "
            "или даммой.",
            "en": "Skip it when joining to the previous word. When you start from this "
            "word, pronounce a hamza: with fatha before ال, otherwise with kasra or damma.",
            "ar": "لا تُنطق عند الوصل بما قبلها، وتُنطق عند الابتداء: مفتوحة في «ال»، "
            "ومكسورة أو مضمومة في غيرها.",
            "tr": "Önceki kelimeye bağlarken okumayın. Bu kelimeyle başlarsanız hemzeyi "
            "okuyun: ال'de üstünle, diğerlerinde esre veya ötreyle.",
        },
    ),
    TajweedRule(
        code="laam_shamsiyah",
        arabic_name="اللام الشمسية",
        color=_GREY,
        name={
            "ru": "Лям шамсия",
            "en": "Lam shamsiyyah",
            "ar": "اللام الشمسية",
            "tr": "Şemsî lâm",
        },
        why={
            "ru": "Лям артикля ال перед «солнечной» буквой: следующая буква стоит с шаддой.",
            "en": "The lam of ال before a sun letter: the next letter carries a shadda.",
            "ar": "لام «ال» قبل حرف شمسي، والحرف بعدها مشدَّد.",
            "tr": "ال takısının lâmı şemsî harften önce gelir; sonraki harf şeddelidir.",
        },
        how={
            "ru": "Лям не произносится: сразу читайте следующую букву с удвоением.",
            "en": "Do not pronounce the lam: go straight to the doubled letter after it.",
            "ar": "لا تُنطق اللام، بل يُنطق الحرف الشمسي بعدها مشدَّدًا.",
            "tr": "Lâmı okumayın; doğrudan sonraki şeddeli harfe geçin.",
        },
    ),
    TajweedRule(
        code="slnt",
        arabic_name="حرف لا يُنطق",
        color=_GREY,
        name={
            "ru": "Непроизносимая буква",
            "en": "Silent letter",
            "ar": "حرف لا يُنطق",
            "tr": "Okunmayan harf",
        },
        why={
            "ru": "Буква записана по османской орфографии мусхафа, но в чтении не звучит.",
            "en": "The letter belongs to the Uthmani spelling of the Mushaf but is not pronounced.",
            "ar": "حرف ثابت في الرسم العثماني ولا يُنطق في التلاوة.",
            "tr": "Harf, Mushaf'ın resm-i Osmânî imlasında yazılır ama okunmaz.",
        },
        how={
            "ru": "Пропустите эту букву и читайте дальше по огласовкам.",
            "en": "Skip this letter and read on following the vowel marks.",
            "ar": "تجاوز هذا الحرف واقرأ ما بعده بحسب الحركات.",
            "tr": "Bu harfi atlayın ve harekelere göre okumaya devam edin.",
        },
    ),
)

RULES_BY_CODE = {rule.code: rule for rule in TAJWEED_RULES}
RULE_ORDER = {rule.code: index for index, rule in enumerate(TAJWEED_RULES)}


def rules_reference() -> dict[str, Any]:
    return {
        "version": REFERENCE_VERSION,
        "review_status": REVIEW_STATUS,
        "languages": list(LANGUAGES),
        "rules": [rule.as_dict() for rule in TAJWEED_RULES],
    }

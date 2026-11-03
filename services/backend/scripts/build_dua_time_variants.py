"""Build hisn_al_muslim_time_variants_v1.json from the bundled Hisn al-Muslim snapshot.

The morning and evening adhkar cards both show chapter 27. Where the book keeps both
readings in one entry («in the evening say…», «утром (вечером)»), this script derives
each card's own reading from the source text, so every change is a visible replacement
of a quoted source fragment. Run it from anywhere; it rewrites the data file in place.
"""

# The replacements quote the source text verbatim, in Cyrillic and Turkish.
# ruff: noqa: E501, RUF001

from __future__ import annotations

import json
import re
from pathlib import Path

data_dir = Path(__file__).resolve().parents[1] / "src/quran_backend/modules/dua/data"
src = json.loads((data_dir / "hisn_al_muslim_full_v1.json").read_text(encoding="utf-8"))
A, T = {}, {}
for e in src["entries"]:
    A[e["source_number"]] = e["arabic_text"]
    T[e["source_number"]] = {t["language"]: t for t in e["translations"]}

HARAKAT = "[ً-ٰٟـ]*"


def plain(s):
    return re.sub(HARAKAT, "", s)


def fuzzy(s):
    return HARAKAT.join(re.escape(c) for c in plain(s)) + HARAKAT


def ar_sub(text, old, new):
    pattern = fuzzy(old)
    assert re.search(pattern, text), ("missing", old)
    return re.sub(pattern, new, text, count=1)


def sub(text, old, new):
    assert old in text, ("missing", old, text[:80])
    return text.replace(old, new, 1)


def ar_before_note(n):
    text = A[n]
    i = text.index("[")
    return text[:i].rstrip(" .") + ("." if text[:i].rstrip().endswith(".") else "")


def m(n, lang):
    return T[n][lang]["meaning_text"]


def tr(n, lang):
    return T[n][lang].get("transliteration", "")


V = {}


def put(n, time, arabic=None, **langs):
    V.setdefault(n, {})[time] = {"arabic_text": arabic, "translations": langs}


# 77 -------------------------------------------------------------------
ar77m = ar_before_note(77)
ar77e = ar_sub(ar77m, "أَصْبَحْنَا وَأَصْبَحَ", "أَمْسَيْنَا وَأَمْسَى")
ar77e = ar_sub(ar77e, "خَيْرَ مَا فِي هَذَا الْيَوْمِ وَخَيرَ مَا بَعْدَهُ", "خَيْرَ مَا فِي هَذِهِ اللَّيْلَةِ وَخَيْرَ مَا بَعْدَهَا")
ar77e = ar_sub(ar77e, "شَرِّ مَا فِي هَذَا الْيَوْمِ وَشَرِّ مَا بَعْدَهُ", "شَرِّ مَا فِي هَذِهِ اللَّيْلَةِ وَشَرِّ مَا بَعْدَهَا")
ru77 = m(77, "ru")
ru77m = sub(
    ru77,
    " (мы дожили до вечера, и этим вечером владычество принадлежит Аллаху) (Это читается вечером.)",
    "",
)
ru77m = sub(
    ru77m,
    " (Господь мой, прошу Тебя о благе того, что будет в эту ночь, и благе того, что за ней последует, и прибегаю к Тебе от зла того, что будет в эту ночь, и зла того, что за ней последует) (Это читается вечером.) Господь",
    ". Господь",
)
ru77e = (
    "Мы дожили до вечера, и этим вечером владычество принадлежит Аллаху (В комментариях ан-Навави указывается, что эти слова поясняют собой состояние произносящего их человека, убедившегося в том, что и этим вечером владычество принадлежит Аллаху, как принадлежит оно Ему всегда.) "
    "и хвала Аллаху, нет бога, кроме одного лишь Аллаха, у которого нет сотоварища. Ему принадлежит владычество, Ему хвала, Он всё может. "
    "Господь мой, прошу Тебя о благе того, что будет в эту ночь, и благе того, что за ней последует, и прибегаю к Тебе от зла того, что будет в эту ночь, и зла того, что за ней последует. "
    "Господь мой, прибегаю к Тебе от нерадения и старческой дряхлости, Господь мой, прибегаю к Тебе от мучений в огне и мучений в могиле!"
)
assert ru77m.endswith("Господь мой, прибегаю к Тебе от мучений в огне и мучений в могиле!"), ru77m[
    -80:
]
rutr77_tail = "ва-ль-хамду ли-Лляхи, ля иляха илля Ллаху вахда-ху ля шарикя ля-ху, ля-ху-ль-мульку ва ля-ху-ль-хамду ва хуа 'аля кулли шайин кадирун. "
rutr77m = (
    "Асбахна ва асбаха-ль-мульку ли-Лляхи "
    + rutr77_tail
    + "Рабби, ас'алю-кя хайра ма фи хаза-ль-йауми ва хайра ма ба'да-ху ва а'узу би-кя мин шарри ма фи хаза-ль-йауми ва шарри ма ба'да-ху! "
    "Рабби, а'узу би-кя мин аль-кясали ва суи-ль-кибари, Рабби, а'узу би-кя мин 'азабин фи-н-нари ва 'азабин фи-ль-кабри!"
)
rutr77e = (
    "Амсайна ва амса-ль-мульку ли-Лляхи "
    + rutr77_tail
    + "Рабби, ас'алю-кя хайра ма фи хазихи-ль-лейляти ва хайра ма ба'да-ха ва а'узу би-кя мин шарри ма фи хазихи-ль-лейляти ва шарри ма ба'да-ха! "
    "Рабби, а'узу би-кя мин аль-кясали ва суи-ль-кибари, Рабби, а'узу би-кя мин 'азабин фи-н-нари ва 'азабин фи-ль-кабри!"
)
en77_tail = "None has the right to be worshipped except Allah, alone, without any partner, to Him belong all sovereignty and praise and He is over all things omnipotent. "
en77e = (
    "We have reached the evening and at this very time unto Allah belongs all sovereignty, and all praise is for Allah. "
    + en77_tail
    + "My Lord, I ask You for the good of this night and the good of what follows it and I take refuge in You from the evil of this night and the evil of what follows it. "
    "My Lord, I take refuge in You from laziness and senility. My Lord, I take refuge in You from torment in the Fire and punishment in the grave."
)
entr77 = "walhamdu lillah la ilaha illal-lah, wahdahu la shareeka lah, lahul-mulku walahul-hamd, wahuwa AAala kulli shayin qadeer, "
entr77_end = "rabbi aAAoothu bika minal-kasal, wasoo-il kibar, rabbi aAAoothu bika min AAathabin fin-nar, waAAathabin fil-qabr."
entr77m = (
    "Asbahna wa-asbahal-mulku lillah "
    + entr77
    + "rabbi as-aluka khayra ma fee hathal-yawm, wakhayra ma baAAdah, wa-aAAoothu bika min sharri ma fee hathal-yawm, washarri ma baAAdah, "
    + entr77_end
)
entr77e = (
    "Amsayna wa-amsal-mulku lillah "
    + entr77
    + "rabbi as-aluka khayra ma fee hathihil-laylah, wakhayra ma baAAdaha, wa-aAAoothu bika min sharri ma fee hathihil-laylah, washarri ma baAAdaha, "
    + entr77_end
)
tr77e = (
    "Mülk, devamlı Allah’a âit bir halde akşamladık. Hamd Allah’adır. Allah’tan başka hak ilah yoktur. O, tektir ve ortağı yoktur. Mülk O’nundur. Hamd da O’nadır. O, her şeye gücü yetendir. "
    "Rabbim! Senden bu gecede ve bu geceden sonra iyiliklerini isterim; bu gecenin şerrinden ve bu geceden sonra (meydana gelecek olan) şerden de sana sığınırım. "
    "Rabbim! Tembellikten ve (aklını yitirmek ve bunamak gibi) kötü yaşlılıktan sana sığınırım. Rabbim! Cehennem ve kabir azabından sana sığınırım."
)
put(
    77,
    "morning",
    ar77m,
    ru={"meaning_text": ru77m, "transliteration": rutr77m},
    en={"meaning_text": m(77, "en"), "transliteration": entr77m},
)
put(
    77,
    "evening",
    ar77e,
    ru={"meaning_text": ru77e, "transliteration": rutr77e},
    en={"meaning_text": en77e, "transliteration": entr77e},
    tr={"meaning_text": tr77e},
)

# 78 -------------------------------------------------------------------
ar78m = ar_before_note(78)
ar78e = ar_sub(ar78m, "بِكَ أَصْبَحْنَا، وَبِكَ أَمْسَيْنَا", "بِكَ أَمْسَيْنَا، وَبِكَ أَصْبَحْنَا")
ar78e = ar_sub(ar78e, "نَمُوتُ وَإِلَيْكَ النُّشُورُ", "نَمُوتُ، وَإِلَيْكَ الْمَصِيرُ")
en78m, en78e = (part.strip() for part in m(78, "en").split("[In the evening:]"))
entr78m, entr78e = (part.strip() for part in tr(78, "en").split("[In the evening:]"))
ru78 = m(78, "ru")
i = ru78.index(" О Аллах, благодаря Тебе мы дожили до вечера")
ru78m, ru78e = ru78[:i].strip(), ru78[i:].strip()
rutr78 = tr(78, "ru")
rutr78m = rutr78[: rutr78.index('" (Это читается утром).')].strip() + "."
rutr78e = (
    rutr78[
        rutr78.index("Аллахумма, би-кя амсайна") : rutr78.index('" (Это читается вечером).')
    ].strip()
    + "."
)
tr78e = (
    "Allahım! Senin (nimetin, koruman ve zikrin) ile akşamlarız ve senin (nimetin, koruman ve zikrin) ile sabahlarız. "
    "Senin yardımınla yaşar ve senin yardımınla ölürüz. Ve (kıyâmet günü) dönüş, yalnızca sanadır."
)
put(
    78,
    "morning",
    ar78m,
    ru={"meaning_text": ru78m, "transliteration": rutr78m},
    en={"meaning_text": en78m, "transliteration": entr78m},
)
put(
    78,
    "evening",
    ar78e,
    ru={"meaning_text": ru78e, "transliteration": rutr78e},
    en={"meaning_text": en78e, "transliteration": entr78e},
    tr={"meaning_text": tr78e},
)

# 80 -------------------------------------------------------------------
ar80m = ar_before_note(80)
ar80e = ar_sub(ar80m, "أَصْبَحْتُ", "أَمْسَيْتُ")
en80m = sub(
    m(80, "en"),
    "(four times in the morning & evening)(Note: for the evening, one reads (amsaytu) instead of (asbahtu).)",
    "(four times)",
)
en80e = sub(en80m, "I have reached the morning", "I have reached the evening")
entr80m = sub(
    tr(80, "en"),
    "(four times in the morning & evening)(Note: for the evening, one reads (amsaytu) instead of (asbahtu).)",
    "(four times)",
)
entr80e = sub(entr80m, "asbahtu", "amsaytu")
ru80 = m(80, "ru")
ru80m = sub(
    sub(ru80, "этим утром (этим вечером)", "этим утром"),
    "делать это утром или вечером",
    "делать это утром",
)
ru80e = sub(
    sub(ru80, "этим утром (этим вечером)", "этим вечером"),
    "делать это утром или вечером",
    "делать это вечером",
)
ru80m, ru80e = (s.replace("огня).", "огня.)") for s in (ru80m, ru80e))
rutr80m = sub(tr(80, "ru"), "асбахту (инни амсайту)", "асбахту").rstrip('".') + "."
rutr80e = sub(tr(80, "ru"), "асбахту (инни амсайту)", "амсайту").rstrip('".') + "."
tr80e = sub(sub(m(80, "tr"), "sabahladım3", "akşamladım"), "taşıyanları,2", "taşıyanları,")
put(
    80,
    "morning",
    ar80m,
    ru={"meaning_text": ru80m, "transliteration": rutr80m},
    en={"meaning_text": en80m, "transliteration": entr80m},
)
put(
    80,
    "evening",
    ar80e,
    ru={"meaning_text": ru80e, "transliteration": rutr80e},
    en={"meaning_text": en80e, "transliteration": entr80e},
    tr={"meaning_text": tr80e},
)

# 81 -------------------------------------------------------------------
ar81m = ar_before_note(81)
ar81e = ar_sub(ar81m, "مَا أَصْبَحَ بِي", "مَا أَمْسَى بِي")
en81 = m(81, "en")
en81m = sub(
    en81,
    " and whoever says this in the evening has indeed offered his night’s thanks.)(Note: for the evening, one reads (amsa) instead of (asbaha).)",
    ".)",
)
en81e = sub(
    sub(
        en81,
        "whoever says this in the morning has indeed offered his day’s thanks and whoever says this in the evening",
        "whoever says this in the evening",
    ),
    "(Note: for the evening, one reads (amsa) instead of (asbaha).)",
    "",
)
en81e = sub(en81e, "have risen upon", "have reached the evening with")
entr81m = sub(tr(81, "en"), "(Note: for the evening, one reads (amsa) instead of (asbaha).)", "")
entr81e = sub(entr81m, "ma asbaha bee", "ma amsa bee")
ru81m = sub(m(81, "ru"), "этим утром (вечером)", "этим утром")
ru81e = sub(m(81, "ru"), "этим утром (вечером)", "этим вечером")
rutr81m = sub(tr(81, "ru"), "ма асбаха (ма амса) би", "ма асбаха би")
rutr81e = sub(tr(81, "ru"), "ма асбаха (ма амса) би", "ма амса би")
tr81e = sub(m(81, "tr"), "sabaha5 çıkan", "akşama çıkan")
put(
    81,
    "morning",
    ar81m,
    ru={"meaning_text": ru81m, "transliteration": rutr81m},
    en={"meaning_text": en81m, "transliteration": entr81m},
)
put(
    81,
    "evening",
    ar81e,
    ru={"meaning_text": ru81e, "transliteration": rutr81e},
    en={"meaning_text": en81e, "transliteration": entr81e},
    tr={"meaning_text": tr81e},
)

# 86, 87 ---------------------------------------------------------------
put(86, "morning", ru={"meaning_text": sub(m(86, "ru"), "утром или вечером", "утром")})
put(86, "evening", ru={"meaning_text": sub(m(86, "ru"), "утром или вечером", "вечером")})
ru87 = sub(m(87, "ru"), "делать это утром и вечером.", "делать это.")
put(87, "morning", ru={"meaning_text": ru87})
put(87, "evening", ru={"meaning_text": ru87})

# 89 -------------------------------------------------------------------
ar89m = ar_before_note(89)
ar89e = ar_sub(ar89m, "أَصْبَحْنَا وَأَصْبَحَ", "أَمْسَيْنَا وَأَمْسَى")
ar89e = ar_sub(
    ar89e,
    "خَيْرَ هَذَا الْيَوْمِ:فَتْحَهُ، وَنَصْرَهُ، وَنورَهُ، وَبَرَكَتَهُ، وَهُدَاهُ",
    "خَيْرَ هَذِهِ اللَّيْلَةِ: فَتْحَهَا، وَنَصْرَهَا، وَنُورَهَا، وَبَرَكَتَهَا، وَهُدَاهَا",
)
ar89e = ar_sub(ar89e, "شَرِّ مَا فِيهِ وَشَرِّ مَا بَعْدَهُ", "شَرِّ مَا فِيهَا وَشَرِّ مَا بَعْدَهَا")
en89m, en89e = (
    part.strip()
    for part in m(89, "en").split("[For the evening, the supplication is read as follows:]")
)
entr89m, entr89e = (
    part.strip()
    for part in tr(89, "en").split("[For the evening, the supplication is read as follows: ]")
)
ru89m = (
    "Мы дожили до утра, и этим утром владычество принадлежит Аллаху, Господу миров. О Аллах, поистине, я прошу Тебя о благе этого дня: "
    "о помощи и победе, о свете, благословении и руководстве в этот день, и я прибегаю к Тебе от зла того, что случится этим днем, и зла того, что за ним последует."
)
ru89e = (
    "Мы дожили до вечера, и этим вечером владычество принадлежит Аллаху, Господу миров. О Аллах, поистине, я прошу Тебя о благе этой ночи: "
    "о помощи и победе, о свете, благословении и руководстве в эту ночь, и я прибегаю к Тебе от зла того, что случится этой ночью, и зла того, что за ней последует."
)
rutr89m = (
    "Асбахна ва асбаха-ль-мульку ли-Лляхи, Рабби-ль-'Алямина. Аллахумма, инни ас'алю-кя хайра хаза-ль-йауми: фатха-ху, ва насра-ху, ва нура-ху, "
    "ва баракята-ху ва худа-ху, ва а'узу би-кя мин шарри ма фи-хи ва шарри ма ба'да-ху."
)
rutr89e = (
    "Амсайна ва амса-ль-мульку ли-Лляхи, Рабби-ль-'Алямина. Аллахумма, инни ас'алю-кя хайра хазихи-ль-лейляти: фатха-ха, ва насра-ха, ва нура-ха, "
    "ва баракята-ха ва худа-ха, ва а'узу би-кя мин шарри ма фи-ха ва шарри ма ба'да-ха."
)
tr89e = (
    "Mülk, Âlemlerin Rabbi Allah’a devamlı âit bir halde akşamladık. Allahım! Senden bu gecenin iyiliğini, zaferini, (ilim ve amelde muvaffak olmak sûretiyle) nûrunu, "
    "(kolay helal rızık kazanmak sûretiyle) bereketini ve hidâyetini dilerim. Onda ve sonrasındaki şerden de sana sığınırım."
)
put(
    89,
    "morning",
    ar89m,
    ru={"meaning_text": ru89m, "transliteration": rutr89m},
    en={"meaning_text": en89m, "transliteration": entr89m},
)
put(
    89,
    "evening",
    ar89e,
    ru={"meaning_text": ru89e, "transliteration": rutr89e},
    en={"meaning_text": en89e, "transliteration": entr89e},
    tr={"meaning_text": tr89e},
)

# 90 -------------------------------------------------------------------
ar90m = ar_before_note(90)
ar90e = ar_sub(ar90m, "أَصْبَحْنا", "أَمْسَيْنَا")
en90m = sub(m(90, "en"), "(Note: for the evening, one reads amsayna instead of asbahna.)", "")
en90e = sub(en90m, "We rise upon", "We have reached the evening upon")
entr90m = sub(tr(90, "en"), "(Note: for the evening, one reads amsayna instead of asbahna.)", "")
entr90e = sub(entr90m, "Asbahna AAala", "Amsayna AAala")
ru90m = sub(m(90, "ru"), "до утра (вечера)", "до утра")
ru90e = sub(m(90, "ru"), "до утра (вечера)", "до вечера")
rutr90 = tr(90, "ru").rstrip('".') + "."
rutr90m = sub(rutr90, "Асбахна (амсайна)", "Асбахна")
rutr90e = sub(rutr90, "Асбахна (амсайна)", "Амсайна")
tr90e = sub(m(90, "tr"), "sabahladık", "akşamladık")
put(
    90,
    "morning",
    ar90m,
    ru={"meaning_text": ru90m, "transliteration": rutr90m},
    en={"meaning_text": en90m, "transliteration": entr90m},
)
put(
    90,
    "evening",
    ar90e,
    ru={"meaning_text": ru90e, "transliteration": rutr90e},
    en={"meaning_text": en90e, "transliteration": entr90e},
    tr={"meaning_text": tr90e},
)

# 91, 93, 96, 98 -------------------------------------------------------
ru91 = sub(m(91, "ru"), "по сто раз утром и вечером,", "по сто раз,")
put(91, "morning", ru={"meaning_text": ru91})
put(91, "evening", ru={"meaning_text": ru91})
put(
    93,
    "morning",
    ru={
        "meaning_text": sub(
            m(93, "ru"), "в течение всего этого дня до самого вечера,", "в течение всего этого дня,"
        )
    },
)
ru96 = sub(m(96, "ru"), " * Эти слова следует повторять по три раза каждое утро.", "")
put(96, "morning", ru={"meaning_text": ru96})
put(96, "evening", ru={"meaning_text": ru96})
ru98 = sub(m(98, "ru"), "по десять молитв утром и вечером,", "по десять молитв,")
put(98, "morning", ru={"meaning_text": ru98})
put(98, "evening", ru={"meaning_text": ru98})

out = {
    "schema_version": 1,
    "collection": src["collection"]["slug"],
    "version": src["version"],
    "entries": [
        {
            "source_number": n,
            **{time: {k: v for k, v in body.items() if v} for time, body in V[n].items()},
        }
        for n in sorted(V)
    ],
}
(data_dir / "hisn_al_muslim_time_variants_v1.json").write_text(
    json.dumps(out, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
)
print("entries", len(out["entries"]))  # noqa: T201

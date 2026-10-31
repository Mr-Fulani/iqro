# ruff: noqa: RUF001 -- Curated reciter names are intentionally Cyrillic.

"""Curated names of reciters imported from MP3Quran.

MP3Quran's Russian names follow no one spelling, some are Latin, and a few are
page keywords rather than names; its Turkish list mostly repeats English. These
follow the catalog's own spelling (`reciter_profiles.py`), checked against the
Arabic name. `import_mp3quran_catalog --apply-profiles` writes them.
"""

from __future__ import annotations

import json
from datetime import date
from pathlib import Path
from typing import Any

# reciter code: (Russian name, Turkish name)
MP3QURAN_RECITER_NAMES: dict[str, tuple[str, str]] = {
    "abdelbari-al-toubayti": ("Абдуль-Бари ас-Субейти", "Abdülbari es-Subeyti"),
    "abdul-aziz-al-ahmad": ("Абдуль-Азиз аль-Ахмад", "Abdülaziz el-Ahmed"),
    "abdulaziz-alturki": ("Абдуль-Азиз ат-Турки", "Abdülaziz et-Türki"),
    "abdulaziz-az-zahrani": ("Абдуль-Азиз аз-Захрани", "Abdülaziz ez-Zehrani"),
    "abdulbari-mohammad": ("Абдуль-Бари Мухаммад", "Abdülbari Muhammed"),
    "abdulhadi-kanakeri": ("Абдуль-Хади Канакири", "Abdülhadi Kenakiri"),
    "abdullah-al-johany": ("Абдуллах аль-Джухани", "Abdullah el-Cühani"),
    "abdullah-al-khalaf": ("Абдуллах аль-Халяф", "Abdullah el-Halef"),
    "abdullah-al-mattrod": ("Абдуллах аль-Матруд", "Abdullah el-Matrud"),
    "abdullah-al-mousa": ("Абдуллах аль-Муса", "Abdullah el-Musa"),
    "abdullah-albuajan": ("Абдуллах аль-Буайджан", "Abdullah el-Buaycan"),
    "abdullah-basfer": ("Абдуллах Басфар", "Abdullah Basfar"),
    "abdullah-khayyat": ("Абдуллах Хайят", "Abdullah Hayyat"),
    "abdulmohsen-al-qasim": ("Абдуль-Мухсин аль-Касим", "Abdülmuhsin el-Kasım"),
    "abdulmohsin-al-harthy": ("Абдуль-Мухсин аль-Хариси", "Abdülmuhsin el-Harisi"),
    "abdulmohsin-al-obaikan": ("Абдуль-Мухсин аль-Убайкан", "Abdülmuhsin el-Ubeykan"),
    "abdulrahman-al-majed": ("Абдуррахман аль-Маджид", "Abdurrahman el-Macid"),
    "abdulrasheed-soufi": ("Абдуррашид Суфи", "Abdürreşid Sufi"),
    "abdulwadood-haneef": ("Абдуль-Вадуд Ханиф", "Abdülvedud Hanif"),
    "abdulwali-al-arkani": ("Абдуль-Вали аль-Аркани", "Abdülveli el-Erkani"),
    "adel-ryyan": ("Адиль Райян", "Adil Reyyan"),
    "ahmad-al-hawashi": ("Ахмад аль-Хаваши", "Ahmed el-Havaşi"),
    "ahmad-al-nufais": ("Ахмад ан-Нуфайс", "Ahmed en-Nüfeys"),
    "ahmad-deban": ("Ахмад Дибан", "Ahmed Diban"),
    "ahmad-issa-al-maasaraawi": ("Ахмад Иса аль-Масарави", "Ahmed İsa el-Masaravi"),
    "ahmad-nauina": ("Ахмад Нуайна", "Ahmed Nuayna"),
    "ahmad-saber": ("Ахмад Сабир", "Ahmed Sabir"),
    "ahmad-shaheen": ("Ахмад Халиль Шахин", "Ahmed Halil Şahin"),
    "ahmed-al-trabulsi": ("Ахмад ат-Тарабулси", "Ahmed et-Trablusi"),
    "ahmed-amer": ("Ахмад Амир", "Ahmed Amir"),
    "akram-alalaqmi": ("Акрам аль-Алякми", "Ekrem el-Alakmi"),
    "ali-alhuthaifi": ("Али аль-Хузайфи", "Ali el-Huzeyfi"),
    "ali-hajjaj-alsouasi": ("Али Хаджаж ас-Сувайси", "Ali Haccac es-Süveysi"),
    "alzain-mohammad-ahmad": ("Аз-Зейн Мухаммад Ахмад", "Ez-Zeyn Muhammed Ahmed"),
    "anas-alemadi": ("Анас аль-Имади", "Enes el-İmadi"),
    "dawood-hamza": ("Дауд Хамза", "Davud Hamza"),
    "emad-hafez": ("Имад Зухайр Хафиз", "İmad Züheyr Hafız"),
    "fares-abbad": ("Фарис Аббад", "Faris Abbad"),
    "hasan-saleh": ("Хасан Салих", "Hasan Salih"),
    "hassan-aldaghriri": ("Хасан ад-Дагрири", "Hasan ed-Dağriri"),
    "ibrahim-al-akdar": ("Ибрахим аль-Ахдар", "İbrahim el-Ahdar"),
    "ibrahim-al-asiri": ("Ибрахим аль-Асири", "İbrahim el-Asiri"),
    "ibrahim-aldosari": ("Ибрахим ад-Дусари", "İbrahim ed-Devseri"),
    "issa-omar-sanankoua": ("Иса Умар Сананкуа", "İsa Ömer Sanankua"),
    "jamaan-alosaimi": ("Джамаан аль-Усайми", "Cuman el-Useymi"),
    "khaled-al-qahtani": ("Халид аль-Кахтани", "Halid el-Kahtani"),
    "khalid-abdulkafi": ("Халид Абдулькафи", "Halid Abdülkafi"),
    "khalid-al-jileel": ("Халид аль-Джалиль", "Halid el-Celil"),
    "khalid-almohana": ("Халид аль-Муханна", "Halid el-Mühenna"),
    "khalid-mohammadi": ("Халид Карим Мухаммади", "Halid Kerim Muhammedi"),
    "khalifa-altunaiji": ("Халифа ат-Тунайджи", "Halife et-Tuneyci"),
    "mahmoud-ali-albanna": ("Махмуд Али аль-Банна", "Mahmud Ali el-Benna"),
    "majed-al-zamil": ("Маджид аз-Замиль", "Macid ez-Zamil"),
    "mansour-al-salemi": ("Мансур ас-Салими", "Mansur es-Salimi"),
    "mohammad-abdullkarem": ("Мухаммад Абдулькарим", "Muhammed Abdülkerim"),
    "mohammad-al-tablaway": ("Мухаммад ат-Таблави", "Muhammed et-Tablavi"),
    "mohammad-albukheet": ("Мухаммад аль-Бухайт", "Muhammed el-Buheyt"),
    "mohammad-khalil-al-qari": ("Мухаммад Халиль аль-Кари", "Muhammed Halil el-Kari"),
    "mohammad-rashad-alshareef": ("Мухаммад Рашад аш-Шариф", "Muhammed Reşad eş-Şerif"),
    "mohammad-saleh-alim-shah": ("Мухаммад Салих Алим Шах", "Muhammed Salih Alim Şah"),
    "mohammed-ayyub": ("Мухаммад Аюб", "Muhammed Eyyub"),
    "muhammad-burhaji": ("Мухаммад Бурхаджи", "Muhammed Burhaci"),
    "mustafa-ismail": ("Мустафа Исмаил", "Mustafa İsmail"),
    "nabil-al-rifay": ("Набиль ар-Рифаи", "Nebil er-Rifai"),
    "nasser-alqatami": ("Насер аль-Катами", "Nasır el-Katami"),
    "neamah-al-hassan": ("Нима аль-Хассан", "Nime el-Hassan"),
    "peshawa-qadr-al-kurdi": ("Пешава Кадир аль-Курди", "Bişava Kadir el-Kürdi"),
    "raad-al-kurdi": ("Раад Мухаммад аль-Курди", "Raad Muhammed el-Kürdi"),
    "saber-abdulhakm": ("Сабир Абдуль-Хакам", "Sabir Abdülhakem"),
    "sahl-yassin": ("Сахль Ясин", "Sehl Yasin"),
    "salah-albudair": ("Салах аль-Будайр", "Salah el-Bedir"),
    "salah-alhashim": ("Салах аль-Хашим", "Salah el-Haşim"),
    "saleh-al-habdan": ("Салих аль-Хабдан", "Salih el-Habdan"),
    "saleh-alsahood": ("Салих ас-Сахуд", "Salih es-Sahud"),
    "saleh-alshamrani": ("Салих аш-Шамрани", "Salih eş-Şemrani"),
    "sayed-ahmad-hashemi": ("Сайид Ахмад Хашими", "Seyyid Ahmed Haşimi"),
    "shirazad-taher": ("Ширзад Тахир", "Şirzad Tahir"),
    "slaah-bukhatir": ("Салах Бу Хатыр", "Salah Buhatır"),
    "tawfeeq-as-sayegh": ("Тауфик ас-Саиг", "Tevfik es-Sayiğ"),
    "wadeea-al-yamani": ("Вади аль-Ямани", "Vedi el-Yemani"),
    "yousef-bin-noah-ahmad": ("Юсуф бин Нух Ахмад", "Yusuf bin Nuh Ahmed"),
    "zaki-daghistani": ("Заки Дагистани", "Zeki Dağıstani"),
}

# Where MP3Quran's English spelling is simply wrong.
MP3QURAN_RECITER_ENGLISH_NAMES: dict[str, str] = {
    "abdullah-basfer": "Abdullah Basfar",
    "ibrahim-al-akdar": "Ibrahim Al-Akhdar",
    "mahmoud-ali-albanna": "Mahmoud Ali Al-Banna",
    "mohammad-abdullkarem": "Mohammad Abdulkarim",
    "mohammad-al-tablaway": "Muhammad Al-Tablawi",
    "saber-abdulhakm": "Saber Abdulhakam",
    "slaah-bukhatir": "Salah Bukhatir",
}

# Short sourced biographies, checked against the page in `profile_source_url`.
PROFILES_CHECKED_ON = date(2026, 10, 31)
_BIOGRAPHIES_FILE = Path(__file__).with_name("mp3quran_reciter_biographies.json")


def _biographies() -> dict[str, dict[str, Any]]:
    profiles: dict[str, dict[str, Any]] = json.loads(_BIOGRAPHIES_FILE.read_text("utf-8"))
    return {
        code: {**profile, "profile_source_checked_on": PROFILES_CHECKED_ON}
        for code, profile in profiles.items()
    }


MP3QURAN_RECITER_BIOGRAPHIES: dict[str, dict[str, Any]] = _biographies()

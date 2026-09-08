"""Mechanically pin the existing mobile table/text as shared calendar v1 assets.

Run once with --hijri-package pointing at the already installed hijri 3.0.1.
Existing output must be byte-identical; this never overwrites a different asset.
"""
import argparse
import hashlib
import json
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "services/backend/src/quran_backend/modules/calendar/data"
RULES = [
    ("ramadan", "ramadan", 9, 1, 30, "occasion", "Quran 2:185", "https://quran.com/2/185"),
    ("eid_fitr", "eidFitr", 10, 1, 1, "no_fast", "Sahih al-Bukhari 1990", "https://sunnah.com/bukhari:1990"),
    ("arafah", "arafah", 12, 9, 9, "voluntary_fast", "Sahih Muslim 1162b", "https://sunnah.com/muslim:1162b"),
    ("eid_adha", "eidAdha", 12, 10, 10, "no_fast", "Sahih al-Bukhari 1990", "https://sunnah.com/bukhari:1990"),
    ("tashriq", "tashriq", 12, 11, 13, "no_fast", "Sahih Muslim 1141a", "https://sunnah.com/muslim:1141a"),
    ("ashura", "ashura", 1, 10, 10, "voluntary_fast", "Sahih Muslim 1162b", "https://sunnah.com/muslim:1162b"),
    ("white_days", "whiteDays", 0, 13, 15, "voluntary_fast", "Sunan Abi Dawud 2449", "https://sunnah.com/abudawud:2449"),
    ("last_ten_nights", "lastTenNights", 9, 21, 30, "occasion", "Sahih al-Bukhari 2017", "https://sunnah.com/bukhari:2017"),
]
DESCRIPTIONS = {
    "ramadan": ["Месяц поста и ниспослания Корана. Начало уточняйте в своей общине.", "The month of fasting and revelation of the Quran. Confirm its start locally.", "شهر الصيام ونزول القرآن. تحقّق من بدايته لدى الجهات المحلية المعتمدة.", "Oruç ve Kur'an'ın indirildiği ay. Başlangıcını yerel yetkililerden doğrulayın."],
    "eid_fitr": ["Первый день Шавваля. В день праздника не постятся.", "The first day of Shawwal. Fasting on Eid is prohibited.", "أول شوال. يحرم صيام يوم العيد.", "Şevval'in ilk günü. Bayram günü oruç tutulmaz."],
    "eid_adha": ["Десятый день Зуль-хиджа. В день праздника не постятся.", "The tenth day of Dhul-Hijjah. Fasting on Eid is prohibited.", "العاشر من ذي الحجة. يحرم صيام يوم العيد.", "Zilhicce'nin onuncu günü. Bayram günü oruç tutulmaz."],
    "tashriq": ["11–13 Зуль-хиджа: дни еды, питья и поминания Аллаха. Не отмечаются как дни добровольного поста.", "11–13 Dhul-Hijjah: days of eating, drinking and remembering Allah, not voluntary fasting reminders.", "١١–١٣ من ذي الحجة: أيام أكل وشرب وذكر لله، ولا تُعرض كتذكير بصيام التطوع.", "11–13 Zilhicce: yeme, içme ve Allah'ı anma günleri; nafile oruç hatırlatması gösterilmez."],
    "arafah": ["9 Зуль-хиджа. Источник о достоинстве поста; для совершающих хадж действуют отдельные положения.", "9 Dhul-Hijjah. A reference on the merit of fasting; pilgrims have separate guidance.", "٩ ذو الحجة. مصدر في فضل الصيام، وللحجاج أحكام خاصة.", "9 Zilhicce. Orucun faziletine dair kaynak; hacılar için ayrı hükümler geçerlidir."],
    "ashura": ["10 Мухаррама. Источник о достоинстве поста в день Ашура.", "10 Muharram. A reference on the merit of fasting on Ashura.", "١٠ محرم. مصدر في فضل صيام عاشوراء.", "10 Muharrem. Aşure günü orucunun faziletine dair kaynak."],
    "white_days": ["13–15 числа лунного месяца. В Рамадан и дни без добровольного поста эта отметка не показывается.", "The 13th–15th of the lunar month. Hidden in Ramadan and on days excluded from voluntary fasting.", "الأيام ١٣–١٥ من الشهر القمري. لا تظهر العلامة في رمضان وأيام منع صيام التطوع.", "Kameri ayın 13–15. günleri. Ramazan'da ve nafile oruç tutulmayan günlerde gösterilmez."],
    "last_ten_nights": ["Период последних десяти ночей Рамадана. Ночь предопределения не привязана здесь к одной гарантированной дате.", "The last ten nights of Ramadan. Laylat al-Qadr is not assigned one guaranteed date here.", "العشر الأواخر من رمضان. لا تُحدّد ليلة القدر هنا بتاريخ واحد مؤكد.", "Ramazan'ın son on gecesi. Kadir Gecesi burada kesin bir tek tarihe bağlanmaz."],
}


def raw_json(value):
    return (json.dumps(value, ensure_ascii=False, indent=2) + "\n").encode()


def write_once(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    if path.exists():
        if path.read_bytes() != data:
            raise ValueError(f"Existing generated asset differs: {path}")
    else:
        with path.open("xb") as stream:
            stream.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hijri-package", type=Path, required=True)
    args = parser.parse_args()
    source = args.hijri_package / "lib/hijri_array.dart"
    values = list(map(int, re.search(r"ummAlquraDateArray = \[([^]]+)\]", source.read_text()).group(1).replace("\n", "").split(",")))
    assert len(values) == 1741
    table = {"method": "ummalqura-hijri-3.0.1", "source": "https://pub.dev/packages/hijri/versions/3.0.1", "source_sha256": hashlib.sha256(source.read_bytes()).hexdigest(), "month_starts_mcjdn": values}
    write_once(DATA / "ummalqura-v1.json", raw_json(table))
    write_once(DATA / "HIJRI-LICENSE.txt", (args.hijri_package / "LICENSE").read_bytes())
    locales = ("ru", "en", "ar", "tr")
    translations = {locale: json.loads((ROOT / f"clients/iqro_mobile/lib/l10n/app_{locale}.arb").read_text()) for locale in locales}
    events = []
    for code, old, month, first, last, kind, label, url in RULES:
        events.append({"code": code, "month": month, "day_start": first, "day_end": last,
            "kind": kind, "exclude_ramadan": code == "white_days",
            "titles": {locale: re.search(r"\b" + old + r"\{([^}]+)\}", translations[locale]["hijriEventName"]).group(1) for locale in locales},
            "descriptions": dict(zip(locales, DESCRIPTIONS[code], strict=True)),
            "source": {"label": label, "url": url}})
    seed = {"schema_version": 1, "method": table["method"], "min_year": 1356, "max_year": 1500,
        "civil_start": "1937-03-14", "civil_end": "2077-11-16", "events": events}
    seed["version"] = hashlib.sha256(json.dumps(seed, sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode()).hexdigest()
    write_once(DATA / "events-v1.json", raw_json(seed))
    write_once(ROOT / "clients/iqro_mobile/assets/calendar/events-v1.json", raw_json(seed))
    print(f"Generated {len(values)} month boundaries and {len(events)} shared events; existing files preserved.")


if __name__ == "__main__":
    main()

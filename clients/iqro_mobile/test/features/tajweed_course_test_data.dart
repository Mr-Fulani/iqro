// Data of the tajweed course tests, trimmed from the real fixtures:
// docs/tajweed/course-document.example.json (three lessons of two sections;
// «iqlab» is listed but absent, so the section drops it) and
// services/web/e2e/fixtures/tajweed-course-examples.json (API order).
import 'dart:convert';

Map<String, Object?> tajweedCourseDocumentJson() =>
    jsonDecode(_document) as Map<String, Object?>;

/// The examples of [lesson] in API order: a page is `offset..offset+limit`.
List<Object?> tajweedCourseExamplesJson(String lesson) =>
    (jsonDecode(_examples) as Map<String, Object?>)[lesson]! as List<Object?>;

/// A page of the examples API, as the backend slices it.
Map<String, Object?> tajweedCourseExamplesPage(
  String lesson, {
  required int offset,
  required int limit,
}) {
  final all = tajweedCourseExamplesJson(lesson);
  final end = offset + limit < all.length ? offset + limit : all.length;
  return <String, Object?>{
    'lesson': lesson,
    'offset': offset,
    'next_offset': offset + limit < all.length ? offset + limit : null,
    'examples': offset < all.length ? all.sublist(offset, end) : const [],
  };
}

const _document = r'''
{
 "schema_version": 1,
 "course": {
  "slug": "tajweed",
  "version": "2026-10-22",
  "reviewed_at": "2026-10-22T09:00:00+00:00",
  "published_at": "2026-10-22T10:00:00+00:00",
  "checksum_sha256": "0000000000000000000000000000000000000000000000000000000000000000",
  "language": "ru",
  "title": "Таджвид",
  "summary": "Правила чтения Корана по риваяту Хафса шаг за шагом: объяснение, примеры из аятов с прослушиванием и упражнение в каждом уроке.",
  "review_status": "pending_teacher_review"
 },
 "targets": {
  "izhar": {
   "name": "Изхар",
   "arabic_name": "الإظهار الحلقي",
   "color": "#7B5EA7",
   "rule": null
  },
  "idgham_ghunnah": {
   "name": "Идгам с гунной",
   "arabic_name": "الإدغام بغنة",
   "color": "#09B000",
   "rule": "idgham_ghunnah"
  },
  "ikhafa_shafawi": {
   "name": "Ихфа шафави",
   "arabic_name": "الإخفاء الشفوي",
   "color": "#09B000",
   "rule": "ikhafa_shafawi"
  }
 },
 "sections": [
  {
   "slug": "noon-sakinah",
   "title": "Нун с сукуном и танвин",
   "lessons": [
    "izhar",
    "idgham-ghunnah",
    "iqlab"
   ]
  },
  {
   "slug": "meem-sakinah",
   "title": "Мим с сукуном",
   "lessons": [
    "ikhfa-shafawi"
   ]
  }
 ],
 "lessons": [
  {
   "slug": "izhar",
   "section": "noon-sakinah",
   "target": "izhar",
   "minutes": 4,
   "title": "Изхар — нун звучит ясно",
   "summary": "Перед шестью гортанными буквами нун с сукуном и танвин звучат чётко, без задержки в носу.",
   "explanation": "Изхар (الإظهار) значит «ясность». Правило действует, когда после нуна с сукуном (نْ) или танвина стоит одна из шести гортанных букв: ء ه ع ح غ خ. Встреча бывает внутри слова (يَنْهَوْنَ) или на стыке слов (مَنْ ءَامَنَ, عَلِيمٌ حَكِيمٌ).\n\nЭти буквы рождаются в горле, далеко от места нуна, поэтому нун не сливается с ними и не прячется. Слышен обычный чёткий звук «н», без затянутого носового звука (гунны).\n\nПодсказка: в мусхафе над таким нуном стоит знак сукуна.",
   "how": "Произнесите нун полностью: кончик языка касается десны над верхними передними зубами, звук короткий, не тяните его через нос. Сразу переходите к гортанной букве, без паузы и без лишнего гласного между ними.",
   "letters": "ء ه ع ح غ خ"
  },
  {
   "slug": "idgham-ghunnah",
   "section": "noon-sakinah",
   "target": "idgham_ghunnah",
   "minutes": 4,
   "title": "Идгам с гунной — слияние с носовым звуком",
   "summary": "Нун с сукуном или танвин в конце слова сливается с буквами ي ن م و, оставляя носовой звук.",
   "explanation": "Идгам (الإدغام) значит «вставить одно в другое». Если слово кончается нуном с сукуном или танвином, а следующее начинается с одной из букв ي ن م و (их запоминают словом يَنْمُو), нун сливается с этой буквой. Она звучит удвоенной, а носовой звук (гунна) сохраняется: مَن يَقُولُ, خَيْرًا يَرَهُۥ, مِن مَّالٍ.\n\nПравило действует только на стыке двух слов. Внутри одного слова нун перед و или ي читается ясно: دُنْيَا, صِنْوَانٌ.\n\nС ن и م слияние полное. С و и ي оно неполное: часть носового звука нуна остаётся.",
   "how": "Не произносите нун отдельно: сразу переходите к следующей букве, удваивая её, и держите носовой звук 2 хараката. Харака — время одного короткого гласного; две хараката — примерно как неспешно загнуть два пальца.",
   "letters": "ي ن م و"
  },
  {
   "slug": "ikhfa-shafawi",
   "section": "meem-sakinah",
   "target": "ikhafa_shafawi",
   "minutes": 3,
   "title": "Ихфа шафави — мим перед ب",
   "summary": "Мим с сукуном перед ب звучит скрыто: губы смыкаются мягко, гунна — 2 хараката.",
   "explanation": "Шафави (شفوي) значит «губной»: и мим, и ب произносятся губами. Если слово кончается мимом с сукуном, а следующее начинается с ب, мим читается скрыто, с носовым звуком (гунной): تَرْمِيهِم بِحِجَارَةٍ, وَمَا هُم بِمُؤْمِنِينَ.\n\nВ мусхафе над таким мимом нет знака сукуна — подсказка, что мим не читается ясно.\n\nЗвучит так же, как икляб: там нун сначала превращается в мим, а затем читается по этому правилу.",
   "how": "Сомкните губы мягко, без нажима, и тяните носовой звук 2 хараката. Затем раскройте губы на ب. Не сжимайте губы с силой и не произносите мим отдельно от ب.",
   "letters": "ب"
  }
 ]
}
''';

const _examples = r'''
{
 "izhar": [
  {
   "verse_key": "89:2",
   "surah_number": 89,
   "ayah_number": 2,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "وَلَيَالٍ"
    },
    {
     "position": 2,
     "text": "عَشْرٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 7,
       "end": 9
      },
      {
       "position": 2,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "101:11",
   "surah_number": 101,
   "ayah_number": 11,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "نَارٌ"
    },
    {
     "position": 2,
     "text": "حَامِيَةُۢ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 3,
       "end": 5
      },
      {
       "position": 2,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "88:4",
   "surah_number": 88,
   "ayah_number": 4,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "تَصْلَىٰ"
    },
    {
     "position": 2,
     "text": "نَارًا"
    },
    {
     "position": 3,
     "text": "حَامِيَةً"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 3,
       "end": 5
      },
      {
       "position": 3,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "80:18",
   "surah_number": 80,
   "ayah_number": 18,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "مِنْ"
    },
    {
     "position": 2,
     "text": "أَىِّ"
    },
    {
     "position": 3,
     "text": "شَىْءٍ"
    },
    {
     "position": 4,
     "text": "خَلَقَهُۥ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 2,
       "end": 4
      },
      {
       "position": 2,
       "start": 0,
       "end": 2
      }
     ]
    },
    {
     "parts": [
      {
       "position": 3,
       "start": 4,
       "end": 6
      },
      {
       "position": 4,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "88:5",
   "surah_number": 88,
   "ayah_number": 5,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "تُسْقَىٰ"
    },
    {
     "position": 2,
     "text": "مِنْ"
    },
    {
     "position": 3,
     "text": "عَيْنٍ"
    },
    {
     "position": 4,
     "text": "ءَانِيَةٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 2,
       "end": 4
      },
      {
       "position": 3,
       "start": 0,
       "end": 2
      }
     ]
    },
    {
     "parts": [
      {
       "position": 3,
       "start": 4,
       "end": 6
      },
      {
       "position": 4,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "88:10",
   "surah_number": 88,
   "ayah_number": 10,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فِى"
    },
    {
     "position": 2,
     "text": "جَنَّةٍ"
    },
    {
     "position": 3,
     "text": "عَالِيَةٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 5,
       "end": 7
      },
      {
       "position": 3,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  },
  {
   "verse_key": "96:10",
   "surah_number": 96,
   "ayah_number": 10,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "عَبْدًا"
    },
    {
     "position": 2,
     "text": "إِذَا"
    },
    {
     "position": 3,
     "text": "صَلَّىٰٓ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 4,
       "end": 6
      },
      {
       "position": 2,
       "start": 0,
       "end": 2
      }
     ]
    }
   ]
  }
 ],
 "idgham-ghunnah": [
  {
   "verse_key": "80:28",
   "surah_number": 80,
   "ayah_number": 28,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "وَعِنَبًا"
    },
    {
     "position": 2,
     "text": "وَقَضْبًا"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 6,
       "end": 9
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "88:3",
   "surah_number": 88,
   "ayah_number": 3,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "عَامِلَةٌ"
    },
    {
     "position": 2,
     "text": "نَّاصِبَةٌ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 7,
       "end": 9
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "80:29",
   "surah_number": 80,
   "ayah_number": 29,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "وَزَيْتُونًا"
    },
    {
     "position": 2,
     "text": "وَنَخْلاً"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 9,
       "end": 12
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "80:13",
   "surah_number": 80,
   "ayah_number": 13,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فِى"
    },
    {
     "position": 2,
     "text": "صُحُفٍ"
    },
    {
     "position": 3,
     "text": "مُّكَرَّمَةٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 4,
       "end": 6
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "104:9",
   "surah_number": 104,
   "ayah_number": 9,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فِى"
    },
    {
     "position": 2,
     "text": "عَمَدٍ"
    },
    {
     "position": 3,
     "text": "مُّمَدَّدَةِۭ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 4,
       "end": 6
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "88:14",
   "surah_number": 88,
   "ayah_number": 14,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "وَأَكْوَابٌ"
    },
    {
     "position": 2,
     "text": "مَّوْضُوعَةٌ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 9,
       "end": 11
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "87:10",
   "surah_number": 87,
   "ayah_number": 10,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "سَيَذَّكَّرُ"
    },
    {
     "position": 2,
     "text": "مَن"
    },
    {
     "position": 3,
     "text": "يَخْشَىٰ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 1,
       "end": 3
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  }
 ],
 "ikhfa-shafawi": [
  {
   "verse_key": "88:22",
   "surah_number": 88,
   "ayah_number": 22,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "لَّسْتَ"
    },
    {
     "position": 2,
     "text": "عَلَيْهِم"
    },
    {
     "position": 3,
     "text": "بِمُصَيْطِرٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 7,
       "end": 9
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "84:24",
   "surah_number": 84,
   "ayah_number": 24,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فَبَشِّرْهُم"
    },
    {
     "position": 2,
     "text": "بِعَذَابٍ"
    },
    {
     "position": 3,
     "text": "أَلِيمٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 10,
       "end": 12
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "79:14",
   "surah_number": 79,
   "ayah_number": 14,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فَإِذَا"
    },
    {
     "position": 2,
     "text": "هُم"
    },
    {
     "position": 3,
     "text": "بِٱلسَّاهِرَةِ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 1,
       "end": 3
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "81:22",
   "surah_number": 81,
   "ayah_number": 22,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "وَمَا"
    },
    {
     "position": 2,
     "text": "صَاحِبُكُم"
    },
    {
     "position": 3,
     "text": "بِمَجْنُونٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 8,
       "end": 10
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "96:14",
   "surah_number": 96,
   "ayah_number": 14,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "أَلَمْ"
    },
    {
     "position": 2,
     "text": "يَعْلَم"
    },
    {
     "position": 3,
     "text": "بِأَنَّ"
    },
    {
     "position": 4,
     "text": "ٱللَّهَ"
    },
    {
     "position": 5,
     "text": "يَرَىٰ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 2,
       "start": 5,
       "end": 7
      },
      {
       "position": 3,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "105:4",
   "surah_number": 105,
   "ayah_number": 4,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "تَرْمِيهِم"
    },
    {
     "position": 2,
     "text": "بِحِجَارَةٍ"
    },
    {
     "position": 3,
     "text": "مِّن"
    },
    {
     "position": 4,
     "text": "سِجِّيلٍ"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 1,
       "start": 8,
       "end": 10
      },
      {
       "position": 2,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  },
  {
   "verse_key": "91:14",
   "surah_number": 91,
   "ayah_number": 14,
   "page_number": 604,
   "words": [
    {
     "position": 1,
     "text": "فَكَذَّبُوهُ"
    },
    {
     "position": 2,
     "text": "فَعَقَرُوهَا"
    },
    {
     "position": 3,
     "text": "فَدَمْدَمَ"
    },
    {
     "position": 4,
     "text": "عَلَيْهِمْ"
    },
    {
     "position": 5,
     "text": "رَبُّهُم"
    },
    {
     "position": 6,
     "text": "بِذَنۢبِهِمْ"
    },
    {
     "position": 7,
     "text": "فَسَوَّىٰهَا"
    }
   ],
   "occurrences": [
    {
     "parts": [
      {
       "position": 5,
       "start": 6,
       "end": 8
      },
      {
       "position": 6,
       "start": 0,
       "end": 1
      }
     ]
    }
   ]
  }
 ]
}
''';

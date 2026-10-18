# Иллюстрации курса «Обучение намазу» — промпты генерации

Курс `hanbali-umdah`, снимок `hanbali-umdah-v1.json`. 19 картинок: 10 положений тела и 9 шагов вуду. Каждый ключ ниже совпадает с `media[].key` снимка, файл кладётся в `media/<key>.webp`.

Иллюстрации загружает владелец в админке: «Версии курса» → версия-черновик → «Открыть иллюстрации». Подходит PNG, JPEG или WebP до 20 МБ. Сервер обрежет картинку по центру до квадрата, сожмёт в WebP 720×720 (цель — до 60 КБ) и сразу пересоберёт документы курса. Файлы в `media/` не обязательны: импорт пропускает отсутствующие, а лежащие в git загружает как раньше.

Опыт генерации через `google/nano-banana`: модель держит стиль и человека, но в полный рост не рисует хват «правая кисть обхватывает левое запястье ниже пупка». Для qiyam руки надо дорабатывать вручную или в более сильной модели.

## Требования к файлу

- 720×720 px, WebP, не больше 60 КБ.
- Одна и та же модель и одинаковые настройки для всех 19 картинок.
- Если модель поддерживает референс, сначала генерируется `position-qiyam`. Принятый вариант затем подаётся референсом для остальных картинок, чтобы человек, одежда и свет совпадали.

## Общий стиль (добавляется к каждому промпту)

```
Calm, respectful flat vector illustration for a beginner's prayer guide.
One adult Muslim man, average build, short neat dark beard suggested only by silhouette,
NO facial features at all (smooth face, no eyes, no mouth, no nose detail).
Same clothing in every image: plain loose ankle-length off-white thobe with long sleeves,
small plain white kufi cap, barefoot. No logos, no patterns, no jewellery, no watch.
Plain warm light-grey background (#ECEAE6), no room, no furniture, no text, no symbols,
no mosque, no prayer rug pattern — at most a thin flat neutral floor line.
Soft even lighting, very subtle shadow under the figure. Muted palette: off-white, warm grey,
soft sage-green accents only on water where present.
Camera: full figure, 3/4 side view from the man's left-front, eye level, figure centred,
the same distance and framing in every image. Square 1:1 composition, generous margins.
Anatomically correct hands and feet, five fingers, clear readable pose.
```

Негативный промпт (если модель его принимает):

```
face details, eyes, mouth, realistic photo, 3d render, text, letters, watermark, logo,
extra fingers, extra limbs, distorted hands, multiple people, woman, child, busy background,
patterned carpet, mosque interior, dramatic lighting, gamified UI, cartoon exaggeration
```

## Положения тела

### position-takbir
```
Standing upright, both hands raised with open palms
facing forward, fingers together, hands level with the shoulders, thumbs near the earlobes;
feet slightly apart, gaze lowered. Opening takbir of the prayer.
```

### position-qiyam
```
Standing upright and still, right palm resting over the left wrist, both hands placed just
below the navel, gaze lowered towards the floor in front, feet slightly apart.
Standing in prayer (qiyam).
```

### position-ruku
```
Bowing: back straight and horizontal, head in line with the back (not raised, not dropped),
palms resting on the knees with fingers spread, arms straight and slightly away from the sides,
legs straight. Bowing in prayer (ruku').
```

### position-itidal
```
Standing upright again after bowing, body straight and still, arms relaxed down by the sides,
gaze lowered. Standing after bowing (i'tidal).
```

### position-qunut
```
Standing upright, both forearms raised in front of the chest, palms open and facing upwards
towards the sky as in supplication, elbows close to the body, gaze lowered.
Supplication of qunut while standing.
```

### position-sujud
```
Prostration seen from the side: forehead and nose touching the floor, palms flat on the floor
level with the shoulders, fingers together pointing forward, elbows raised and away from the
sides, belly not touching the thighs, knees on the floor, toes of both feet bent and pressed
into the floor. Prostration in prayer (sujud).
```

### position-jalsa
```
Sitting between two prostrations: sitting on the left foot laid flat under the body, right foot
upright with toes bent towards the front, back straight, both palms resting flat on the thighs
near the knees, gaze lowered. Sitting posture called iftirash.
```

### position-tashahhud
```
Same sitting as iftirash (on the left foot, right foot upright), left palm flat on the left thigh;
right hand on the right thigh with little and ring fingers folded, thumb and middle finger forming
a ring, index finger extended and pointing slightly forward. Sitting for the tashahhud.
```

### position-tawarruk
```
Sitting directly on the floor on the left hip/buttocks, left foot laid flat and brought out to the
right side from under the right shin, right foot upright with toes bent towards the front, hands on
the thighs as in tashahhud with the right index finger extended. Final sitting called tawarruk.
```

### position-taslim
```
Sitting as in tashahhud (iftirash), hands resting on the thighs, head turned to the right over the
right shoulder, body facing forward. Closing salutation (taslim).
```

## Вуду

Для шагов вуду меняется только окружение: тот же фон, а в кадре один простой настенный кран над светлой раковиной слева от человека. Одежда та же; рукава закатаны до локтей там, где руки омывают. Кадр — по пояс, а для стоп — во весь рост сидя.

### wudu-start
```
Waist-up, the man standing calmly in front of a simple wall tap over a plain light basin, hands
relaxed in front of him, sleeves rolled up to the elbows, gaze lowered — preparing for ablution.
```

### wudu-hands
```
Waist-up, washing both hands together under a gentle stream of water from the tap, rubbing the
palms and backs of the hands, sleeves rolled to the elbows.
```

### wudu-mouth-nose
```
Waist-up, raising a little water cupped in the right palm towards the mouth and nose, left hand
resting at the side; calm posture, no facial detail.
```

### wudu-face
```
Waist-up, washing the face with water held in both palms, hands covering the face from the
hairline to the chin, small drops of water, no facial features visible.
```

### wudu-arms
```
Waist-up, washing the right forearm up to and including the elbow, the left hand passing water
from the fingertips towards the elbow, sleeves rolled above the elbows.
```

### wudu-head
```
Waist-up, kufi removed and held aside or not shown, wet palms passing over the head from the
forehead towards the nape, fingers together, elbows raised. Wiping the head.
```

### wudu-ears
```
Waist-up, close framing on head and hands, index fingers inside the ears and thumbs behind the
ears, wiping the ears; no facial features.
```

### wudu-feet
```
Full figure, sitting on a low plain stool beside the basin, right foot raised over a small basin on
the floor, washing the right foot up to and including the ankle bones, left hand's little finger
between the toes; thobe hem lifted just above the ankles.
```

### wudu-finish
```
Waist-up, the man standing calmly after ablution, sleeves rolled down again, kufi on, gaze
slightly raised upwards, hands relaxed in front of him, a few drops of water on the hands.
```

## Аудио коротких формул

Записи лежат в `media/` рядом с иллюстрациями и подключаются через `audio_media` встроенной формулы.

- `audio-takbir.mp3` — «Аллаху акбар», такбират аль-ихрам, 1,6 с: archive.org, `takbiratul-ihram_202510`.
- `audio-taawwudh.mp3` — та'аввуз, 5,3 с: EveryAyah, `Husary_128kbps/audhubillah.mp3`.
- Для «амин» и таслима отдельной чистой записи пока нет.

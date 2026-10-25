import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/app/providers.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/theme/iqro_theme.dart';
import 'package:iqro_mobile/features/courses/course_models.dart';
import 'package:iqro_mobile/features/courses/lesson_media_cache.dart';
import 'package:iqro_mobile/features/courses/lesson_media_view.dart';
import 'package:iqro_mobile/l10n/generated/app_localizations.dart';

import 'course_test_data.dart';
import 'lesson_media_test_data.dart';

const _slides = ValueKey('lesson-media-slides');
const _previous = ValueKey('lesson-media-slide-previous');
const _next = ValueKey('lesson-media-slide-next');
const _counter = ValueKey('lesson-media-slide-counter');
const _video = ValueKey('test-video');
const _media = 'https://media.iqro.forum/courses';

List<LessonMedia> _exampleMedia(String lesson) =>
    CourseDocument.fromJson(courseDocumentJson()).lesson(lesson)!.media;

Map<String, Object?> _image(String name, int width, int height) => {
  'url': '$_media/slides/$name.webp',
  'small_url': '$_media/slides/$name-800.webp',
  'width': width,
  'height': height,
};

Map<String, Object?> _slide(
  String name, {
  int width = 1600,
  int height = 900,
  String caption = '',
  String alt = '',
  String dir = 'ltr',
}) => {
  'image': _image(name, width, height),
  'caption': caption,
  'alt': alt,
  'dir': dir,
};

List<LessonMedia> _parse(List<Map<String, Object?>> blocks) =>
    parseLessonMedia(blocks);

Future<List<String>> _pump(
  WidgetTester tester,
  List<LessonMedia> media, {
  String locale = 'ru',
  double pixelRatio = 1,
  double width = 400,
  ImageProvider Function(String url)? images,
}) async {
  tester.view.devicePixelRatio = pixelRatio;
  tester.view.physicalSize = Size(width, 900) * pixelRatio;
  addTearDown(tester.view.reset);
  final requested = <String>[];
  await tester.pumpWidget(
    ProviderScope(
      overrides: <Override>[
        appConfigProvider.overrideWithValue(
          const AppConfig(
            apiBaseUrl: 'https://iqro.forum',
            fallbackDownloadUrl: 'https://iqro.forum',
            environment: 'production',
          ),
        ),
        ...lessonMediaOverrides(requested: requested, images: images),
      ],
      child: MaterialApp(
        locale: Locale(locale),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        theme: IqroTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: LessonMediaView(
                media: media,
                videoBuilder: (context, video) =>
                    const SizedBox(key: _video, height: 100),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return requested;
}

String _counterText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_counter)).data!;

void main() {
  testWidgets('a video, then slides that turn with arrows, dots and swipes', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final requested = await _pump(tester, _exampleMedia('namerenie'));
    // In the author's order.
    expect(
      tester.getRect(find.byKey(_video)).bottom,
      lessThan(tester.getRect(find.byKey(_slides)).top),
    );
    expect(_counterText(tester), '1 / 2');
    expect(
      find.text('[Когда делать намерение — схема после проверки]'),
      findsOneWidget,
    );
    // The current slide and the next one are loaded, the small copy for a
    // frame of 368 pixels.
    expect(requested.toSet(), {
      '$_media/slides/1111111111aaaaaaaaaa-800.webp',
      '$_media/slides/3333333333cccccccccc-800.webp',
    });

    // The frame is as tall as the tallest slide, 4:3.
    final frame = tester.getSize(
      find.byKey(const ValueKey('lesson-media-slide-pages')),
    );
    expect(frame.width, 368);
    expect(frame.height, closeTo(276, .01));

    // Arrows are 48 wide at least; there is nothing before the first.
    expect(
      tester.getSize(find.byKey(_previous)).width,
      greaterThanOrEqualTo(48),
    );
    expect(tester.getSize(find.byKey(_next)).height, greaterThanOrEqualTo(48));
    expect(
      tester
          .widget<IconButton>(
            find.descendant(
              of: find.byKey(_previous),
              matching: find.byType(IconButton),
            ),
          )
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('Следующий слайд'), findsOneWidget);
    expect(find.byTooltip('Предыдущий слайд'), findsOneWidget);

    // The slide speaks its number and its description.
    expect(
      tester.getSemantics(find.byKey(const ValueKey('lesson-media-slide-0'))),
      matchesSemantics(
        label: 'Слайд 1 из 2\nСхема: ночь, рассвет и время намерения',
        isImage: true,
      ),
    );
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('lesson-media-slide-dot-1')),
      ),
      matchesSemantics(
        label: 'Слайд 2 из 2',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
      ),
    );

    await tester.tap(find.byKey(_next));
    await tester.pumpAndSettle();
    expect(_counterText(tester), '2 / 2');
    // The Arabic caption reads right to left in a Russian lesson.
    final caption = find.text('نويت صوم غد');
    expect(Directionality.of(tester.element(caption)), TextDirection.rtl);
    expect(
      tester.getSemantics(
        find.byKey(const ValueKey('lesson-media-slide-dot-1')),
      ),
      matchesSemantics(
        label: 'Слайд 2 из 2',
        isButton: true,
        hasTapAction: true,
        hasSelectedState: true,
        isSelected: true,
      ),
    );

    // A swipe goes back; a dot goes to its slide.
    await tester.fling(
      find.byKey(const ValueKey('lesson-media-slide-pages')),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(_counterText(tester), '1 / 2');
    await tester.tap(find.byKey(const ValueKey('lesson-media-slide-dot-1')));
    await tester.pumpAndSettle();
    expect(_counterText(tester), '2 / 2');
    semantics.dispose();
  });

  testWidgets('the frame stops at 5:4 and takes the large copy when the '
      'small one would be scaled up', (tester) async {
    final requested = await _pump(
      tester,
      _parse([
        {
          'type': 'slides',
          'slides': [_slide('tall', width: 600, height: 1600), _slide('wide')],
        },
      ]),
      pixelRatio: 3,
    );
    final frame = tester.getSize(
      find.byKey(const ValueKey('lesson-media-slide-pages')),
    );
    expect(frame.height, closeTo(frame.width * 1.25, .01));
    // 368 × 3 = 1104 device pixels.
    expect(requested.toSet(), {
      '$_media/slides/tall.webp',
      '$_media/slides/wide.webp',
    });
  });

  testWidgets('in Arabic the slides and the arrows are mirrored', (
    tester,
  ) async {
    await _pump(tester, _exampleMedia('namerenie'), locale: 'ar');
    // «Previous» is on the right, «next» on the left.
    expect(
      tester.getCenter(find.byKey(_previous)).dx,
      greaterThan(tester.getCenter(find.byKey(_next)).dx),
    );
    expect(
      tester
          .getCenter(find.byKey(const ValueKey('lesson-media-slide-dot-0')))
          .dx,
      greaterThan(
        tester
            .getCenter(find.byKey(const ValueKey('lesson-media-slide-dot-1')))
            .dx,
      ),
    );
    expect(find.byTooltip('الشريحة التالية'), findsOneWidget);
    // The next slide comes from the left: the finger moves to the right.
    await tester.fling(
      find.byKey(const ValueKey('lesson-media-slide-pages')),
      const Offset(300, 0),
      1000,
    );
    await tester.pumpAndSettle();
    expect(_counterText(tester), '2 / 2');
    // A Russian caption stays left to right.
    await tester.tap(find.byKey(_previous));
    await tester.pumpAndSettle();
    final caption = find.text(
      '[Когда делать намерение — схема после проверки]',
    );
    expect(Directionality.of(tester.element(caption)), TextDirection.ltr);
  });

  testWidgets('a banner is 16:9 with its caption under it', (tester) async {
    final semantics = tester.ensureSemantics();
    final requested = await _pump(
      tester,
      _exampleMedia('smysl-posta'),
      images: (_) => FailingImage(),
    );
    final banner = find.byKey(const ValueKey('lesson-media-banner'));
    final picture = find.descendant(
      of: banner,
      matching: find.byType(LessonMediaImage),
    );
    final size = tester.getSize(picture);
    expect(size.width / size.height, closeTo(16 / 9, .01));
    expect(
      tester.getSemantics(picture),
      matchesSemantics(
        label: 'Полумесяц над минаретом на закате',
        isImage: true,
      ),
    );
    expect(requested.toSet().toList(), [
      '$_media/banners/2222222222bbbbbbbbbb-800.webp',
      // Not at hand: the other copy is tried, then the placeholder shows.
      '$_media/banners/2222222222bbbbbbbbbb.webp',
    ]);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);
    // No caption in the example; another banner has one.
    expect(find.byKey(_counter), findsNothing);
    await _pump(
      tester,
      _parse([
        {'type': 'banner', ..._slide('b', caption: 'Подпись к баннеру')},
      ]),
    );
    expect(
      tester.getRect(find.text('Подпись к баннеру')).top,
      greaterThan(tester.getRect(find.byType(LessonMediaImage)).bottom),
    );
    semantics.dispose();
  });

  testWidgets('pictures from another host leave their block out', (
    tester,
  ) async {
    final requested = await _pump(
      tester,
      _parse([
        {
          'type': 'banner',
          ..._slide('b'),
          'image': {
            ..._image('b', 1600, 900),
            'url': 'https://elsewhere.example/b.webp',
          },
        },
        {
          'type': 'slides',
          'slides': [
            _slide('ours'),
            {
              ..._slide('theirs'),
              'image': {
                ..._image('theirs', 1600, 900),
                'small_url': 'https://media.iqro.forum.example/t.webp',
              },
            },
          ],
        },
        {
          'type': 'slides',
          'slides': [_slide('one', caption: 'Один слайд')],
        },
      ]),
    );
    expect(find.byKey(const ValueKey('lesson-media-banner')), findsNothing);
    expect(find.byKey(_slides), findsOneWidget);
    // A single slide needs no arrows, dots or counter.
    expect(find.text('Один слайд'), findsOneWidget);
    expect(find.byKey(_next), findsNothing);
    expect(find.byKey(_counter), findsNothing);
    expect(requested.toSet(), {'$_media/slides/one-800.webp'});
  });

  group('kept for offline', () {
    final uri = Uri.parse('https://iqro.forum');

    test('the copies the lessons show, once each, from approved hosts', () {
      final media = [
        ..._exampleMedia('smysl-posta'),
        ..._exampleMedia('namerenie'),
        ..._exampleMedia('smysl-posta'),
        ..._parse([
          {
            'type': 'banner',
            ..._slide('x'),
            'image': {..._image('x', 1600, 900), 'url': 'https://x.example/x'},
          },
          {
            'type': 'banner',
            ..._slide('local'),
            'image': {
              ..._image('local', 1600, 900),
              'url': '/media/courses/banners/local.webp',
              'small_url': '/media/courses/banners/local-800.webp',
            },
          },
        ]),
      ];
      final small = LessonMediaPrefetcher(
        cache: FakeMediaCache(),
        apiBase: uri,
        framePixels: () => 720,
      );
      expect(small.urls(media), [
        '$_media/banners/2222222222bbbbbbbbbb-800.webp',
        '$_media/slides/1111111111aaaaaaaaaa-800.webp',
        '$_media/slides/3333333333cccccccccc-800.webp',
        'https://iqro.forum/media/courses/banners/local-800.webp',
      ]);
      final large = LessonMediaPrefetcher(
        cache: FakeMediaCache(),
        apiBase: uri,
        framePixels: () => 990,
      );
      expect(large.urls(_exampleMedia('namerenie')), [
        '$_media/slides/1111111111aaaaaaaaaa.webp',
        '$_media/slides/3333333333cccccccccc.webp',
      ]);
    });

    test(
      'fetches what is not kept yet; a failure does not stop the rest',
      () async {
        const first = '$_media/banners/2222222222bbbbbbbbbb-800.webp';
        const second = '$_media/slides/1111111111aaaaaaaaaa-800.webp';
        const third = '$_media/slides/3333333333cccccccccc-800.webp';
        final cache = FakeMediaCache(cached: {first}, failing: {second});
        final prefetcher = LessonMediaPrefetcher(
          cache: cache,
          apiBase: uri,
          framePixels: () => 720,
        );
        await prefetcher.keep([
          ..._exampleMedia('smysl-posta'),
          ..._exampleMedia('namerenie'),
        ]);
        expect(cache.downloads, [second, third]);
        expect(cache.cached, {first, third});

        // The next time only the one that failed.
        cache.failing.clear();
        await prefetcher.keep([
          ..._exampleMedia('smysl-posta'),
          ..._exampleMedia('namerenie'),
        ]);
        expect(cache.downloads, [second, third, second]);
      },
    );
  });
}

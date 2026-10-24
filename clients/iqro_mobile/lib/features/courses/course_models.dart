import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';

/// The document schema this app draws (docs/courses/README.md). A larger one
/// means new required fields or block types: the app asks to be updated.
const courseSchemaVersion = 1;

/// Course and lesson addresses: route segments and storage keys.
final _slug = RegExp(r'^[A-Za-z0-9_-]{1,100}$');

bool isCourseSlug(String value) => _slug.hasMatch(value);

/// The course is hidden, gone or not published in this language.
class CourseUnavailable implements Exception {
  const CourseUnavailable(this.slug);

  final String slug;

  @override
  String toString() => 'Course is not available: $slug';
}

/// The document has a newer schema than this app understands.
class CourseNeedsUpdate implements Exception {
  const CourseNeedsUpdate(this.schemaVersion);

  final int schemaVersion;

  @override
  String toString() => 'Course schema $schemaVersion needs an app update';
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is Map) return Map<String, Object?>.from(value);
  throw FormatException('Course field $name must be an object');
}

List<Object?> _list(Object? value, String name) {
  if (value is List) return value;
  throw FormatException('Course field $name must be a list');
}

String _string(Map<String, Object?> json, String name) {
  final value = json[name];
  if (value is String) return value;
  throw FormatException('Course field $name must be a string');
}

String _slugField(Map<String, Object?> json, String name) {
  final value = _string(json, name);
  if (isCourseSlug(value)) return value;
  throw FormatException('Course field $name is not a slug');
}

String _nonEmpty(Map<String, Object?> json, String name) {
  final value = _string(json, name);
  if (value.isNotEmpty) return value;
  throw FormatException('Course field $name must not be empty');
}

int _int(Map<String, Object?> json, String name, {int min = 0}) {
  final value = json[name];
  if (value is int && value >= min) return value;
  throw FormatException('Course field $name must be an integer');
}

List<String> _strings(Object? value, String name) => [
  for (final item in _list(value, name))
    if (item is String) item else throw FormatException('$name: not a string'),
];

/// A WebP cover, 16:9.
@immutable
class CourseCover {
  const CourseCover({
    required this.url,
    required this.thumbUrl,
    required this.width,
    required this.height,
  });

  static CourseCover? fromJson(Object? value) {
    if (value == null) return null;
    final json = _map(value, 'cover');
    final thumb = json['thumb_url'];
    return CourseCover(
      url: _nonEmpty(json, 'url'),
      thumbUrl: thumb is String && thumb.isNotEmpty ? thumb : null,
      width: _int(json, 'width', min: 1),
      height: _int(json, 'height', min: 1),
    );
  }

  final String url;
  final String? thumbUrl;
  final int width;
  final int height;

  /// The small copy for cards.
  String get cardUrl => thumbUrl ?? url;
}

/// A course of `GET /courses`.
@immutable
class CourseSummary {
  const CourseSummary({
    required this.slug,
    required this.version,
    required this.title,
    required this.summary,
    required this.source,
    required this.cover,
    required this.lessonCount,
    required this.minutes,
    required this.videoMinutes,
    required this.publishedAt,
  });

  factory CourseSummary.fromJson(Object? value) {
    final json = _map(value, 'courses[]');
    return CourseSummary(
      slug: _slugField(json, 'slug'),
      version: _nonEmpty(json, 'version'),
      title: _nonEmpty(json, 'title'),
      summary: _string(json, 'summary'),
      source: _string(json, 'source'),
      cover: CourseCover.fromJson(json['cover']),
      lessonCount: _int(json, 'lesson_count'),
      minutes: _int(json, 'minutes'),
      videoMinutes: _int(json, 'video_minutes'),
      publishedAt: _string(json, 'published_at'),
    );
  }

  final String slug;
  final String version;
  final String title;
  final String summary;
  final String source;
  final CourseCover? cover;
  final int lessonCount;
  final int minutes;
  final int videoMinutes;
  final String publishedAt;

  /// The same course as kept for reading offline: [version] names the
  /// stored document.
  CourseSummary withVersion(String version) => CourseSummary(
    slug: slug,
    version: version,
    title: title,
    summary: summary,
    source: source,
    cover: cover,
    lessonCount: lessonCount,
    minutes: minutes,
    videoMinutes: videoMinutes,
    publishedAt: publishedAt,
  );
}

/// Courses of one language, in the order of the list.
List<CourseSummary> parseCourseList(Object? payload) {
  final json = _map(payload, 'list');
  final courses = [
    for (final item in _list(json['courses'], 'courses'))
      CourseSummary.fromJson(item),
  ];
  if (courses.map((course) => course.slug).toSet().length != courses.length) {
    throw const FormatException('Course list repeats a course');
  }
  return courses;
}

/// The catalog as shown: [offline] when the list could not be refreshed and
/// only the courses kept on the device are listed.
@immutable
class CourseCatalog {
  const CourseCatalog({required this.courses, this.offline = false});

  final List<CourseSummary> courses;
  final bool offline;

  CourseSummary? course(String slug) =>
      courses.where((course) => course.slug == slug).firstOrNull;
}

/// `course` of the document.
@immutable
class CourseInfo {
  const CourseInfo({
    required this.slug,
    required this.version,
    required this.language,
    required this.languages,
    required this.title,
    required this.summary,
    required this.source,
    required this.cover,
    required this.publishedAt,
  });

  factory CourseInfo.fromJson(Object? value) {
    final json = _map(value, 'course');
    return CourseInfo(
      slug: _slugField(json, 'slug'),
      version: _nonEmpty(json, 'version'),
      language: _nonEmpty(json, 'language'),
      languages: _strings(json['languages'], 'languages'),
      title: _nonEmpty(json, 'title'),
      summary: _string(json, 'summary'),
      source: _string(json, 'source'),
      cover: CourseCover.fromJson(json['cover']),
      publishedAt: _string(json, 'published_at'),
    );
  }

  final String slug;
  final String version;
  final String language;
  final List<String> languages;
  final String title;
  final String summary;
  final String source;
  final CourseCover? cover;
  final String publishedAt;
}

/// The poster of a lesson video, WebP 1280 and 640 px.
@immutable
class CourseVideoPoster {
  const CourseVideoPoster({
    required this.url,
    required this.smallUrl,
    required this.width,
    required this.height,
  });

  factory CourseVideoPoster.fromJson(Object? value) {
    final json = _map(value, 'poster');
    return CourseVideoPoster(
      url: _nonEmpty(json, 'url'),
      smallUrl: _nonEmpty(json, 'small_url'),
      width: _int(json, 'width', min: 1),
      height: _int(json, 'height', min: 1),
    );
  }

  final String url;
  final String smallUrl;
  final int width;
  final int height;
}

/// The video of a lesson: the server already chose the file for the
/// language of the document, a dub or the main one.
@immutable
class CourseVideo {
  const CourseVideo({
    required this.url,
    required this.bytes,
    required this.duration,
    required this.width,
    required this.height,
    required this.spokenLanguage,
    required this.poster,
  });

  static CourseVideo? fromJson(Object? value) {
    if (value == null) return null;
    final json = _map(value, 'video');
    return CourseVideo(
      url: _nonEmpty(json, 'url'),
      bytes: _int(json, 'bytes', min: 1),
      duration: Duration(milliseconds: _int(json, 'duration_ms', min: 1)),
      width: _int(json, 'width', min: 1),
      height: _int(json, 'height', min: 1),
      spokenLanguage: _string(json, 'spoken_language'),
      poster: CourseVideoPoster.fromJson(json['poster']),
    );
  }

  final String url;
  final int bytes;
  final Duration duration;
  final int width;
  final int height;

  /// The language of the sound, `""` for a video without speech.
  final String spokenLanguage;
  final CourseVideoPoster poster;

  double get aspectRatio => width / height;
}

/// A picture of a slide or a banner: WebP, [url] up to 1600 px on the
/// longer side and [smallUrl] up to 800 px. [width] and [height] are of the
/// large one.
@immutable
class LessonImage {
  const LessonImage({
    required this.url,
    required this.smallUrl,
    required this.width,
    required this.height,
  });

  factory LessonImage.fromJson(Object? value) {
    final json = _map(value, 'image');
    return LessonImage(
      url: _nonEmpty(json, 'url'),
      smallUrl: _nonEmpty(json, 'small_url'),
      width: _int(json, 'width', min: 1),
      height: _int(json, 'height', min: 1),
    );
  }

  final String url;
  final String smallUrl;
  final int width;
  final int height;
}

TextDirection _direction(Map<String, Object?> json) => switch (json['dir']) {
  'ltr' => TextDirection.ltr,
  'rtl' => TextDirection.rtl,
  _ => throw const FormatException('Course block has no direction'),
};

/// A slide or a banner: the image, the caption under it in [direction], and
/// [alt] for the screen reader (`""` for a decorative picture).
@immutable
class LessonPicture {
  const LessonPicture({
    required this.image,
    required this.caption,
    required this.alt,
    required this.direction,
  });

  factory LessonPicture.fromJson(Object? value) {
    final json = _map(value, 'picture');
    return LessonPicture(
      image: LessonImage.fromJson(json['image']),
      caption: _string(json, 'caption'),
      alt: _string(json, 'alt'),
      direction: _direction(json),
    );
  }

  final LessonImage image;
  final String caption;
  final String alt;
  final TextDirection direction;
}

/// A block of the media above the notes, in the author's order.
sealed class LessonMedia {
  const LessonMedia();
}

class LessonVideoMedia extends LessonMedia {
  const LessonVideoMedia(this.video);

  final CourseVideo video;
}

class LessonSlidesMedia extends LessonMedia {
  const LessonSlidesMedia(this.slides);

  /// At least one.
  final List<LessonPicture> slides;
}

/// A 16:9 picture with a caption under it.
class LessonBannerMedia extends LessonMedia {
  const LessonBannerMedia(this.picture);

  final LessonPicture picture;
}

/// `lessons[].media`. A document prepared before media has none: then it is
/// the lesson's [video], if any. A block of an unknown type and slides
/// without a slide are left out; they do not make the document invalid.
List<LessonMedia> parseLessonMedia(Object? value, {CourseVideo? video}) {
  if (value == null) {
    return List.unmodifiable([if (video != null) LessonVideoMedia(video)]);
  }
  final media = <LessonMedia>[];
  for (final item in _list(value, 'media')) {
    final json = _map(item, 'media[]');
    switch (json['type']) {
      case 'video':
        final video = CourseVideo.fromJson(json['video']);
        if (video == null) throw const FormatException('Video block is empty');
        media.add(LessonVideoMedia(video));
      case 'slides':
        final slides = [
          for (final slide in _list(json['slides'], 'slides'))
            LessonPicture.fromJson(slide),
        ];
        if (slides.isNotEmpty) {
          media.add(LessonSlidesMedia(List.unmodifiable(slides)));
        }
      case 'banner':
        media.add(LessonBannerMedia(LessonPicture.fromJson(json)));
      default:
      // Added later; this app does not draw it.
    }
  }
  return List.unmodifiable(media);
}

@immutable
class CourseLesson {
  const CourseLesson({
    required this.slug,
    required this.number,
    required this.title,
    required this.summary,
    required this.minutes,
    required this.notes,
    required this.sources,
    this.video,
    this.media = const [],
  });

  factory CourseLesson.fromJson(Object? value) {
    final json = _map(value, 'lessons[]');
    final video = CourseVideo.fromJson(json['video']);
    return CourseLesson(
      slug: _slugField(json, 'slug'),
      number: _int(json, 'number', min: 1),
      title: _nonEmpty(json, 'title'),
      summary: _string(json, 'summary'),
      minutes: _int(json, 'minutes'),
      video: video,
      media: parseLessonMedia(json['media'], video: video),
      notes: parseNoteBlocks(json['notes']),
      sources: _strings(json['sources'], 'sources'),
    );
  }

  final String slug;
  final int number;
  final String title;
  final String summary;
  final int minutes;
  final CourseVideo? video;

  /// Above the notes, in order; [video] is among them.
  final List<LessonMedia> media;
  final List<NoteBlock> notes;
  final List<String> sources;
}

/// `GET /courses/{slug}`: one published version in one language.
@immutable
class CourseDocument {
  const CourseDocument({required this.course, required this.lessons});

  /// Throws [CourseNeedsUpdate] for a newer schema and [FormatException]
  /// for a document that does not fit. Unknown fields are ignored.
  factory CourseDocument.fromJson(Object? payload) {
    final json = _map(payload, 'document');
    final schema = json['schema_version'];
    if (schema is int && schema > courseSchemaVersion) {
      throw CourseNeedsUpdate(schema);
    }
    if (schema != courseSchemaVersion) {
      throw const FormatException('Unknown course schema');
    }
    final lessons = [
      for (final item in _list(json['lessons'], 'lessons'))
        CourseLesson.fromJson(item),
    ];
    if (lessons.map((lesson) => lesson.slug).toSet().length != lessons.length) {
      throw const FormatException('Course repeats a lesson');
    }
    return CourseDocument(
      course: CourseInfo.fromJson(json['course']),
      lessons: List.unmodifiable(lessons),
    );
  }

  final CourseInfo course;

  /// In the order of the course.
  final List<CourseLesson> lessons;

  int indexOf(String lesson) =>
      lessons.indexWhere((candidate) => candidate.slug == lesson);

  CourseLesson? lesson(String slug) {
    final index = indexOf(slug);
    return index < 0 ? null : lessons[index];
  }

  CourseLesson? previous(String slug) {
    final index = indexOf(slug);
    return index > 0 ? lessons[index - 1] : null;
  }

  CourseLesson? next(String slug) {
    final index = indexOf(slug);
    return index >= 0 && index + 1 < lessons.length ? lessons[index + 1] : null;
  }
}

/// A run of text of one kind: bold, and Arabic script drawn in the Arabic
/// font with its direction isolated.
@immutable
class NoteSegment {
  const NoteSegment(this.text, {this.bold = false, this.arabic = false});

  factory NoteSegment.fromJson(Object? value) {
    final json = _map(value, 'segment');
    final bold = json['bold'] ?? false;
    final lang = json['lang'];
    if (bold is! bool || (lang != null && lang != 'ar')) {
      throw const FormatException('Note segment does not fit');
    }
    return NoteSegment(_string(json, 'text'), bold: bold, arabic: lang == 'ar');
  }

  final String text;
  final bool bold;
  final bool arabic;
}

/// One line of a block.
typedef NoteLine = List<NoteSegment>;

/// A block of the notes; the server parses the author's markup into them.
sealed class NoteBlock {
  const NoteBlock(this.direction);

  final TextDirection direction;
}

class NoteHeading extends NoteBlock {
  const NoteHeading(super.direction, this.text);

  final NoteLine text;
}

class NoteParagraph extends NoteBlock {
  const NoteParagraph(super.direction, this.lines);

  final List<NoteLine> lines;
}

class NoteList extends NoteBlock {
  const NoteList(super.direction, {required this.ordered, required this.items});

  /// The client draws the numbers.
  final bool ordered;
  final List<NoteLine> items;
}

class NoteQuote extends NoteBlock {
  const NoteQuote(super.direction, this.lines, this.source);

  final List<NoteLine> lines;
  final String? source;
}

/// «Important».
class NoteCallout extends NoteBlock {
  const NoteCallout(super.direction, this.lines);

  final List<NoteLine> lines;
}

List<NoteBlock> parseNoteBlocks(Object? value) =>
    List.unmodifiable([for (final item in _list(value, 'notes')) _block(item)]);

NoteLine _line(Object? value) => List.unmodifiable([
  for (final segment in _list(value, 'line')) NoteSegment.fromJson(segment),
]);

List<NoteLine> _lines(Object? value, String name) =>
    List.unmodifiable([for (final line in _list(value, name)) _line(line)]);

NoteBlock _block(Object? value) {
  final json = _map(value, 'block');
  final direction = switch (json['dir']) {
    'ltr' => TextDirection.ltr,
    'rtl' => TextDirection.rtl,
    _ => throw const FormatException('Note block has no direction'),
  };
  return switch (json['type']) {
    'heading' => NoteHeading(direction, _line(json['text'])),
    'paragraph' => NoteParagraph(direction, _lines(json['lines'], 'lines')),
    'list' => NoteList(
      direction,
      ordered: switch (json['ordered']) {
        final bool ordered => ordered,
        _ => throw const FormatException('List has no order'),
      },
      items: _lines(json['items'], 'items'),
    ),
    'quote' => NoteQuote(
      direction,
      _lines(json['lines'], 'lines'),
      switch (json['source']) {
        null => null,
        final String source => source,
        _ => throw const FormatException('Quote source is not a string'),
      },
    ),
    'note' => NoteCallout(direction, _lines(json['lines'], 'lines')),
    // A new block type comes with a larger schema_version.
    _ => throw const FormatException('Unknown note block'),
  };
}

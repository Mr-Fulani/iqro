// Practice tasks of the tests, built from the lesson examples of
// tajweed_course_test_data.dart in the form of
// `GET /tajweed/courses/<slug>/practice` (docs/tajweed/practice.md).
import 'tajweed_course_test_data.dart';

Map<String, Object?> tajweedPracticeTaskJson(
  String type,
  String lesson,
  String verseKey,
  String target, {
  bool review = false,
  int focus = 0,
  List<String>? options,
}) => <String, Object?>{
  'key': '$type~$verseKey~$target',
  'type': type,
  'target': target,
  'review': review,
  'example': tajweedCourseExamplesJson(
    lesson,
  ).cast<Map<String, Object?>>().firstWhere((e) => e['verse_key'] == verseKey),
  'focus': focus,
  'options': ?options,
};

/// A «find» back for review, an «identify» and a «listen».
Map<String, Object?> tajweedPracticeTasksJson() => <String, Object?>{
  'seed': 42,
  'tasks': [
    tajweedPracticeTaskJson('find', 'izhar', '80:18', 'izhar', review: true),
    tajweedPracticeTaskJson(
      'identify',
      'idgham-ghunnah',
      '80:13',
      'idgham_ghunnah',
      options: ['izhar', 'idgham_ghunnah', 'ikhafa_shafawi'],
    ),
    tajweedPracticeTaskJson(
      'listen',
      'ikhfa-shafawi',
      '96:14',
      'ikhafa_shafawi',
      options: ['ikhafa_shafawi', 'izhar', 'idgham_ghunnah'],
    ),
  ],
};

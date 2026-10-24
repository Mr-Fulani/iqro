import 'dart:convert';
import 'dart:io';

import 'package:iqro_mobile/core/network/api_exception.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/courses/course_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// The shared examples of docs/courses, the same files the site and the
/// backend test with.
Object? courseDocsJson(String name) =>
    jsonDecode(File('../../docs/courses/$name').readAsStringSync());

Map<String, Object?> courseListJson() => Map<String, Object?>.from(
  courseDocsJson('course-list.example.json')! as Map,
);

Map<String, Object?> courseDocumentJson() => Map<String, Object?>.from(
  courseDocsJson('course-document.example.json')! as Map,
);

/// [courseDocumentJson] as another published version.
Map<String, Object?> courseDocumentVersion(String version) {
  final json = courseDocumentJson();
  (json['course']! as Map)['version'] = version;
  return json;
}

Map<String, Object?> courseListVersion(String version) {
  final json = courseListJson();
  ((json['courses']! as List).single as Map)['version'] = version;
  return json;
}

const offlineError = ApiException(message: 'offline');
const notFoundError = ApiException(message: 'Not found', statusCode: 404);

class FakeCourseGateway implements CourseRemoteGateway {
  FakeCourseGateway({Object? list, Map<String, Object?>? documents})
    : list = list ?? courseListJson(),
      documents = documents ?? {'1': courseDocumentJson()};

  /// The list answer, or an exception to throw.
  Object? list;

  /// Documents by the version the list names; an exception is thrown.
  Map<String, Object?> documents;

  /// An exception every document request throws.
  Object? documentError;

  final listRequests = <String>[];
  final documentRequests = <String>[];

  @override
  Future<Object?> courses(String language) async {
    listRequests.add(language);
    final answer = list;
    if (answer is Exception) throw answer;
    return jsonDecode(jsonEncode(answer));
  }

  @override
  Future<Object?> course(String slug, String language) async {
    documentRequests.add('$slug.$language');
    if (documentError case final error?) throw error;
    final listed = (list is Map ? (list! as Map)['courses'] : null) as List?;
    final version =
        listed
            ?.whereType<Map>()
            .where((course) => course['slug'] == slug)
            .firstOrNull?['version'] ??
        '1';
    final answer = documents[version];
    if (answer == null) throw notFoundError;
    return jsonDecode(jsonEncode(answer));
  }
}

Future<(Database, LocalDatabase)> openCourseTestDatabase() async {
  sqfliteFfiInit();
  final sql = await databaseFactoryFfi.openDatabase(inMemoryDatabasePath);
  await sql.execute('''
    CREATE TABLE app_state (
      owner_id TEXT NOT NULL,
      state_key TEXT NOT NULL,
      payload TEXT NOT NULL,
      updated_at TEXT NOT NULL,
      PRIMARY KEY (owner_id, state_key)
    )
  ''');
  await sql.execute('''
    CREATE TABLE cache_entries (
      cache_key TEXT PRIMARY KEY,
      payload TEXT NOT NULL,
      etag TEXT,
      updated_at TEXT NOT NULL,
      expires_at TEXT
    )
  ''');
  return (sql, LocalDatabase.forTesting(sql));
}

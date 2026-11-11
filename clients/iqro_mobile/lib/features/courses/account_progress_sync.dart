import '../../core/auth/account_scope.dart';
import '../../core/auth/auth_session.dart';
import '../../core/storage/local_database.dart';
import '../../core/utils/json_helpers.dart';
import '../tajweed_course/tajweed_course_progress.dart';

/// `PUT /me/courses/progress/<kind>/<course>`: the server merges and answers
/// with the result.
typedef SaveCourseProgress =
    Future<Object?> Function(
      String kind,
      String course,
      Map<String, Object?> body, {
      AccountScopeSnapshot? accountScope,
    });

/// Sends the local progress of the prayer course or a topical course to the
/// account and keeps the merged answer.
///
/// Only for a signed-in account: a guest's progress stays on the device.
/// Failures are silent: without a network the progress stays local until
/// the next time.
class AccountProgressSync {
  AccountProgressSync({
    required SaveCourseProgress save,
    required LocalDatabase database,
    required AuthSession? Function() session,
    required Future<void> Function(
      String kind,
      String course,
      Map<String, Object?> answer,
      AccountScopeSnapshot accountScope,
    )
    merge,
    void Function(String kind, String course)? onMerged,
  }) : _save = save,
       _database = database,
       _session = session,
       _merge = merge,
       _onMerged = onMerged;

  /// The first part of the `app_state` key and of the address.
  static const salah = 'salah';
  static const courses = 'courses';

  final SaveCourseProgress _save;
  final LocalDatabase _database;
  final AuthSession? Function() _session;

  /// Merges the server's copy into the local one through its store.
  final Future<void> Function(
    String kind,
    String course,
    Map<String, Object?> answer,
    AccountScopeSnapshot accountScope,
  )
  _merge;

  /// Lets the screens that show the progress read it again.
  final void Function(String kind, String course)? _onMerged;

  /// Whether the progress was synchronized.
  Future<bool> sync(String kind, String course) async {
    try {
      final session = _session();
      if (session == null || session.userStatus != 'active') return false;
      final scope = await _database.captureAccount();
      if (scope.userId != session.userId) return false;
      final local = await _database.readState(
        '$kind.progress.$course',
        accountScope: scope,
      );
      final lessons = local?['lessons'];
      final answer = await _save(kind, course, <String, Object?>{
        'lessons': <String, Object?>{
          if (lessons is Map)
            for (final MapEntry(:key, :value) in lessons.entries)
              // The server refuses a lesson not started or without its time.
              if (TajweedLessonProgress.tryParse(value) case final entry?
                  when key is String && entry.updatedAt.isNotEmpty)
                key: entry.toJson(),
        },
      }, accountScope: scope);
      await _merge(kind, course, jsonMap(answer), scope);
      _onMerged?.call(kind, course);
      return true;
    } on Object {
      return false;
    }
  }
}

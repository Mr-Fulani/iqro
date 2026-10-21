import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/feedback/feedback_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(sqfliteFfiInit);

  test('a Turkish reader files feedback in Turkish', () async {
    final sqlDatabase = await databaseFactoryFfi.openDatabase(
      inMemoryDatabasePath,
    );
    addTearDown(sqlDatabase.close);
    final accountScope = AccountScope.forTesting();
    final api = _RecordingApi(
      AuthRepository(config: _config, accountScope: accountScope),
    );
    final repository = FeedbackRepository(
      api: api,
      database: LocalDatabase.forTesting(
        sqlDatabase,
        accountScope: accountScope,
      ),
      locale: () => 'tr',
    );

    await repository.create(
      category: 'other',
      subject: 'Konu',
      message: 'Mesaj',
    );

    expect(api.posted?['locale'], 'tr');
  });
}

const _config = AppConfig(
  apiBaseUrl: 'https://iqro.forum',
  fallbackDownloadUrl: 'https://iqro.forum',
  environment: 'production',
);

class _RecordingApi extends ApiClient {
  _RecordingApi(AuthRepository auth)
    : super(config: _config, authRepository: auth, locale: () => 'tr');

  Map<String, Object?>? posted;

  @override
  Future<Object?> post(
    String path, {
    Object? data,
    bool public = false,
    AccountScopeSnapshot? accountScope,
  }) async {
    posted = data! as Map<String, Object?>;
    return <String, Object?>{
      'public_id': 'FB-tr',
      'category': 'other',
      'subject': 'Konu',
      'status': 'new',
      'priority': 'normal',
      'locale': 'tr',
      'channel': 'android',
      'created_at': '2026-10-21T09:00:00Z',
      'updated_at': '2026-10-21T09:00:00Z',
      'messages': <Object?>[],
    };
  }
}

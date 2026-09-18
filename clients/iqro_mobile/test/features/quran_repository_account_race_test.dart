import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/account_scope.dart';
import 'package:iqro_mobile/core/auth/auth_repository.dart';
import 'package:iqro_mobile/core/config/app_config.dart';
import 'package:iqro_mobile/core/network/api_client.dart';
import 'package:iqro_mobile/core/storage/local_database.dart';
import 'package:iqro_mobile/features/quran/quran_repository.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  setUpAll(sqfliteFfiInit);

  test(
    'a stale reader scope cannot save a position into the next account',
    () async {
      final database = await databaseFactoryFfi.openDatabase(
        inMemoryDatabasePath,
      );
      addTearDown(database.close);
      await database.execute('''
      CREATE TABLE reading_positions (
        owner_id TEXT NOT NULL,
        edition TEXT NOT NULL,
        entity_id TEXT NOT NULL,
        surah INTEGER NOT NULL,
        ayah INTEGER NOT NULL,
        page INTEGER,
        server_revision INTEGER NOT NULL DEFAULT 0,
        dirty INTEGER NOT NULL DEFAULT 1,
        updated_at TEXT NOT NULL,
        PRIMARY KEY (owner_id, edition)
      )
    ''');
      await database.execute('''
      CREATE TABLE outbox (
        owner_id TEXT NOT NULL,
        operation_id TEXT NOT NULL,
        entity_type TEXT NOT NULL,
        entity_id TEXT,
        payload TEXT NOT NULL,
        attempts INTEGER NOT NULL DEFAULT 0,
        created_at TEXT NOT NULL,
        last_error TEXT,
        PRIMARY KEY (owner_id, operation_id)
      )
    ''');

      final accountScope = AccountScope.forTesting('owner-a');
      final local = LocalDatabase.forTesting(
        database,
        accountScope: accountScope,
      );
      const config = AppConfig(
        apiBaseUrl: 'https://iqro.forum',
        fallbackDownloadUrl: 'https://iqro.forum',
        environment: 'production',
      );
      final auth = AuthRepository(config: config, accountScope: accountScope);
      final repository = QuranRepository(
        api: ApiClient(
          config: config,
          authRepository: auth,
          locale: () => 'en',
        ),
        database: local,
      );

      final ownerA = await repository.captureAccount();
      accountScope.activate('owner-b');

      await expectLater(
        repository.savePosition(
          surah: 2,
          ayah: 7,
          page: 2,
          accountScope: ownerA,
        ),
        throwsA(isA<AccountScopeChanged>()),
      );
      await expectLater(
        repository.position(accountScope: ownerA),
        throwsA(isA<AccountScopeChanged>()),
      );
      expect(await database.query('reading_positions'), isEmpty);
      expect(await database.query('outbox'), isEmpty);
    },
  );
}

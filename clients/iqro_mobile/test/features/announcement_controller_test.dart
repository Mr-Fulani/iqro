import 'package:flutter_test/flutter_test.dart';
import 'package:iqro_mobile/core/auth/auth_session.dart';
import 'package:iqro_mobile/features/announcements/announcement_controller.dart';

import 'announcement_test_data.dart';

void main() {
  late FakeAnnouncementRepository repository;
  late DateTime now;
  AuthSession? session;

  AnnouncementsController controller() => AnnouncementsController(
    repository: () => repository,
    session: () => session,
    clock: () => now,
  );

  setUp(() {
    repository = FakeAnnouncementRepository(
      active: [testAnnouncement(), featureAnnouncement()],
    );
    now = DateTime.utc(2026, 10, 22, 10);
    session = null;
  });

  test('the bubble counts one impression per visit', () async {
    final store = controller();
    await store.load('ru');
    final items = store.state.bubble(signedIn: false);
    expect(items, hasLength(2));

    store.recordShown(items);
    store.recordShown(items);
    expect(store.state.local.bubble[announcementIdA]!.shown, 1);
    expect(repository.events, [
      '$announcementIdA:bubble:impression:1',
      '$announcementIdB:bubble:impression:1',
    ]);
    // Still on screen during this visit, and saved for the next launch.
    expect(store.state.bubble(signedIn: false), hasLength(2));
    expect(repository.stored.bubble.keys, [announcementIdA, announcementIdB]);
  });

  test('a guest reads on this device only', () async {
    final store = controller();
    await store.load('ru');
    await store.read(testAnnouncement(), 'bubble', opened: true);
    expect(store.state.bubble(signedIn: false).map((item) => item.id), [
      announcementIdB,
    ]);
    expect(repository.events, ['$announcementIdA:bubble:open:1']);
    expect(repository.sentReceipts, isEmpty);
    expect(repository.receiptRequests, 0);
  });

  test('marks of a signed-in person are synced with their wave', () async {
    session = testSession();
    // Read on another device in wave 2 of the second announcement.
    repository.receiptsPayload = <String, Object?>{
      'results': <Object?>[
        <String, Object?>{
          'announcement_id': announcementIdB,
          'read_at': '2026-10-21T09:00:00Z',
          'dismissed_at': null,
          'wave': 2,
        },
      ],
    };
    repository.activeItems = [
      testAnnouncement(<String, Object?>{'wave': 3}),
      testAnnouncement(<String, Object?>{'id': announcementIdB, 'wave': 2}),
    ];
    final store = controller();
    await store.load('ru');
    expect(repository.receiptRequests, 1);
    expect(store.state.bubble(signedIn: true).map((item) => item.id), [
      announcementIdA,
    ]);

    await store.click(repository.activeItems.first, 'bubble');
    expect(repository.sentReceipts, [
      <String, Object?>{'id': announcementIdA, 'read': true, 'wave': 3},
    ]);
    expect(repository.events, ['$announcementIdA:bubble:click:3']);
    // Read twice in the same wave: nothing new to send.
    await store.read(repository.activeItems.first, 'feed');
    expect(repository.sentReceipts, hasLength(1));

    // «Показать снова»: wave 3 of the second one is back for this person.
    repository.activeItems = [
      testAnnouncement(<String, Object?>{'wave': 3}),
      testAnnouncement(<String, Object?>{'id': announcementIdB, 'wave': 3}),
    ];
    await store.load('ru', refresh: true);
    expect(store.state.bubble(signedIn: true).map((item) => item.id), [
      announcementIdB,
    ]);
    await store.dismiss(repository.activeItems.last, 'card');
    expect(repository.sentReceipts.last, <String, Object?>{
      'id': announcementIdB,
      'dismissed': true,
      'wave': 3,
    });

    // Receipts are fetched once per person, again after switching accounts.
    await store.syncReceipts();
    expect(repository.receiptRequests, 1);
    session = testSession(userId: 'user-2');
    await store.syncReceipts();
    expect(repository.receiptRequests, 2);
  });

  test('coming back after half an hour is a new visit', () async {
    final daily = testAnnouncement(<String, Object?>{
      'bubble': <String, Object?>{
        'icon': 'portrait',
        'frequency': 'each_visit',
        'max_impressions': 2,
      },
    });
    repository.activeItems = [daily];
    final store = controller();
    await store.load('ru');
    store.recordShown(store.state.bubble(signedIn: false));

    store.left();
    expect(repository.flushes, 1);
    now = now.add(const Duration(minutes: 10));
    expect(store.returned(), isFalse);
    store.recordShown(store.state.bubble(signedIn: false));
    expect(store.state.local.bubble[announcementIdA]!.shown, 1);

    store.left();
    now = now.add(const Duration(minutes: 31));
    expect(store.returned(), isTrue);
    store.recordShown(store.state.bubble(signedIn: false));
    expect(store.state.local.bubble[announcementIdA]!.shown, 2);

    // The admin's limit of two shows is reached.
    store.left();
    now = now.add(const Duration(hours: 1));
    expect(store.returned(), isTrue);
    expect(store.state.bubble(signedIn: false), isEmpty);
    // The feed still has it, unread.
    expect(store.state.unread(signedIn: false), 1);
  });

  test('without the network the bubble stays quiet', () async {
    repository.offline = true;
    final store = controller();
    await store.load('ru');
    expect(store.state.loaded, isTrue);
    expect(store.state.bubble(signedIn: false), isEmpty);
  });

  test('marks saved on this device come back after a restart', () async {
    final first = controller();
    await first.load('ru');
    await first.read(testAnnouncement(), 'bubble');
    final second = controller();
    await second.load('ru');
    expect(second.state.bubble(signedIn: false).map((item) => item.id), [
      announcementIdB,
    ]);
  });
}
